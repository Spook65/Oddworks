--!strict

local Players = game:GetService("Players")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][ProgressionService] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))

local recipesModule = Config:WaitForChild("Recipes")
if not recipesModule:IsA("ModuleScript") then
	error("[ODDWORKS][ProgressionService] Server.Config.Recipes must be a ModuleScript.")
end

local Recipes = require(recipesModule)

type RecipeDefinition = {
	RecipeId: string,
	ScrapCost: number,
	OutputSpeciesId: string,
	RequiredWorkshopLevel: number,
	IsCraftingEnabled: boolean,
}

local ProgressionService = {}

-- This server-private guard prevents UnlockRecipe's state notification from
-- recursively starting another reconciliation for the same player.
local reconcilingPlayers: { [Player]: boolean } = {}
local started = false

-- Reconstructs level-based recipe unlocks from authoritative state and config.
-- It does not decide craftability; disabled recipes can be revealed/unlocked safely.
local function reconcilePlayer(player: Player)
	if reconcilingPlayers[player] then
		return
	end

	reconcilingPlayers[player] = true
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot then
		reconcilingPlayers[player] = nil
		return
	end

	local unlockedCount = 0
	for _, recipe in ipairs(Recipes.GetAllRecipes() :: { RecipeDefinition }) do
		if snapshot.WorkshopLevel >= recipe.RequiredWorkshopLevel and not snapshot.UnlockedRecipes[recipe.RecipeId] then
			if PlayerStateService.UnlockRecipe(player, recipe.RecipeId) then
				unlockedCount += 1
			end
		end
	end

	if unlockedCount > 0 then
		print(
			string.format(
				"[ODDWORKS][ProgressionService] Reconciled %d recipe unlock(s) for %s at Workshop Level %d.",
				unlockedCount,
				player.Name,
				snapshot.WorkshopLevel
			)
		)
	end

	reconcilingPlayers[player] = nil
end

-- Starts progression after PlayerStateService so existing and future state can
-- reconstruct unlocks without depending on a one-time workshop-upgrade callback.
function ProgressionService.Start()
	if started then
		return
	end

	started = true
	PlayerStateService.ObserveStateChanged(reconcilePlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		reconcilingPlayers[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		reconcilePlayer(player)
	end

	print("[ODDWORKS][ProgressionService] Service started.")
end

return ProgressionService
