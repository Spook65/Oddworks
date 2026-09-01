--!strict

local Players = game:GetService("Players")

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

local PlayerStateService = {}

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

-- Creates a brand-new state object so each player gets separate nested tables.
-- Reusing table references here would let one player's Oddlings/unlocks leak into another player's state.
local function createInitialPlayerState(): PlayerState
	return {
		Scrap = 0,
		Hype = 0,
		WorkshopLevel = 1,
		AssignedPlotId = nil,
		OwnedOddlings = {},
		UnlockedRecipes = {},
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

-- PlayerAdded can fire before or after services start depending on Studio/server timing,
-- so initialization is idempotent and refuses to create duplicate state for one Player.
local function initializePlayer(player: Player)
	if playerStates[player] then
		warn(string.format("[ODDWORKS][PlayerState] State already exists for %s (%d).", player.Name, player.UserId))
		return
	end

	playerStates[player] = createInitialPlayerState()
	notifyStateChanged(player)
	print(string.format("[ODDWORKS][PlayerState] Created session state for %s (%d).", player.Name, player.UserId))
end

-- PlayerRemoving cleanup prevents stale server-memory state from surviving after a player leaves.
-- This pass is session-only, so there is intentionally no DataStore save here.
local function removePlayer(player: Player)
	if not playerStates[player] then
		return
	end

	playerStates[player] = nil
	print(string.format("[ODDWORKS][PlayerState] Cleaned up session state for %s (%d).", player.Name, player.UserId))
end

-- Starts the server-owned player lifecycle once and initializes any players already present.
-- The server, not the client, is responsible for creating authoritative gameplay state.
function PlayerStateService.Start()
	if started then
		return
	end

	started = true

	Players.PlayerAdded:Connect(initializePlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end

	print("[ODDWORKS][PlayerState] Service started.")
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

	if typeof(amount) ~= "number" then
		return false
	end

	if amount ~= amount or amount == math.huge or amount == -math.huge then
		return false
	end

	if amount <= 0 or math.floor(amount) ~= amount then
		return false
	end

	state.Scrap += amount
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
