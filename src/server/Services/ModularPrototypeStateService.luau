--!strict

local Players = game:GetService("Players")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][ModularState] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local Components = require(Config:WaitForChild("Components"))

export type RarityCounts = { [string]: number }
export type ComponentCounts = { [string]: RarityCounts }
export type ComponentSelection = {
	ComponentId: string,
	Rarity: string,
}
export type PrototypeConstruct = {
	FrameId: string,
	Head: ComponentSelection,
	Arm: ComponentSelection,
	Legs: ComponentSelection,
}
export type ModularPrototypeState = {
	UnbankedComponents: ComponentCounts,
	BankedComponents: ComponentCounts,
	PrototypeConstruct: PrototypeConstruct?,
}
export type BankResultCode = "BANK_SUCCESS" | "NOTHING_TO_BANK" | "BANK_OVERFLOW" | "INVALID_STATE"
export type AssemblyResultCode =
	"ASSEMBLY_SUCCESS"
	| "INVALID_STATE"
	| "INVALID_REQUEST"
	| "INVALID_FRAME"
	| "INVALID_COMPONENT"
	| "INCOMPATIBLE_COMPONENT"
	| "INSUFFICIENT_COMPONENTS"
	| "BANK_OVERFLOW"

local ModularPrototypeStateService = {}

local MAX_COMPONENTS_PER_BUCKET = 999
local MAX_COMPONENT_ID_LENGTH = 48
local MAX_RARITY_LENGTH = 16
local MAX_ASSEMBLY_ID_LENGTH = 32
local PROTOTYPE_FRAME_ID = "SmallBiped_v1"

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

local function isNonNegativeInteger(value: number): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
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
		Head = table.clone(source.Head),
		Arm = table.clone(source.Arm),
		Legs = table.clone(source.Legs),
	}
end

local function hasExactKeys(value: any, expectedKeys: { [string]: boolean }): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local seenCount = 0
	for key in pairs(value) do
		if typeof(key) ~= "string" or not expectedKeys[key] then
			return false
		end
		seenCount += 1
	end

	local expectedCount = 0
	for _ in pairs(expectedKeys) do
		expectedCount += 1
	end
	return seenCount == expectedCount
end

local function validateSelection(value: any, expectedSlot: string, frameId: string): AssemblyResultCode?
	if not hasExactKeys(value, { ComponentId = true, Rarity = true })
		or not isBoundedString(value.ComponentId, MAX_ASSEMBLY_ID_LENGTH)
		or not isBoundedString(value.Rarity, MAX_RARITY_LENGTH)
	then
		return "INVALID_REQUEST"
	end

	local definition = Components.GetDefinition(value.ComponentId)
	if not definition or not Components.IsValidRarity(value.Rarity) then
		return "INVALID_COMPONENT"
	end
	if definition.Slot ~= expectedSlot or not Components.IsCompatibleWithFrame(value.ComponentId, frameId) then
		return "INCOMPATIBLE_COMPONENT"
	end
	return nil
end

local function validateAssemblyRequest(request: any): AssemblyResultCode?
	if not hasExactKeys(request, { FrameId = true, Head = true, Arm = true, Legs = true })
		or not isBoundedString(request.FrameId, MAX_ASSEMBLY_ID_LENGTH)
	then
		return "INVALID_REQUEST"
	end
	if request.FrameId ~= PROTOTYPE_FRAME_ID then
		return "INVALID_FRAME"
	end

	return validateSelection(request.Head, "Head", request.FrameId)
		or validateSelection(request.Arm, "Arm", request.FrameId)
		or validateSelection(request.Legs, "Legs", request.FrameId)
end

local function copyValidatedComponentCounts(source: ComponentCounts): ComponentCounts?
	local result: ComponentCounts = {}
	for componentId, rarityCounts in pairs(source) do
		if not isBoundedString(componentId, MAX_COMPONENT_ID_LENGTH)
			or not Components.GetDefinition(componentId)
			or typeof(rarityCounts) ~= "table"
		then
			return nil
		end

		local rarityCopy: RarityCounts = {}
		for rarity, count in pairs(rarityCounts) do
			if not isBoundedString(rarity, MAX_RARITY_LENGTH)
				or not Components.IsValidRarity(rarity)
				or not isNonNegativeInteger(count)
				or count > MAX_COMPONENTS_PER_BUCKET
			then
				return nil
			end
			if count > 0 then
				rarityCopy[rarity] = count
			end
		end
		if next(rarityCopy) ~= nil then
			result[componentId] = rarityCopy
		end
	end
	return result
end

local function addSelection(counts: ComponentCounts, selection: ComponentSelection)
	local rarityCounts = counts[selection.ComponentId]
	if not rarityCounts then
		rarityCounts = {}
		counts[selection.ComponentId] = rarityCounts
	end
	rarityCounts[selection.Rarity] = (rarityCounts[selection.Rarity] or 0) + 1
end

local function reserveSelection(counts: ComponentCounts, selection: ComponentSelection): boolean
	local rarityCounts = counts[selection.ComponentId]
	local currentCount = if rarityCounts then rarityCounts[selection.Rarity] or 0 else 0
	if currentCount < 1 or not rarityCounts then
		return false
	end

	if currentCount == 1 then
		rarityCounts[selection.Rarity] = nil
		if next(rarityCounts) == nil then
			counts[selection.ComponentId] = nil
		end
	else
		rarityCounts[selection.Rarity] = currentCount - 1
	end
	return true
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

