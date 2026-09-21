--!strict

local Players = game:GetService("Players")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][ModularState] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local Components = require(Config:WaitForChild("Components"))

export type RarityCounts = { [string]: number }
export type ComponentCounts = { [string]: RarityCounts }
export type PrototypeConstruct = {
	FrameId: string,
	HeadComponentId: string,
	HeadRarity: string,
	ArmComponentId: string,
	ArmRarity: string,
	LegsComponentId: string,
	LegsRarity: string,
}
export type ModularPrototypeState = {
	UnbankedComponents: ComponentCounts,
	BankedComponents: ComponentCounts,
	PrototypeConstruct: PrototypeConstruct?,
}

local ModularPrototypeStateService = {}

local MAX_COMPONENTS_PER_BUCKET = 999
local MAX_COMPONENT_ID_LENGTH = 48
local MAX_RARITY_LENGTH = 16

-- This state is deliberately separate from PlayerState and ProfileStore schema
-- v1. If the experiment fails its fun gate, it can disappear without migration.
local states: { [Player]: ModularPrototypeState } = {}
local stateChangedEvent = Instance.new("BindableEvent")
local stateRemovedEvent = Instance.new("BindableEvent")
local started = false

local function isPositiveInteger(value: number): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
		and math.floor(value) == value
end

local function isBoundedString(value: string, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

local function copyComponentCounts(source: ComponentCounts): ComponentCounts
	local copy: ComponentCounts = {}
	for componentId, rarityCounts in pairs(source) do
		local rarityCopy: RarityCounts = {}
		for rarity, count in pairs(rarityCounts) do
			rarityCopy[rarity] = count
		end
		copy[componentId] = rarityCopy
	end
	return copy
end

local function copyPrototypeConstruct(source: PrototypeConstruct?): PrototypeConstruct?
	if not source then
		return nil
	end

	return {
		FrameId = source.FrameId,
		HeadComponentId = source.HeadComponentId,
		HeadRarity = source.HeadRarity,
		ArmComponentId = source.ArmComponentId,
		ArmRarity = source.ArmRarity,
		LegsComponentId = source.LegsComponentId,
		LegsRarity = source.LegsRarity,
	}
end

-- Creates state only after PersistenceService has established production
-- PlayerState. This prevents temporary prototype data from becoming a readiness bypass.
local function initializePlayer(player: Player)
	if states[player] or player.Parent ~= Players or not PlayerStateService.HasState(player) then
		return
	end

	states[player] = {
		UnbankedComponents = {},
		BankedComponents = {},
		PrototypeConstruct = nil,
	}
	stateChangedEvent:Fire(player)
	print(string.format("[ODDWORKS][ModularState] Initialized session-only state for %s (%d).", player.Name, player.UserId))
end

-- Removal is idempotent because both profile loss and PlayerRemoving can occur
-- during the same disconnect path.
local function removePlayer(player: Player)
	if not states[player] then
		return
	end

	states[player] = nil
	stateRemovedEvent:Fire(player)
	print(string.format("[ODDWORKS][ModularState] Removed session-only state for %s (%d).", player.Name, player.UserId))
end

function ModularPrototypeStateService.Start()
	if started then
		return
	end
	started = true

	PlayerStateService.ObserveStateChanged(initializePlayer)
	PlayerStateService.ObserveStateRemoved(removePlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end

	print("[ODDWORKS][ModularState] Service started; state is session-only and excluded from schema v1.")
end

function ModularPrototypeStateService.HasState(player: Player): boolean
	return states[player] ~= nil
end

-- Adds one server-determined reward while enforcing configured identity and the
-- prototype's per-component/rarity bucket cap.
function ModularPrototypeStateService.AddUnbankedComponent(
	player: Player,
	componentId: string,
	rarity: string,
	count: number
): boolean
	local state = states[player]
	if not state then
		return false
	end

	if not isBoundedString(componentId, MAX_COMPONENT_ID_LENGTH)
		or not Components.GetDefinition(componentId)
		or not isBoundedString(rarity, MAX_RARITY_LENGTH)
		or not Components.IsValidRarity(rarity)
		or not isPositiveInteger(count)
	then
		return false
	end

	local rarityCounts = state.UnbankedComponents[componentId]
	local currentCount = if rarityCounts then rarityCounts[rarity] or 0 else 0
	if count > MAX_COMPONENTS_PER_BUCKET - currentCount then
		return false
	end

	if not rarityCounts then
		rarityCounts = {}
		state.UnbankedComponents[componentId] = rarityCounts
	end
	rarityCounts[rarity] = currentCount + count
	stateChangedEvent:Fire(player)
	return true
end

-- Every table crossing the service boundary is copied, including nested rarity
-- buckets, so callers cannot mutate session authority by retaining a reference.
function ModularPrototypeStateService.GetSnapshot(player: Player): ModularPrototypeState?
	local state = states[player]
	if not state then
		return nil
	end

	return {
		UnbankedComponents = copyComponentCounts(state.UnbankedComponents),
		BankedComponents = copyComponentCounts(state.BankedComponents),
		PrototypeConstruct = copyPrototypeConstruct(state.PrototypeConstruct),
	}
end

function ModularPrototypeStateService.ObserveStateChanged(callback: (Player) -> ()): RBXScriptConnection
	return stateChangedEvent.Event:Connect(callback)
end

function ModularPrototypeStateService.ObserveStateRemoved(callback: (Player) -> ()): RBXScriptConnection
	return stateRemovedEvent.Event:Connect(callback)
end

return ModularPrototypeStateService
