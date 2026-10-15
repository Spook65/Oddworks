--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][ModularReplication] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local Components = require(Config:WaitForChild("Components"))

type ClientComponentEntry = {
	ComponentId: string,
	DisplayName: string,
	Rarity: string,
	Slot: string,
	Count: number,
}

type ClientSelection = {
	ComponentId: string,
	DisplayName: string,
	Rarity: string,
}

type ClientPrototypeConstruct = {
	FrameId: string,
	Head: ClientSelection,
	Arm: ClientSelection,
	Legs: ClientSelection,
}

type ClientModularSnapshot = {
	UnbankedComponents: { ClientComponentEntry },
	BankedComponents: { ClientComponentEntry },
	PrototypeConstruct: ClientPrototypeConstruct?,
}

local ModularPrototypeReplicationService = {}

local REQUEST_INTERVAL_SECONDS = 1

local stateRequest: RemoteEvent? = nil
local stateSnapshot: RemoteEvent? = nil
local lastRequestTimes: { [Player]: number } = {}
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][ModularReplication] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][ModularReplication] %s.%s must be a %s, but found %s.",
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

local function buildClientEntries(componentCounts: ModularPrototypeStateService.ComponentCounts): { ClientComponentEntry }
	local entries: { ClientComponentEntry } = {}
	for componentId, rarityCounts in pairs(componentCounts) do
		local definition = Components.GetDefinition(componentId)
		if definition then
			for rarity, count in pairs(rarityCounts) do
				if Components.IsValidRarity(rarity) and count > 0 then
					table.insert(entries, {
						ComponentId = componentId,
						DisplayName = definition.DisplayName,
						Rarity = rarity,
						Slot = definition.Slot,
						Count = count,
					})
				end
			end
		end
	end

	table.sort(entries, function(left: ClientComponentEntry, right: ClientComponentEntry): boolean
		if left.ComponentId == right.ComponentId then
			return left.Rarity < right.Rarity
		end
		return left.ComponentId < right.ComponentId
	end)
	return entries
end

local function buildClientSelection(selection: ModularPrototypeStateService.ComponentSelection): ClientSelection?
	local definition = Components.GetDefinition(selection.ComponentId)
	if not definition or not Components.IsValidRarity(selection.Rarity) then
		return nil
	end
	return {
		ComponentId = selection.ComponentId,
		DisplayName = definition.DisplayName,
		Rarity = selection.Rarity,
	}
end

local function buildClientConstruct(
	construct: ModularPrototypeStateService.PrototypeConstruct?
): ClientPrototypeConstruct?
	if not construct then
		return nil
	end

	local head = buildClientSelection(construct.Head)
	local arm = buildClientSelection(construct.Arm)
	local legs = buildClientSelection(construct.Legs)
	if construct.FrameId ~= "SmallBiped_v1" or not head or not arm or not legs then
		return nil
	end

	return {
		FrameId = construct.FrameId,
		Head = head,
		Arm = arm,
		Legs = legs,
	}
end

-- Inventories and the complete Construct are copied into presentation records;
-- no private table or mutable server reference crosses the network boundary.
local function buildSanitizedSnapshot(player: Player): ClientModularSnapshot?
	local snapshot = ModularPrototypeStateService.GetSnapshot(player)
	if not snapshot then
		return nil
	end

	return {
		UnbankedComponents = buildClientEntries(snapshot.UnbankedComponents),
		BankedComponents = buildClientEntries(snapshot.BankedComponents),
		PrototypeConstruct = buildClientConstruct(snapshot.PrototypeConstruct),
	}
end

local function sendSnapshot(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end

	local payload = buildSanitizedSnapshot(player)
	local remote = stateSnapshot
	if not payload or not remote then
		return false
	end

	remote:FireClient(player, payload)
	return true
end

local function passesRequestThrottle(player: Player): boolean
	local now = os.clock()
	local lastRequest = lastRequestTimes[player]
	if lastRequest and now - lastRequest < REQUEST_INTERVAL_SECONDS then
		return false
	end

	lastRequestTimes[player] = now
	return true
end

-- The request contains no inventory values: it only asks the server to create a
-- fresh sanitized snapshot for the automatically supplied requesting Player.
local function handleStateRequest(player: Player, ...: any)
	if select("#", ...) ~= 0 or not passesRequestThrottle(player) then
		return
	end

	if not ModularPrototypeStateService.HasState(player) then
		return
	end

	sendSnapshot(player)
end

function ModularPrototypeReplicationService.Start()
	if started then
		return
	end
	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local requestRemote = requireChildOfClass(networkFolder, "ModularStateRequest", "RemoteEvent") :: RemoteEvent
	stateRequest = requestRemote
	stateSnapshot = requireChildOfClass(networkFolder, "ModularStateSnapshot", "RemoteEvent") :: RemoteEvent

	requestRemote.OnServerEvent:Connect(handleStateRequest)
	ModularPrototypeStateService.ObserveStateChanged(function(player: Player)
		sendSnapshot(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestTimes[player] = nil
	end)

	print("[ODDWORKS][ModularReplication] Sanitized inventory/construct replication started.")
end

return ModularPrototypeReplicationService
