--!strict

local Players = game:GetService("Players")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][PlayerState] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")

local workshopLevelsModule = Config:WaitForChild("WorkshopLevels")
if not workshopLevelsModule:IsA("ModuleScript") then
	error("[ODDWORKS][PlayerState] Server.Config.WorkshopLevels must be a ModuleScript.")
end

local WorkshopLevels = require(workshopLevelsModule)

local recipesModule = Config:WaitForChild("Recipes")
if not recipesModule:IsA("ModuleScript") then
	error("[ODDWORKS][PlayerState] Server.Config.Recipes must be a ModuleScript.")
end

local Recipes = require(recipesModule)

local oddlingsModule = Config:WaitForChild("Oddlings")
if not oddlingsModule:IsA("ModuleScript") then
	error("[ODDWORKS][PlayerState] Server.Config.Oddlings must be a ModuleScript.")
end

local Oddlings = require(oddlingsModule)

export type OddlingCounts = { [string]: number }
export type RecipeUnlocks = { [string]: boolean }

export type PlayerState = {
	Scrap: number,
	Hype: number,
	WorkshopLevel: number,
	AssignedPlotId: string?,
	OwnedOddlings: OddlingCounts,
	UnlockedRecipes: RecipeUnlocks,
}

export type InitialPlayerState = {
	Scrap: number,
	Hype: number,
	WorkshopLevel: number,
	OwnedOddlings: OddlingCounts,
}

local PlayerStateService = {}

local STARTING_RECIPE_ID = "Toastmarshal"
local MAX_OWNED_ODDLING_ID_LENGTH = 64
local MAX_RECIPE_ID_LENGTH = 48
local MAX_SAFE_INTEGER = 9_007_199_254_740_991

-- This table is intentionally server-private. Future clients may receive
-- sanitized copies, but they must never own the authoritative progression data.
local playerStates: { [Player]: PlayerState } = {}
-- This BindableEvent stays server-internal. Other server services may observe
-- state changes, but clients cannot fire it or use it to mutate PlayerState.
local stateChangedEvent = Instance.new("BindableEvent")
local started = false

-- Notifies server-only listeners that a player's authoritative state changed.
-- Keeping the Fire call private prevents unrelated services from spoofing state updates.
local function notifyStateChanged(player: Player)
	stateChangedEvent:Fire(player)
end

-- Validates server-approved currency amounts before they touch authoritative state.
-- Even server callers can contain bugs, so mutation APIs fail closed for invalid numbers.
local function isPositiveFiniteInteger(amount: number): boolean
	if typeof(amount) ~= "number" then
		return false
	end

	if amount ~= amount or amount == math.huge or amount == -math.huge then
		return false
	end

	return amount > 0 and amount <= MAX_SAFE_INTEGER and math.floor(amount) == amount
end

-- Loaded balances and ownership counts may legitimately be zero, but must
-- still be finite whole numbers before becoming authoritative session state.
local function isNonNegativeFiniteInteger(value: number): boolean
	if typeof(value) ~= "number" then
		return false
	end

	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end

	return value >= 0 and value <= MAX_SAFE_INTEGER and math.floor(value) == value
end

-- Checks the result before addition so valid operands cannot cross Luau's exact
-- integer range and silently lose economy precision.
local function canAddWithoutOverflow(currentValue: number, amount: number): boolean
	return currentValue <= MAX_SAFE_INTEGER - amount
end

-- Validates species/recipe-style IDs that are used as dictionary keys.
-- Bounds avoid accepting giant strings into server-owned state by accident.
local function isBoundedIdentifier(id: string, maxLength: number): boolean
	return typeof(id) == "string" and #id > 0 and #id <= maxLength
end

-- Builds configured zero-count ownership so new players and loaded players have
-- separate, predictable species maps without sharing the save payload table.
local function createDefaultOddlingCounts(): OddlingCounts
	local counts: OddlingCounts = {}
	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		counts[definition.SpeciesId] = 0
	end
	return counts
end

-- Creates a brand-new state object from validated loaded values. AssignedPlotId
-- and recipe unlocks intentionally begin as session/derived state.
local function createPlayerState(initialState: InitialPlayerState?): PlayerState?
	local ownedOddlings = createDefaultOddlingCounts()
	local scrap = 0
	local hype = 0
	local workshopLevel = 1

	if initialState then
		if not isNonNegativeFiniteInteger(initialState.Scrap)
			or not isNonNegativeFiniteInteger(initialState.Hype)
			or not isPositiveFiniteInteger(initialState.WorkshopLevel)
			or not WorkshopLevels.GetDefinition(initialState.WorkshopLevel)
			or typeof(initialState.OwnedOddlings) ~= "table"
		then
			return nil
		end

		scrap = initialState.Scrap
		hype = initialState.Hype
		workshopLevel = initialState.WorkshopLevel
		for speciesId, count in pairs(initialState.OwnedOddlings) do
			if not Oddlings.GetDefinition(speciesId) or not isNonNegativeFiniteInteger(count) then
				return nil
			end
			ownedOddlings[speciesId] = count
		end
	end

	return {
		Scrap = scrap,
		Hype = hype,
		WorkshopLevel = workshopLevel,
		AssignedPlotId = nil,
		OwnedOddlings = ownedOddlings,
		-- Toastmarshal is server-unlocked from the start for Vertical Slice 0.1.
		UnlockedRecipes = {
			[STARTING_RECIPE_ID] = true,
		},
	}
