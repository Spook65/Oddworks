--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][OddlingCollection] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local Oddlings = require(Config:WaitForChild("Oddlings"))
local WorkshopLevels = require(Config:WaitForChild("WorkshopLevels"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))

export type DisplayLoadout = { [number]: string }

local OddlingCollectionService = {}

local COLLECTION_REQUEST_NAME = "OddlingCollectionRequest"
local COLLECTION_SNAPSHOT_NAME = "OddlingCollectionSnapshot"
local DISPLAY_EDIT_REQUEST_NAME = "OddlingDisplayEditRequest"
local COLLECTION_FEEDBACK_NAME = "OddlingCollectionFeedback"
local REQUEST_INTERVAL_SECONDS = 0.25
local EDIT_INTERVAL_SECONDS = 0.35
local MAX_SPECIES_ID_LENGTH = 64

local loadouts: { [Player]: DisplayLoadout } = {}
local previousOwnedCounts: { [Player]: { [string]: number } } = {}
local previousWorkshopLevels: { [Player]: number } = {}
local lastRequestTimes: { [Player]: number } = {}
local lastEditTimes: { [Player]: number } = {}
local loadoutChangedEvent = Instance.new("BindableEvent")
local snapshotRemote: RemoteEvent? = nil
local feedbackRemote: RemoteEvent? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][OddlingCollection] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][OddlingCollection] %s.%s must be a %s, but found %s.",
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

local function copyCounts(source: { [string]: number }): { [string]: number }
	local copy: { [string]: number } = {}
	for speciesId, count in pairs(source) do
		copy[speciesId] = count
	end
	return copy
end

local function copyLoadout(source: DisplayLoadout): DisplayLoadout
	local copy: DisplayLoadout = {}
	for slotIndex, speciesId in pairs(source) do
		copy[slotIndex] = speciesId
	end
	return copy
end

local function getCapacity(workshopLevel: number): number?
	local definition = WorkshopLevels.GetDefinition(workshopLevel)
	if not definition
		or typeof(definition.DisplayCapacity) ~= "number"
		or definition.DisplayCapacity < 0
		or definition.DisplayCapacity % 1 ~= 0
	then
		return nil
	end
	return definition.DisplayCapacity
end

local function countLoadoutSpecies(loadout: DisplayLoadout, capacity: number): { [string]: number }
	local counts: { [string]: number } = {}
	for slotIndex = 1, capacity do
		local speciesId = loadout[slotIndex]
		if speciesId then
			counts[speciesId] = (counts[speciesId] or 0) + 1
		end
	end
	return counts
end

local function isCandidateValid(
	candidate: DisplayLoadout,
	ownedCounts: { [string]: number },
	capacity: number
): boolean
	local displayedCounts: { [string]: number } = {}
	for slotIndex, speciesId in pairs(candidate) do
		if typeof(slotIndex) ~= "number"
			or slotIndex % 1 ~= 0
			or slotIndex < 1
			or slotIndex > capacity
			or typeof(speciesId) ~= "string"
			or #speciesId == 0
			or #speciesId > MAX_SPECIES_ID_LENGTH
			or not Oddlings.GetDefinition(speciesId)
		then
			return false
		end
		displayedCounts[speciesId] = (displayedCounts[speciesId] or 0) + 1
	end
	for speciesId, displayedCount in pairs(displayedCounts) do
		if displayedCount > (ownedCounts[speciesId] or 0) then
			return false
		end
	end
	return true
end

