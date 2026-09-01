--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][CraftingService] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))

local recipesModule = Config:WaitForChild("Recipes")
if not recipesModule:IsA("ModuleScript") then
	error("[ODDWORKS][CraftingService] Server.Config.Recipes must be a ModuleScript.")
end

local Recipes = require(recipesModule)

type RecipeDefinition = {
	RecipeId: string,
	ScrapCost: number,
	OutputSpeciesId: string,
}

type CraftResultCode =
	"CRAFT_SUCCESS"
	| "NOT_ENOUGH_SCRAP"
	| "RECIPE_LOCKED"
	| "INVALID_RECIPE"
	| "RATE_LIMITED"
	| "CRAFT_FAILED"

local CRAFT_REQUEST_INTERVAL_SECONDS = 0.5
local MAX_RECIPE_ID_LENGTH = 48
local OWNERSHIP_INCREMENT = 1

local RESULT_SUCCESS: CraftResultCode = "CRAFT_SUCCESS"
local RESULT_NOT_ENOUGH_SCRAP: CraftResultCode = "NOT_ENOUGH_SCRAP"
local RESULT_RECIPE_LOCKED: CraftResultCode = "RECIPE_LOCKED"
local RESULT_INVALID_RECIPE: CraftResultCode = "INVALID_RECIPE"
local RESULT_RATE_LIMITED: CraftResultCode = "RATE_LIMITED"
local RESULT_CRAFT_FAILED: CraftResultCode = "CRAFT_FAILED"

local CraftingService = {}

-- CraftingService owns crafting decisions, not player state. Its private throttle
-- tracks request timing so a client cannot spam state-changing craft attempts.
local craftRequest: RemoteEvent? = nil
local craftResult: RemoteEvent? = nil
local lastCraftRequestTimes: { [Player]: number } = {}
local started = false

-- Verifies required networking/config objects without creating a generic networking framework.
-- A missing remote should fail loudly because crafting depends on a narrow, documented contract.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][CraftingService] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end

	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][CraftingService] %s.%s must be a %s, but found %s.",
				parent:GetFullName(),
				childName,
				expectedClassName,
				child.ClassName
			),
			2
		)
	end

	return child
end

-- Sends one server-generated result code to the requesting client.
-- The client maps codes to display text; it does not receive internal server errors or authority.
local function sendCraftResult(player: Player, resultCode: CraftResultCode)
	if player.Parent ~= Players then
		return
	end

	local resultRemote = craftResult
	if not resultRemote then
		return
	end

	resultRemote:FireClient(player, resultCode)
end

-- Limits state-changing craft requests to a small legitimate pace.
-- This is separate from affordability checks because rate limits defend server work, not balances.
local function passesCraftThrottle(player: Player): boolean
	local now = os.clock()
	local lastRequestTime = lastCraftRequestTimes[player]

	if lastRequestTime ~= nil and now - lastRequestTime < CRAFT_REQUEST_INTERVAL_SECONDS then
		return false
	end

	lastCraftRequestTimes[player] = now
	return true
end

-- Accepts only the single recipeId string payload allowed by the CraftRequest contract.
-- Cost, quantity, output, rarity, mutation, size, and Player identity are never accepted from the client.
local function readRecipeId(...: any): string?
	if select("#", ...) ~= 1 then
		return nil
	end

	local recipeId = select(1, ...)
	if typeof(recipeId) ~= "string" then
		return nil
	end

	if #recipeId <= 0 or #recipeId > MAX_RECIPE_ID_LENGTH then
		return nil
	end

	return recipeId
end

-- Performs the server-authoritative transaction with an explicit refund path.
-- Ownership is recorded before any physical Toastmarshal exists so the economy can be verified first.
local function executeCraftTransaction(player: Player, recipe: RecipeDefinition): CraftResultCode
	if not PlayerStateService.IsRecipeUnlocked(player, recipe.RecipeId) then
		return RESULT_RECIPE_LOCKED
	end

	if not PlayerStateService.CanAffordScrap(player, recipe.ScrapCost) then
		return RESULT_NOT_ENOUGH_SCRAP
	end

	local didSpendScrap = PlayerStateService.SpendScrap(player, recipe.ScrapCost)
	if not didSpendScrap then
		return RESULT_NOT_ENOUGH_SCRAP
	end

	local didRecordOwnership = PlayerStateService.AddOwnedOddling(player, recipe.OutputSpeciesId, OWNERSHIP_INCREMENT)
	if not didRecordOwnership then
		local didRefund = PlayerStateService.AddScrap(player, recipe.ScrapCost)
		if not didRefund then
			warn(string.format("[ODDWORKS][CraftingService] Failed to refund Scrap after craft rollback for %s.", player.Name))
		end

		return RESULT_CRAFT_FAILED
	end

	local snapshot = PlayerStateService.GetSnapshot(player)
	local ownedCount = if snapshot then snapshot.OwnedOddlings[recipe.OutputSpeciesId] or 0 else 0
	print(
		string.format(
			"[ODDWORKS][CraftingService] %s crafted %s (-%d Scrap, owned: %d)",
			player.Name,
			recipe.OutputSpeciesId,
			recipe.ScrapCost,
			ownedCount
		)
	)

	return RESULT_SUCCESS
end

-- Handles the client request as an untrusted recipe request.
-- Roblox supplies the Player; the client only supplies the bounded recipeId string.
local function handleCraftRequest(player: Player, ...: any)
	if not passesCraftThrottle(player) then
		sendCraftResult(player, RESULT_RATE_LIMITED)
		return
	end

	local recipeId = readRecipeId(...)
	if not recipeId then
		sendCraftResult(player, RESULT_INVALID_RECIPE)
		return
	end

	local recipe = Recipes.GetRecipe(recipeId) :: RecipeDefinition?
	if not recipe then
		sendCraftResult(player, RESULT_INVALID_RECIPE)
		return
	end

	if not PlayerStateService.HasState(player) then
		sendCraftResult(player, RESULT_CRAFT_FAILED)
		return
	end

	local resultCode = executeCraftTransaction(player, recipe)
	sendCraftResult(player, resultCode)
end

-- Starts the crafting transaction boundary once.
-- No physical models are spawned here; Pass 5 is only request validation, Scrap spending, and ownership count.
function CraftingService.Start()
	if started then
		return
	end

	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local requestRemote = requireChildOfClass(networkFolder, "CraftRequest", "RemoteEvent") :: RemoteEvent
	local resultRemote = requireChildOfClass(networkFolder, "CraftResult", "RemoteEvent") :: RemoteEvent
	craftRequest = requestRemote
	craftResult = resultRemote

	requestRemote.OnServerEvent:Connect(handleCraftRequest)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastCraftRequestTimes[player] = nil
	end)

	print("[ODDWORKS][CraftingService] Service started.")
end

return CraftingService