end

-- Copies an Oddling count map before it leaves the service boundary.
-- Tables are references in Luau, so callers could mutate the original if we returned it directly.
local function copyOddlingCounts(source: OddlingCounts): OddlingCounts
	local copy: OddlingCounts = {}

	for oddlingId, count in pairs(source) do
		copy[oddlingId] = count
	end

	return copy
end

-- Copies the recipe unlock set for the same reason as Oddling counts:
-- public snapshots should be read-only in practice even though Luau tables are mutable.
local function copyRecipeUnlocks(source: RecipeUnlocks): RecipeUnlocks
	local copy: RecipeUnlocks = {}

	for recipeId, isUnlocked in pairs(source) do
		copy[recipeId] = isUnlocked
	end

	return copy
end

-- Starts the state container without creating temporary defaults. PersistenceService
-- is the readiness gate and initializes each player only after a profile session loads.
function PlayerStateService.Start()
	if started then
		return
	end

	started = true
	print("[ODDWORKS][PlayerState] Service started; awaiting persistence initialization.")
end

-- Establishes exactly one authoritative state after persistence has validated
-- and copied its data. A caller cannot retain references to nested state tables.
function PlayerStateService.InitializePlayer(player: Player, initialState: InitialPlayerState?): boolean
	if not started or player.Parent ~= Players or playerStates[player] then
		return false
	end

	local state = createPlayerState(initialState)
	if not state then
		return false
	end

	playerStates[player] = state
	notifyStateChanged(player)
	print(string.format("[ODDWORKS][PlayerState] Initialized authoritative state for %s (%d).", player.Name, player.UserId))
	return true
end

-- Removes only this player's in-memory gameplay state after persistence has
-- synchronized and ended its profile session, or immediately after session loss.
function PlayerStateService.RemovePlayerState(player: Player): boolean
	if not playerStates[player] then
		return false
	end

	playerStates[player] = nil
	print(string.format("[ODDWORKS][PlayerState] Removed session state for %s (%d).", player.Name, player.UserId))
	return true
end

-- Reports whether this server has session state for the given Player without exposing the state itself.
function PlayerStateService.HasState(player: Player): boolean
	return playerStates[player] ~= nil
end

-- Records the plot chosen by WorkshopService without exposing the private PlayerState table.
-- This keeps plot occupancy authority in WorkshopService while PlayerState owns only the AssignedPlotId field.
function PlayerStateService.AssignPlot(player: Player, plotId: string): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if state.AssignedPlotId ~= nil and state.AssignedPlotId ~= plotId then
		return false
	end

	state.AssignedPlotId = plotId
	notifyStateChanged(player)
	return true
end

-- Clears only the AssignedPlotId field during workshop release.
-- The optional expectedPlotId prevents one service cleanup from erasing a newer/different assignment.
function PlayerStateService.ClearAssignedPlot(player: Player, expectedPlotId: string?): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if expectedPlotId ~= nil and state.AssignedPlotId ~= expectedPlotId then
		return false
	end

	state.AssignedPlotId = nil
	notifyStateChanged(player)
	return true
end

-- Adds server-approved Scrap to a player's authoritative session state.
-- The amount is validated here so future economy callers cannot accidentally award invalid values.
function PlayerStateService.AddScrap(player: Player, amount: number): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isPositiveFiniteInteger(amount) or not canAddWithoutOverflow(state.Scrap, amount) then
		return false
	end

	state.Scrap += amount
	notifyStateChanged(player)
	return true
end

-- Adds server-produced Hype to authoritative session state and notifies snapshot listeners.
-- The narrow validated API prevents callers from introducing negative or fractional currency.
function PlayerStateService.AddHype(player: Player, amount: number): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isPositiveFiniteInteger(amount) or not canAddWithoutOverflow(state.Hype, amount) then
		return false
	end

	state.Hype += amount
	notifyStateChanged(player)
	return true
end

-- Checks authoritative Hype affordability without changing the player's balance.
-- Upgrade transactions still revalidate during SpendHype to avoid stale assumptions.
function PlayerStateService.CanAffordHype(player: Player, amount: number): boolean
	local state = playerStates[player]
	if not state or not isPositiveFiniteInteger(amount) then
		return false
	end

	return state.Hype >= amount
end