local function buildDefaultLoadout(ownedCounts: { [string]: number }, capacity: number): DisplayLoadout
	local loadout: DisplayLoadout = {}
	local remaining = copyCounts(ownedCounts)
	local nextSlot = 1
	local definitions = Oddlings.GetAllDefinitions()

	-- Pass one favors collection variety, not production value.
	for _, definition in ipairs(definitions) do
		if nextSlot > capacity then
			break
		end
		local count = remaining[definition.SpeciesId] or 0
		if count > 0 then
			loadout[nextSlot] = definition.SpeciesId
			remaining[definition.SpeciesId] = count - 1
			nextSlot += 1
		end
	end

	-- Pass two fills remaining slots with duplicates in the same stable order.
	while nextSlot <= capacity do
		local filledThisPass = false
		for _, definition in ipairs(definitions) do
			if nextSlot > capacity then
				break
			end
			local count = remaining[definition.SpeciesId] or 0
			if count > 0 then
				loadout[nextSlot] = definition.SpeciesId
				remaining[definition.SpeciesId] = count - 1
				nextSlot += 1
				filledThisPass = true
			end
		end
		if not filledThisPass then
			break
		end
	end
	return loadout
end

local function normalizeLoadout(
	loadout: DisplayLoadout,
	ownedCounts: { [string]: number },
	capacity: number
): boolean
	local changed = false
	local displayedCounts: { [string]: number } = {}
	for slotIndex = 1, WorkshopLevels.GetMaxDisplayCapacity() do
		local speciesId = loadout[slotIndex]
		if speciesId then
			local nextCount = (displayedCounts[speciesId] or 0) + 1
			if slotIndex > capacity or not Oddlings.GetDefinition(speciesId) or nextCount > (ownedCounts[speciesId] or 0) then
				loadout[slotIndex] = nil
				changed = true
			else
				displayedCounts[speciesId] = nextCount
			end
		end
	end
	return changed
end

local function fireFeedback(player: Player, payload: { [string]: any })
	local remote = feedbackRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function buildClientSnapshot(player: Player): { [string]: any }?
	local playerState = PlayerStateService.GetSnapshot(player)
	local loadout = loadouts[player]
	if not playerState or not loadout then
		return nil
	end
	local capacity = getCapacity(playerState.WorkshopLevel)
	if not capacity then
		return nil
	end
	local maxCapacity = WorkshopLevels.GetMaxDisplayCapacity()
	local displayedCounts = countLoadoutSpecies(loadout, capacity)
	local species = {}
	local totalOwned = 0
	local totalDisplayed = 0
	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		local ownedCount = playerState.OwnedOddlings[definition.SpeciesId] or 0
		if ownedCount > 0 then
			local displayedCount = displayedCounts[definition.SpeciesId] or 0
			totalOwned += ownedCount
			totalDisplayed += displayedCount
			table.insert(species, {
				SpeciesId = definition.SpeciesId,
				OwnedCount = ownedCount,
				DisplayedCount = displayedCount,
				CollectionCount = ownedCount - displayedCount,
				HypePerInterval = definition.HypePerInterval,
				HypeIntervalSeconds = definition.HypeIntervalSeconds,
			})
		end
	end
	local slots = {}
	for slotIndex = 1, maxCapacity do
		table.insert(slots, {
			SlotIndex = slotIndex,
			SpeciesId = loadout[slotIndex],
			Unlocked = slotIndex <= capacity,
		})
	end
	return {
		WorkshopLevel = playerState.WorkshopLevel,
		Capacity = capacity,
		UsedSlots = totalDisplayed,
		CollectionOnlyCount = totalOwned - totalDisplayed,
		Species = species,
		Slots = slots,
	}
end

local function sendSnapshot(player: Player)
	local remote = snapshotRemote
	local snapshot = buildClientSnapshot(player)
	if remote and snapshot and player.Parent == Players then
		remote:FireClient(player, snapshot)
	end
end

local function commitLoadout(player: Player, candidate: DisplayLoadout)
	loadouts[player] = candidate
	loadoutChangedEvent:Fire(player)
	sendSnapshot(player)
end

local function autoFillNewOwnership(
	loadout: DisplayLoadout,
	speciesId: string,
	addedCount: number,
	ownedCounts: { [string]: number },
	capacity: number
): (number, number?)
	local displayedCounts = countLoadoutSpecies(loadout, capacity)
	local availableOwned = math.max(0, (ownedCounts[speciesId] or 0) - (displayedCounts[speciesId] or 0))
	local toPlace = math.min(addedCount, availableOwned)
	local placedCount = 0
	local firstSlot: number? = nil
	for slotIndex = 1, capacity do
		if placedCount >= toPlace then
			break
		end
		if loadout[slotIndex] == nil then
			loadout[slotIndex] = speciesId
			placedCount += 1
			firstSlot = firstSlot or slotIndex
		end
	end
	return placedCount, firstSlot
