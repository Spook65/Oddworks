--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))

type NodeState = "AVAILABLE" | "COOLDOWN"

type SalvageNode = {
	Id: string,
	Part: BasePart,
	Prompt: ProximityPrompt,
	State: NodeState,
	OriginalTransparency: number,
}

local EXPECTED_NODE_IDS = {
	"Salvage01",
	"Salvage02",
	"Salvage03",
}

local SCRAP_REWARD = 1
local RESPAWN_SECONDS = 3
local MAX_VALID_DISTANCE = 12
local PLAYER_INTERACTION_SECONDS = 0.25

local NODE_AVAILABLE: NodeState = "AVAILABLE"
local NODE_COOLDOWN: NodeState = "COOLDOWN"

local SalvageService = {}

-- SalvageService privately owns node availability so clients cannot decide
-- whether a node is collectible or how much Scrap it pays.
local registeredNodes: { [string]: SalvageNode } = {}
local lastPlayerInteractionTimes: { [Player]: number } = {}
local started = false

-- Validates required world objects without creating replacement map content.
-- Salvage nodes are persistent Rojo/Studio objects; this service only attaches server behavior.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][SalvageService] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end

	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][SalvageService] %s.%s must be a %s, but found %s.",
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

-- Returns the authoritative root part used for distance checks.
-- ProximityPrompt is useful UI, but the server still checks range because the client is untrusted.
local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	return root
end

-- Applies the simple unavailable/available visual state from the server.
-- This is intentionally minimal feedback, not polished client VFX.
local function setNodeAvailability(node: SalvageNode, isAvailable: boolean)
	node.State = if isAvailable then NODE_AVAILABLE else NODE_COOLDOWN
	node.Prompt.Enabled = isAvailable
	node.Part.Transparency = if isAvailable then node.OriginalTransparency else 0.65
end

-- Lightweight per-player throttling reduces noisy repeated invalid triggers.
-- It is not a replacement for node availability, distance, or state validation.
local function passesPlayerInteractionLimit(player: Player): boolean
	local now = os.clock()
	local lastInteractionTime = lastPlayerInteractionTimes[player]

	if lastInteractionTime ~= nil and now - lastInteractionTime < PLAYER_INTERACTION_SECONDS then
		return false
	end

	lastPlayerInteractionTimes[player] = now
	return true
end

-- Checks every condition required before the server awards Scrap.
-- The returned boolean keeps the reward path boring: reject invalid attempts without mutating economy state.
local function canCollect(player: Player, node: SalvageNode): boolean
	if player.Parent ~= Players then
		return false
	end

	if not passesPlayerInteractionLimit(player) then
		return false
	end

	if not PlayerStateService.HasState(player) then
		return false
	end

	if registeredNodes[node.Id] ~= node or node.Part.Parent == nil then
		return false
	end

	if node.State ~= NODE_AVAILABLE then
		return false
	end

	local root = getCharacterRoot(player)
	if not root then
		return false
	end

	local distance = (root.Position - node.Part.Position).Magnitude
	if distance > MAX_VALID_DISTANCE then
		return false
	end

	return true
end

-- Handles a server-side ProximityPrompt trigger with reservation-before-reward ordering.
-- Marking the node unavailable first prevents two near-simultaneous triggers from both earning Scrap.
local function collectNode(player: Player, node: SalvageNode)
	if not canCollect(player, node) then
		return
	end

	setNodeAvailability(node, false)

	local didAwardScrap = PlayerStateService.AddScrap(player, SCRAP_REWARD)
	if not didAwardScrap then
		setNodeAvailability(node, true)
		warn(string.format("[ODDWORKS][SalvageService] Failed to award Scrap for %s.", player.Name))
		return
	end

	local snapshot = PlayerStateService.GetSnapshot(player)
	local totalScrap = if snapshot then tostring(snapshot.Scrap) else "unknown"
	print(string.format("[ODDWORKS][SalvageService] %s collected %s (+%d Scrap, total Scrap: %s)", player.Name, node.Id, SCRAP_REWARD, totalScrap))

	task.delay(RESPAWN_SECONDS, function()
		if registeredNodes[node.Id] == node and node.State == NODE_COOLDOWN then
			setNodeAvailability(node, true)
		end
	end)
end

-- Discovers the three named persistent salvage nodes and connects their prompts on the server.
-- No RemoteEvent is needed because ProximityPrompt.Triggered already tells the server which Player interacted.
local function discoverNodes(): { [string]: SalvageNode }
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local salvageField = requireChildOfClass(world, "SalvageField", "BasePart")
	local discoveredNodes: { [string]: SalvageNode } = {}

	for _, nodeId in ipairs(EXPECTED_NODE_IDS) do
		local nodePart = requireChildOfClass(salvageField, nodeId, "BasePart") :: BasePart
		local prompt = requireChildOfClass(nodePart, "Prompt", "ProximityPrompt") :: ProximityPrompt

		local node: SalvageNode = {
			Id = nodeId,
			Part = nodePart,
			Prompt = prompt,
			State = NODE_AVAILABLE,
			OriginalTransparency = nodePart.Transparency,
		}

		setNodeAvailability(node, true)
		prompt.Triggered:Connect(function(player: Player)
			collectNode(player, node)
		end)

		discoveredNodes[nodeId] = node
	end

	return discoveredNodes
end

-- Starts salvage once after PlayerStateService is available.
-- This service mutates only server-owned Scrap and keeps node cooldowns in server memory.
function SalvageService.Start()
	if started then
		return
	end

	started = true
	registeredNodes = discoverNodes()

	Players.PlayerRemoving:Connect(function(player: Player)
		lastPlayerInteractionTimes[player] = nil
	end)

	print(string.format("[ODDWORKS][SalvageService] Service started with %d nodes.", #EXPECTED_NODE_IDS))
end

return SalvageService