-- Spends a validated server-approved Hype amount without allowing a negative balance.
-- Clients cannot call this module because it exists only under ServerScriptService.
function PlayerStateService.SpendHype(player: Player, amount: number): boolean
	local state = playerStates[player]
	if not state or not isPositiveFiniteInteger(amount) then
		return false
	end

	if state.Hype < amount then
		return false
	end

	state.Hype -= amount
	notifyStateChanged(player)
	return true
end

-- Advances only a configured transition from the expected current level.
-- Consulting server configuration rejects stale requests, downgrades, skipped, and unsupported levels.
function PlayerStateService.AdvanceWorkshopLevel(
	player: Player,
	expectedCurrentLevel: number,
	newLevel: number
): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isPositiveFiniteInteger(expectedCurrentLevel) or not isPositiveFiniteInteger(newLevel) then
		return false
	end

	if state.WorkshopLevel ~= expectedCurrentLevel then
		return false
	end

	if newLevel ~= expectedCurrentLevel + 1 then
		return false
	end

	local currentDefinition = WorkshopLevels.GetDefinition(expectedCurrentLevel)
	local nextDefinition = WorkshopLevels.GetDefinition(newLevel)
	if not currentDefinition or currentDefinition.NextLevel ~= newLevel or not nextDefinition then
		return false
	end

	state.WorkshopLevel = newLevel
	notifyStateChanged(player)
	return true
end

-- Checks affordability without changing state.
-- Crafting uses this before attempting a transaction, but SpendScrap still validates again.
function PlayerStateService.CanAffordScrap(player: Player, amount: number): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isPositiveFiniteInteger(amount) then
		return false
	end

	return state.Scrap >= amount
end

-- Spends server-approved Scrap while guaranteeing the balance never goes below zero.
-- Clients cannot call this directly; crafting uses it after validating recipe cost and unlocks.
function PlayerStateService.SpendScrap(player: Player, amount: number): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isPositiveFiniteInteger(amount) then
		return false
	end

	if state.Scrap < amount then
		return false
	end

	state.Scrap -= amount
	notifyStateChanged(player)
	return true
end

-- Reports whether the server has unlocked a recipe for this player.
-- The client may request a recipe, but the server-owned unlock set decides eligibility.
function PlayerStateService.IsRecipeUnlocked(player: Player, recipeId: string): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isBoundedIdentifier(recipeId, MAX_RECIPE_ID_LENGTH) then
		return false
	end

	return state.UnlockedRecipes[recipeId] == true
end

-- Unlocks only a recipe that exists in authoritative server configuration.
-- The operation is idempotent so reconciliation can run repeatedly without duplicate changes or notifications.
function PlayerStateService.UnlockRecipe(player: Player, recipeId: string): boolean
	local state = playerStates[player]
	if not state or not isBoundedIdentifier(recipeId, MAX_RECIPE_ID_LENGTH) then
		return false
	end

	if not Recipes.GetRecipe(recipeId) then
		return false
	end

	if state.UnlockedRecipes[recipeId] == true then
		return true
	end

	state.UnlockedRecipes[recipeId] = true
	notifyStateChanged(player)
	return true
end

-- Records owned Oddlings as species counters for the current simple MVP shape.
-- Duplicates are intentional: each successful Toastmarshal craft increments the same counter.
function PlayerStateService.AddOwnedOddling(player: Player, speciesId: string, amount: number): boolean
	local state = playerStates[player]
	if not state then
		return false
	end

	if not isBoundedIdentifier(speciesId, MAX_OWNED_ODDLING_ID_LENGTH) or not Oddlings.GetDefinition(speciesId) then
		return false
	end

	if not isPositiveFiniteInteger(amount) then
		return false
	end

	local currentCount = state.OwnedOddlings[speciesId] or 0
	if not canAddWithoutOverflow(currentCount, amount) then
		return false
	end

	state.OwnedOddlings[speciesId] = currentCount + amount
	notifyStateChanged(player)
	return true
end

-- Lets server services observe authoritative state changes without receiving
-- direct access to the private playerStates table or the event's Fire method.
function PlayerStateService.ObserveStateChanged(callback: (Player) -> ()): RBXScriptConnection
	return stateChangedEvent.Event:Connect(callback)
end

-- Returns a defensive copy of the player's current session state.
-- Future server systems can read this safely without mutating authoritative tables by accident.
function PlayerStateService.GetSnapshot(player: Player): PlayerState?
	local state = playerStates[player]
	if not state then
		return nil
	end

	return {
		Scrap = state.Scrap,
		Hype = state.Hype,
		WorkshopLevel = state.WorkshopLevel,
		AssignedPlotId = state.AssignedPlotId,
		OwnedOddlings = copyOddlingCounts(state.OwnedOddlings),
		UnlockedRecipes = copyRecipeUnlocks(state.UnlockedRecipes),
	}
end

return PlayerStateService