-- Banking builds and validates a complete destination copy before committing
-- either map. With no yields in this function, a repeated prompt cannot observe
-- the same unbanked units midway through the transaction.
function ModularPrototypeStateService.BankAllUnbanked(player: Player): (BankResultCode, number)
	local state = states[player]
	if not state then
		return "INVALID_STATE", 0
	end

	local updatedBanked: ComponentCounts = {}
	for componentId, rarityCounts in pairs(state.BankedComponents) do
		if not isBoundedString(componentId, MAX_COMPONENT_ID_LENGTH)
			or not Components.GetDefinition(componentId)
			or typeof(rarityCounts) ~= "table"
		then
			return "INVALID_STATE", 0
		end

		local copiedRarities: RarityCounts = {}
		for rarity, count in pairs(rarityCounts) do
			if not isBoundedString(rarity, MAX_RARITY_LENGTH)
				or not Components.IsValidRarity(rarity)
				or not isNonNegativeInteger(count)
				or count > MAX_COMPONENTS_PER_BUCKET
			then
				return "INVALID_STATE", 0
			end
			if count > 0 then
				copiedRarities[rarity] = count
			end
		end
		if next(copiedRarities) ~= nil then
			updatedBanked[componentId] = copiedRarities
		end
	end

	local transferredCount = 0
	for componentId, rarityCounts in pairs(state.UnbankedComponents) do
		if not isBoundedString(componentId, MAX_COMPONENT_ID_LENGTH)
			or not Components.GetDefinition(componentId)
			or typeof(rarityCounts) ~= "table"
		then
			return "INVALID_STATE", 0
		end

		for rarity, count in pairs(rarityCounts) do
			if not isBoundedString(rarity, MAX_RARITY_LENGTH)
				or not Components.IsValidRarity(rarity)
				or not isNonNegativeInteger(count)
				or count > MAX_COMPONENTS_PER_BUCKET
			then
				return "INVALID_STATE", 0
			end

			if count > 0 then
				local destinationRarities = updatedBanked[componentId]
				if not destinationRarities then
					destinationRarities = {}
					updatedBanked[componentId] = destinationRarities
				end
				local currentCount = destinationRarities[rarity] or 0
				if count > MAX_COMPONENTS_PER_BUCKET - currentCount then
					return "BANK_OVERFLOW", 0
				end
				destinationRarities[rarity] = currentCount + count
				transferredCount += count
			end
		end
	end

	if transferredCount == 0 then
		return "NOTHING_TO_BANK", 0
	end

	state.BankedComponents = updatedBanked
	state.UnbankedComponents = {}
	stateChangedEvent:Fire(player)
	return "BANK_SUCCESS", transferredCount
end

-- Assembly and rebuild use a virtual inventory pool. Existing modules are
-- returned only inside that copy, requested modules are reserved from it, and
-- the live bank plus complete Construct change together after every check passes.
function ModularPrototypeStateService.AssemblePrototypeConstruct(player: Player, request: any): (AssemblyResultCode, boolean)
	local state = states[player]
	if not state then
		return "INVALID_STATE", false
	end

	local requestFailure = validateAssemblyRequest(request)
	if requestFailure then
		return requestFailure, false
	end

	local candidateBank = copyValidatedComponentCounts(state.BankedComponents)
	if not candidateBank then
		return "INVALID_STATE", false
	end

	local wasRebuild = state.PrototypeConstruct ~= nil
	if state.PrototypeConstruct then
		if validateAssemblyRequest(state.PrototypeConstruct) then
			return "INVALID_STATE", false
		end
		addSelection(candidateBank, state.PrototypeConstruct.Head)
		addSelection(candidateBank, state.PrototypeConstruct.Arm)
		addSelection(candidateBank, state.PrototypeConstruct.Legs)
	end

	local requestedHead: ComponentSelection = table.clone(request.Head)
	local requestedArm: ComponentSelection = table.clone(request.Arm)
	local requestedLegs: ComponentSelection = table.clone(request.Legs)
	if not reserveSelection(candidateBank, requestedHead)
		or not reserveSelection(candidateBank, requestedArm)
		or not reserveSelection(candidateBank, requestedLegs)
	then
		return "INSUFFICIENT_COMPONENTS", false
	end

	-- A virtually returned installed unit may temporarily take a bucket to 1000.
	-- Only the final bank is bounded, which allows selecting that same unit again.
	local finalBank = copyValidatedComponentCounts(candidateBank)
	if not finalBank then
		return "BANK_OVERFLOW", false
	end

	local candidateConstruct: PrototypeConstruct = {
		FrameId = PROTOTYPE_FRAME_ID,
		Head = requestedHead,
		Arm = requestedArm,
		Legs = requestedLegs,
	}

	state.BankedComponents = finalBank
	state.PrototypeConstruct = candidateConstruct
	stateChangedEvent:Fire(player)
	return "ASSEMBLY_SUCCESS", wasRebuild
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