end

local function handlePlayerStateChanged(player: Player)
	local playerState = PlayerStateService.GetSnapshot(player)
	if not playerState then
		return
	end
	local capacity = getCapacity(playerState.WorkshopLevel)
	if not capacity then
		return
	end

	local previousOwned = previousOwnedCounts[player]
	local previousLevel = previousWorkshopLevels[player]
	local loadout = loadouts[player]
	if not previousOwned or not previousLevel or not loadout then
		local initialLoadout = buildDefaultLoadout(playerState.OwnedOddlings, capacity)
		loadouts[player] = initialLoadout
		previousOwnedCounts[player] = copyCounts(playerState.OwnedOddlings)
		previousWorkshopLevels[player] = playerState.WorkshopLevel
		loadoutChangedEvent:Fire(player)
		sendSnapshot(player)
		return
	end

	local ownershipChanged = false
	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		if (previousOwned[definition.SpeciesId] or 0) ~= (playerState.OwnedOddlings[definition.SpeciesId] or 0) then
			ownershipChanged = true
			break
		end
	end
	local levelChanged = previousLevel ~= playerState.WorkshopLevel
	if not ownershipChanged and not levelChanged then
		return
	end

	local candidate = copyLoadout(loadout)
	local loadoutChanged = normalizeLoadout(candidate, playerState.OwnedOddlings, capacity)
	if levelChanged and playerState.WorkshopLevel > previousLevel then
		local oldCapacity = getCapacity(previousLevel) or 0
		fireFeedback(player, {
			Kind = "WORKSHOP_EXPANDED",
			AddedSlots = math.max(0, capacity - oldCapacity),
		})
	end

	if ownershipChanged then
		for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
			local speciesId = definition.SpeciesId
			local addedCount = (playerState.OwnedOddlings[speciesId] or 0) - (previousOwned[speciesId] or 0)
			if addedCount > 0 then
				local autoDisplayedCount, firstSlot = autoFillNewOwnership(
					candidate,
					speciesId,
					addedCount,
					playerState.OwnedOddlings,
					capacity
				)
				if autoDisplayedCount > 0 then
					loadoutChanged = true
				end
				fireFeedback(player, {
					Kind = "ODDLING_ADDED",
					SpeciesId = speciesId,
					AddedCount = addedCount,
					AutoDisplayedCount = autoDisplayedCount,
					FirstSlotIndex = firstSlot,
					DisplayFull = autoDisplayedCount < addedCount,
				})
			end
		end
	end

	previousOwnedCounts[player] = copyCounts(playerState.OwnedOddlings)
	previousWorkshopLevels[player] = playerState.WorkshopLevel
	if loadoutChanged then
		commitLoadout(player, candidate)
	else
		-- Ownership and capacity still affect collection counts and pedestal state
		-- even when the player's explicit slot assignments remain unchanged.
		loadoutChangedEvent:Fire(player)
		sendSnapshot(player)
	end
end

local function passesThrottle(times: { [Player]: number }, player: Player, interval: number): boolean
	local now = os.clock()
	local previous = times[player]
	if previous and now - previous < interval then
		return false
	end
	times[player] = now
	return true
end

local function handleSnapshotRequest(player: Player, ...: any)
	if select("#", ...) ~= 0
		or player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not passesThrottle(lastRequestTimes, player, REQUEST_INTERVAL_SECONDS)
	then
		return
	end
	if not loadouts[player] then
		handlePlayerStateChanged(player)
	else
		sendSnapshot(player)
	end
end

