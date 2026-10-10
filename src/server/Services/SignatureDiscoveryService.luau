--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][SignatureDiscovery] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local ConstructCapabilityResolver = require(Services:WaitForChild("ConstructCapabilityResolver"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))
local SignatureDiscoveryConfig = require(Config:WaitForChild("SignatureDiscoveryConfig"))

type Definition = SignatureDiscoveryConfig.SignatureDiscoveryDefinition
type DiscoverySource = "SIGNAL" | "FURNACE_POD"
type OpportunityRuntime = {
	Model: Model,
	InteractionPart: BasePart,
	CueAnchor: BasePart,
	Prompt: ProximityPrompt,
	RevealMarkersByPlot: { [string]: BasePart },
}

local SignatureDiscoveryService = {}

local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "SignatureOddlings"
local PLAYER_CONTAINER_PREFIX = "Player_"
local STATE_REQUEST_INTERVAL_SECONDS = 1

local discoveries: { [Player]: boolean } = {}
local discoverySources: { [Player]: DiscoverySource } = {}
local lastAttemptTimes: { [Player]: number } = {}
local lastStateRequestTimes: { [Player]: number } = {}
local pendingReconciliations: { [Player]: boolean } = {}
local runtimeFolder: Folder? = nil
local opportunityRuntime: OpportunityRuntime? = nil
local stateRemote: RemoteEvent? = nil
local definition: Definition? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(
			string.format("[ODDWORKS][SignatureDiscovery] Missing required object: %s.%s", parent:GetFullName(), childName),
			2
		)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][SignatureDiscovery] %s.%s must be a %s, but found %s.",
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

local function getOrCreateFolder(parent: Instance, childName: string): Folder
	local existing = parent:FindFirstChild(childName)
	if existing then
		if not existing:IsA("Folder") then
			error(string.format("[ODDWORKS][SignatureDiscovery] %s must be a Folder.", existing:GetFullName()))
		end
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = childName
	folder.Parent = parent
	return folder
end

local function containsExecutableContent(instance: Instance): boolean
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			return true
		end
	end
	return false
end

local function countBaseParts(instance: Instance): number
	local count = if instance:IsA("BasePart") then 1 else 0
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function isPositiveFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value > 0
end

local function validateDefinition(candidate: Definition)
	if candidate.OpportunityId ~= "KilnbackSignal"
		or candidate.SignatureId ~= "Kilnback"
		or not isPositiveFinite(candidate.MaxValidDistance)
		or not isPositiveFinite(candidate.AttemptIntervalSeconds)
		or not isPositiveFinite(candidate.AuditIntervalSeconds)
		or candidate.RevealMarkerNamesByPlot.Plot01 == nil
		or candidate.RevealMarkerNamesByPlot.Plot02 == nil
		or #candidate.WorkshopRevealMarkerName == 0
	then
		error("[ODDWORKS][SignatureDiscovery] Signature discovery configuration is invalid.")
	end
end

local function getRevealMarker(player: Player, opportunity: OpportunityRuntime, candidate: Definition): BasePart?
	if discoverySources[player] == "FURNACE_POD" then
		local plot = WorkshopService.GetAssignedPlot(player)
		local marker = if plot then plot:FindFirstChild(candidate.WorkshopRevealMarkerName) else nil
		return if marker and marker:IsA("BasePart") then marker else nil
	end

	local plotId = WorkshopService.GetAssignedPlotId(player)
	return if plotId then opportunity.RevealMarkersByPlot[plotId] else nil
end

local function discoverOpportunity(candidate: Definition): OpportunityRuntime
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local model = requireChildOfClass(world, candidate.WorldModelName, "Model") :: Model
	local interactionPart = requireChildOfClass(model, candidate.InteractionPartName, "BasePart") :: BasePart
	local cueAnchor = requireChildOfClass(model, candidate.CueAnchorName, "BasePart") :: BasePart
	local prompt = requireChildOfClass(interactionPart, "Prompt", "ProximityPrompt") :: ProximityPrompt
	local revealMarkersByPlot: { [string]: BasePart } = {}
	for plotId, markerName in pairs(candidate.RevealMarkerNamesByPlot) do
		revealMarkersByPlot[plotId] = requireChildOfClass(model, markerName, "BasePart") :: BasePart
	end

	return {
		Model = model,
		InteractionPart = interactionPart,
		CueAnchor = cueAnchor,
		Prompt = prompt,
		RevealMarkersByPlot = revealMarkersByPlot,
	}
end

