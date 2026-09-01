--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))

type ClientStateSnapshot = {
	Scrap: number,
}

local STATE_REQUEST_INTERVAL_SECONDS = 1

local StateReplicationService = {}

-- This service owns only the networking boundary. The authoritative state
-- still lives in PlayerStateService, and clients receive sanitized copies.
local stateRequest: RemoteEvent? = nil
local stateSnapshot: RemoteEvent? = nil
local lastStateRequestTimes: { [Player]: number } = {}
local started = false

-- Verifies expected networking objects that are represented in Rojo.
-- The server refuses to continue if a remote is missing or has the wrong class.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][StateReplicationService] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end

	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][StateReplicationService] %s.%s must be a %s, but found %s.",
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

-- Builds the tiny client-safe payload for this pass.
-- Only Scrap is exposed; nested tables and server-only economy details stay private.
local function buildSanitizedSnapshot(player: Player): ClientStateSnapshot?
	local authoritativeSnapshot = PlayerStateService.GetSnapshot(player)
	if not authoritativeSnapshot then
		return nil
	end

	return {
		Scrap = authoritativeSnapshot.Scrap,
	}
end

-- Sends the latest sanitized state to exactly one player.
-- Private progression state must use FireClient, never FireAllClients.
local function sendSnapshotToPlayer(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end

	local snapshot = buildSanitizedSnapshot(player)
	if not snapshot then
		return false
	end

	local snapshotRemote = stateSnapshot
	if not snapshotRemote then
		return false
	end

	snapshotRemote:FireClient(player, snapshot)
	return true
end

-- Limits accepted refresh requests so a client cannot spam the server for unlimited snapshots.
-- Rate limiting is server-owned; client-side cooldowns would only be presentation.
local function passesStateRequestThrottle(player: Player): boolean
	local now = os.clock()
	local lastRequestTime = lastStateRequestTimes[player]

	if lastRequestTime ~= nil and now - lastRequestTime < STATE_REQUEST_INTERVAL_SECONDS then
		return false
	end

	lastStateRequestTimes[player] = now
	return true
end

-- Handles the read-only client request for its own current state.
-- Roblox supplies the Player to OnServerEvent, so the client never sends a target Player or Scrap value.
local function handleStateRequest(player: Player, ...: any)
	if not passesStateRequestThrottle(player) then
		return
	end

	if select("#", ...) ~= 0 then
		warn(string.format("[ODDWORKS][StateReplicationService] Rejected StateRequest payload from %s.", player.Name))
		return
	end

	if not PlayerStateService.HasState(player) then
		return
	end

	sendSnapshotToPlayer(player)
end

-- Starts the state replication boundary once.
-- It listens to server-internal state changes and pushes sanitized snapshots to the affected client only.
function StateReplicationService.Start()
	if started then
		return
	end

	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local requestRemote = requireChildOfClass(networkFolder, "StateRequest", "RemoteEvent") :: RemoteEvent
	local snapshotRemote = requireChildOfClass(networkFolder, "StateSnapshot", "RemoteEvent") :: RemoteEvent
	stateRequest = requestRemote
	stateSnapshot = snapshotRemote

	requestRemote.OnServerEvent:Connect(handleStateRequest)
	PlayerStateService.ObserveStateChanged(function(player: Player)
		sendSnapshotToPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastStateRequestTimes[player] = nil
	end)

	print("[ODDWORKS][StateReplicationService] Service started.")
end

return StateReplicationService