local function handleEditRequest(player: Player, action: any, slotIndex: any, speciesId: any, ...: any)
	if select("#", ...) ~= 0
		or player.Parent ~= Players
		or typeof(action) ~= "string"
		or (action ~= "ASSIGN" and action ~= "CLEAR")
		or typeof(slotIndex) ~= "number"
		or slotIndex % 1 ~= 0
		or not PlayerStateService.HasState(player)
		or not passesThrottle(lastEditTimes, player, EDIT_INTERVAL_SECONDS)
	then
		return
	end
	local playerState = PlayerStateService.GetSnapshot(player)
	local loadout = loadouts[player]
	local capacity = if playerState then getCapacity(playerState.WorkshopLevel) else nil
	if not playerState or not loadout or not capacity or slotIndex < 1 or slotIndex > capacity then
		return
	end

	local candidate = copyLoadout(loadout)
	if action == "ASSIGN" then
		if typeof(speciesId) ~= "string"
			or #speciesId == 0
			or #speciesId > MAX_SPECIES_ID_LENGTH
			or not Oddlings.GetDefinition(speciesId)
		then
			return
		end
		candidate[slotIndex] = speciesId
		if not isCandidateValid(candidate, playerState.OwnedOddlings, capacity) then
			return
		end
		commitLoadout(player, candidate)
		fireFeedback(player, {
			Kind = "DISPLAY_ASSIGNED",
			SpeciesId = speciesId,
			SlotIndex = slotIndex,
		})
	elseif action == "CLEAR" then
		if speciesId ~= nil or candidate[slotIndex] == nil then
			return
		end
		local removedSpeciesId = candidate[slotIndex]
		candidate[slotIndex] = nil
		if not isCandidateValid(candidate, playerState.OwnedOddlings, capacity) then
			return
		end
		commitLoadout(player, candidate)
		fireFeedback(player, {
			Kind = "DISPLAY_CLEARED",
			SpeciesId = removedSpeciesId,
			SlotIndex = slotIndex,
		})
	end
end

local function cleanupPlayer(player: Player)
	loadouts[player] = nil
	previousOwnedCounts[player] = nil
	previousWorkshopLevels[player] = nil
	lastRequestTimes[player] = nil
	lastEditTimes[player] = nil
end

function OddlingCollectionService.GetDisplayLoadout(player: Player): DisplayLoadout?
	local loadout = loadouts[player]
	return if loadout then copyLoadout(loadout) else nil
end

function OddlingCollectionService.GetDisplayedCounts(player: Player): { [string]: number }
	local playerState = PlayerStateService.GetSnapshot(player)
	local loadout = loadouts[player]
	local capacity = if playerState then getCapacity(playerState.WorkshopLevel) else nil
	if not loadout or not capacity then
		return {}
	end
	return countLoadoutSpecies(loadout, capacity)
end

function OddlingCollectionService.GetCollectionSnapshot(player: Player): { [string]: any }?
	return buildClientSnapshot(player)
end

function OddlingCollectionService.ObserveLoadoutChanged(callback: (Player) -> ()): RBXScriptConnection
	return loadoutChangedEvent.Event:Connect(callback)
end

function OddlingCollectionService.Start()
	if started then
		return
	end
	started = true
	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local requestRemote = requireChildOfClass(network, COLLECTION_REQUEST_NAME, "RemoteEvent") :: RemoteEvent
	snapshotRemote = requireChildOfClass(network, COLLECTION_SNAPSHOT_NAME, "RemoteEvent") :: RemoteEvent
	local editRemote = requireChildOfClass(network, DISPLAY_EDIT_REQUEST_NAME, "RemoteEvent") :: RemoteEvent
	feedbackRemote = requireChildOfClass(network, COLLECTION_FEEDBACK_NAME, "RemoteEvent") :: RemoteEvent

	requestRemote.OnServerEvent:Connect(handleSnapshotRequest)
	editRemote.OnServerEvent:Connect(handleEditRequest)
	PlayerStateService.ObserveStateChanged(handlePlayerStateChanged)
	PlayerStateService.ObserveStateRemoved(cleanupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		handlePlayerStateChanged(player)
	end
	print("[ODDWORKS][OddlingCollection] Session display loadouts and collection snapshots started.")
end

return OddlingCollectionService