local function getTemplate(candidate: Definition): Model?
	local assets = ServerStorage:FindFirstChild("ODDWORKSAssets")
	local signatures = if assets then assets:FindFirstChild("Signatures") else nil
	local template = if signatures then signatures:FindFirstChild(candidate.TemplateName) else nil
	if not template or not template:IsA("Model") then
		warn("[ODDWORKS][SignatureDiscovery] Kilnback runtime template is missing.")
		return nil
	end
	if containsExecutableContent(template) then
		warn("[ODDWORKS][SignatureDiscovery] Kilnback template contains executable content and was rejected.")
		return nil
	end

	local rootPart = template:FindFirstChild("RootPart")
	if not rootPart or not rootPart:IsA("BasePart") or rootPart.Parent ~= template or countBaseParts(template) < 6 then
		warn("[ODDWORKS][SignatureDiscovery] Kilnback template hierarchy is invalid.")
		return nil
	end
	return template
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getPlayerContainerName(player: Player): string
	return PLAYER_CONTAINER_PREFIX .. tostring(player.UserId)
end

local function getPlayerContainer(player: Player, create: boolean): Folder?
	local folder = runtimeFolder
	if not folder then
		return nil
	end

	local name = getPlayerContainerName(player)
	local existing = folder:FindFirstChild(name)
	if existing then
		return if existing:IsA("Folder") then existing else nil
	end
	if not create then
		return nil
	end

	local container = Instance.new("Folder")
	container.Name = name
	container:SetAttribute("OwnerUserId", player.UserId)
	container.Parent = folder
	return container
end

local function destroyRuntime(player: Player)
	local container = getPlayerContainer(player, false)
	if container then
		container:Destroy()
	end
end

local function sendState(player: Player, kind: string)
	local remote = stateRemote
	local candidate = definition
	if not remote or not candidate or player.Parent ~= Players then
		return
	end

	remote:FireClient(player, {
		Kind = kind,
		OpportunityId = candidate.OpportunityId,
		SignatureId = candidate.SignatureId,
		Discovered = discoveries[player] == true,
	})
end

local function buildKilnback(player: Player, template: Model, marker: BasePart, candidate: Definition): Model?
	local model = template:Clone()
	model.Name = candidate.SignatureId
	local rootPart = model:FindFirstChild("RootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		model:Destroy()
		return nil
	end

	model.PrimaryPart = rootPart
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	model:PivotTo(marker.CFrame)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("SignatureId", candidate.SignatureId)
	model:SetAttribute("TemplatePartCount", countBaseParts(template))
	return model
end

local function isRuntimeValid(
	player: Player,
	model: Model,
	template: Model,
	marker: BasePart,
	candidate: Definition
): boolean
	if model.Name ~= candidate.SignatureId
		or model:GetAttribute("OwnerUserId") ~= player.UserId
		or model:GetAttribute("SignatureId") ~= candidate.SignatureId
		or model:GetAttribute("TemplatePartCount") ~= countBaseParts(template)
		or countBaseParts(model) ~= countBaseParts(template)
	then
		return false
	end

	local rootPart = model:FindFirstChild("RootPart")
	if not rootPart or not rootPart:IsA("BasePart") or model.PrimaryPart ~= rootPart then
		return false
	end
	if (rootPart.Position - marker.Position).Magnitude > 0.01 then
		return false
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			return false
		end
	end
	return true
end

function SignatureDiscoveryService.Reconcile(player: Player): boolean
	local candidate = definition
	local opportunity = opportunityRuntime
	if not started or not candidate or not opportunity then
		return false
	end
	if player.Parent ~= Players or discoveries[player] ~= true then
		destroyRuntime(player)
		return true
	end

	local marker = getRevealMarker(player, opportunity, candidate)
	local template = getTemplate(candidate)
	if not marker or not template then
		destroyRuntime(player)
		return false
	end

	local container = getPlayerContainer(player, true)
	if not container then
		return false
	end
	local runtimeModel: Model? = nil
	local modelCount = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			modelCount += 1
			runtimeModel = child
		end
	end
	if modelCount == 1 and runtimeModel and isRuntimeValid(player, runtimeModel, template, marker, candidate) then
		return true
	end

	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	local rebuilt = buildKilnback(player, template, marker, candidate)
	if not rebuilt then
		return false
	end
	rebuilt.Parent = container
	print(string.format("[ODDWORKS][SignatureDiscovery] Reconstructed Kilnback for %s.", player.Name))
	return true
end

local function queueReconcile(player: Player)
	if pendingReconciliations[player] then
		return
	end
	pendingReconciliations[player] = true
	task.defer(function()
		pendingReconciliations[player] = nil
		SignatureDiscoveryService.Reconcile(player)
	end)
end

local function passesAttemptThrottle(player: Player, candidate: Definition): boolean
	local now = os.clock()
	local lastAttempt = lastAttemptTimes[player]
	if lastAttempt and now - lastAttempt < candidate.AttemptIntervalSeconds then
		return false
	end
	lastAttemptTimes[player] = now
	return true
end

local function handlePromptTriggered(player: Player)
	local candidate = definition
	local opportunity = opportunityRuntime
	if not candidate
		or not opportunity
		or player.Parent ~= Players
		or not passesAttemptThrottle(player, candidate)
		or discoveries[player]
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not ConstructCapabilityResolver.CanDetectStrangeSignals(player)
	then
		return
	end
	if opportunity.Model.Parent == nil
		or opportunity.InteractionPart.Parent ~= opportunity.Model
		or opportunity.Prompt.Parent ~= opportunity.InteractionPart
	then
		return
	end

	local root = getCharacterRoot(player)
	if not root or (root.Position - opportunity.InteractionPart.Position).Magnitude > candidate.MaxValidDistance then
		return
	end

	-- This no-yield assignment is the complete session discovery transaction.
	-- Physical construction happens afterward and cannot revoke or duplicate it.
	discoveries[player] = true
	discoverySources[player] = "SIGNAL"
	sendState(player, "REVEALED")
	queueReconcile(player)
	print(string.format("[ODDWORKS][SignatureDiscovery] %s discovered Kilnback for this session.", player.Name))
end

-- This server-only entry point lets another validated server gameplay flow use
-- the existing session discovery and derived Kilnback runtime. It deliberately
-- does not relax the SignalScanner requirement on the public world prompt.
function SignatureDiscoveryService.RevealKilnbackFromFurnacePod(player: Player): boolean
	if not started
		or player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not WorkshopService.GetAssignedPlot(player)
	then
		return false
	end

	discoveries[player] = true
	discoverySources[player] = "FURNACE_POD"
	-- The chase controller owns the reveal banner. STATE updates the existing
	-- scanner presentation without firing its separate discovery celebration.
	sendState(player, "STATE")
	queueReconcile(player)
	print(string.format("[ODDWORKS][SignatureDiscovery] %s revealed Kilnback from a secured Furnace Pod.", player.Name))
	return true
end

-- Exposes only session-discovery and derived-presence facts for the Studio
-- inspector. Discovery ownership and runtime Instances remain private.
function SignatureDiscoveryService.GetDiagnosticSnapshot(player: Player): { [string]: any }
	local container = getPlayerContainer(player, false)
	local modelCount = 0
	if container then
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") then
				modelCount += 1
			end
		end
	end

	return {
		Discovered = discoveries[player] == true,
		RuntimePresent = modelCount == 1,
		RuntimeCount = modelCount,
	}
end

local function handleStateRequest(player: Player, ...: any)
	if select("#", ...) ~= 0 or player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local lastRequest = lastStateRequestTimes[player]
	if lastRequest and now - lastRequest < STATE_REQUEST_INTERVAL_SECONDS then
		return
	end
	lastStateRequestTimes[player] = now
	if not PlayerStateService.HasState(player) or not ModularPrototypeStateService.HasState(player) then
		return
	end
	sendState(player, "STATE")
end

local function cleanupPlayer(player: Player)
	discoveries[player] = nil
	discoverySources[player] = nil
	lastAttemptTimes[player] = nil
	lastStateRequestTimes[player] = nil
	pendingReconciliations[player] = nil
	destroyRuntime(player)
end

function SignatureDiscoveryService.Start()
	if started then
		return
	end
	started = true

	local candidate = SignatureDiscoveryConfig.GetDefinition()
	validateDefinition(candidate)
	definition = candidate
	opportunityRuntime = discoverOpportunity(candidate)

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local requestRemote = requireChildOfClass(network, "SignatureDiscoveryStateRequest", "RemoteEvent") :: RemoteEvent
	stateRemote = requireChildOfClass(network, "SignatureDiscoveryState", "RemoteEvent") :: RemoteEvent
	requestRemote.OnServerEvent:Connect(handleStateRequest)

	local runtimeRoot = getOrCreateFolder(Workspace, RUNTIME_ROOT_NAME)
	runtimeFolder = getOrCreateFolder(runtimeRoot, RUNTIME_FOLDER_NAME)

	local opportunity = opportunityRuntime :: OpportunityRuntime
	opportunity.Prompt.Triggered:Connect(handlePromptTriggered)
	ModularPrototypeStateService.ObserveStateChanged(function(player: Player)
		sendState(player, "STATE")
	end)
	ModularPrototypeStateService.ObserveStateRemoved(cleanupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)

	task.spawn(function()
		while started do
			task.wait(candidate.AuditIntervalSeconds)
			for player in pairs(discoveries) do
				queueReconcile(player)
			end
		end
	end)

	print("[ODDWORKS][SignatureDiscovery] Hidden signal opportunity started; discovery is session-only.")
end

return SignatureDiscoveryService
