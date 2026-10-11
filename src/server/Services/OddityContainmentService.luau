--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][OddityContainment] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local OddityContainmentConfig = require(Config:WaitForChild("OddityContainmentConfig"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type Definition = OddityContainmentConfig.OddityContainmentDefinition
type ActivityPhase = "AVAILABLE" | "ACTIVE" | "RESOLVING" | "SUCCEEDED" | "FAILED" | "RESETTING"
type GateRuntime = {
	Id: string,
	Model: Model,
	Control: BasePart,
	Barrier: BasePart,
	Prompt: ProximityPrompt,
	ClosedCFrame: CFrame,
}
type ActivityRuntime = {
	Model: Model,
	StartConsole: BasePart,
	StartPrompt: ProximityPrompt,
	Gates: { [string]: GateRuntime },
	Waypoints: { [string]: BasePart },
	ContainmentVolume: BasePart,
	EscapeVolume: BasePart,
}

local OddityContainmentService = {}

local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "OddityContainment"
local SPARKMITE_MODEL_NAME = "Sparkmite"
local REQUIRED_WAYPOINTS = {
	"Spawn",
	"SouthRun",
	"BranchA",
	"InnerCross",
	"OuterRun",
	"BranchB",
	"CageEntry",
	"Cage",
	"Escape",
}

local phase: ActivityPhase = "AVAILABLE"
local owner: Player? = nil
local generation = 0
local gateOpen: { [string]: boolean } = {
	GateA = true,
	GateB = true,
}
local claimedRewards: { [Player]: boolean } = {}
local lastStartTimes: { [Player]: number } = {}
local lastGateTimes: { [Player]: number } = {}
local activeDeathConnection: RBXScriptConnection? = nil
local activeCharacterRemovingConnection: RBXScriptConnection? = nil
local targetModel: Model? = nil
local runtimeFolder: Folder? = nil
local runtime: ActivityRuntime? = nil
local definition: Definition? = nil
local stateRemote: RemoteEvent? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(
			string.format("[ODDWORKS][OddityContainment] Missing required object: %s.%s", parent:GetFullName(), childName),
			2
		)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][OddityContainment] %s.%s must be a %s, but found %s.",
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
			error(string.format("[ODDWORKS][OddityContainment] %s must be a Folder.", existing:GetFullName()))
		end
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = childName
	folder.Parent = parent
	return folder
end

local function isPositiveFinite(value: number): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
end

local function validateDefinition(candidate: Definition)
	if candidate.WorldModelName ~= "OddityContainmentYard"
		or candidate.RewardComponentId ~= "ServoArm"
		or candidate.RewardRarity ~= "Rare"
		or candidate.RewardCount ~= 1
		or candidate.GateModelNames.GateA == nil
		or candidate.GateModelNames.GateB == nil
		or not isPositiveFinite(candidate.MaxStartDistance)
		or not isPositiveFinite(candidate.MaxGateDistance)
		or not isPositiveFinite(candidate.StartIntervalSeconds)
		or not isPositiveFinite(candidate.GateIntervalSeconds)
		or not isPositiveFinite(candidate.MovementSpeed)
		or not isPositiveFinite(candidate.MovementStepSeconds)
		or not isPositiveFinite(candidate.FailureResetSeconds)
		or not isPositiveFinite(candidate.SuccessResetSeconds)
	then
		error("[ODDWORKS][OddityContainment] Configuration is invalid.")
	end
end

local function getCharacterRootAndHumanoid(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function isInsideVolume(position: Vector3, volume: BasePart): boolean
	local localPosition = volume.CFrame:PointToObjectSpace(position)
	local halfSize = volume.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function disconnectActiveLifecycle()
	if activeDeathConnection then
		activeDeathConnection:Disconnect()
		activeDeathConnection = nil
	end
	if activeCharacterRemovingConnection then
		activeCharacterRemovingConnection:Disconnect()
		activeCharacterRemovingConnection = nil
	end
end

local function sendState(player: Player, payload: { [string]: any })
	local remote = stateRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function setStartAvailable(isAvailable: boolean)
	local activityRuntime = runtime
	if activityRuntime then
		activityRuntime.StartPrompt.Enabled = isAvailable
	end
end

local function updateGatePresentation(gate: GateRuntime, isOpen: boolean)
	gate.Barrier.CFrame = if isOpen then gate.ClosedCFrame * CFrame.new(0, 6, 0) else gate.ClosedCFrame
	gate.Barrier.Color = if isOpen then Color3.fromRGB(76, 213, 143) else Color3.fromRGB(235, 82, 52)
	gate.Barrier.Transparency = if isOpen then 0.35 else 0.05
	gate.Barrier.CanCollide = not isOpen
	gate.Control.Color = if isOpen then Color3.fromRGB(76, 213, 143) else Color3.fromRGB(235, 82, 52)
	gate.Prompt.ActionText = if isOpen then "CLOSE " .. string.upper(gate.Id) else "OPEN " .. string.upper(gate.Id)
end

local function setGatePromptsEnabled(enabled: boolean)
	local activityRuntime = runtime
	if not activityRuntime then
		return
	end
	for _, gate in pairs(activityRuntime.Gates) do
		gate.Prompt.Enabled = enabled
	end
end

local function resetGates()
	local activityRuntime = runtime
	gateOpen.GateA = true
	gateOpen.GateB = true
	if not activityRuntime then
		return
	end
	for gateId, gate in pairs(activityRuntime.Gates) do
		updateGatePresentation(gate, gateOpen[gateId] == true)
	end
end

local function createDisplayPart(
	model: Model,
	name: string,
	rootCFrame: CFrame,
	localCFrame: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = rootCFrame * localCFrame
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

local function destroyTarget()
	if targetModel then
		targetModel:Destroy()
		targetModel = nil
	end
end

local function buildSparkmite(atCFrame: CFrame, attemptGeneration: number, attemptOwner: Player?): Model?
	local folder = runtimeFolder
	if not folder then
		return nil
	end

	destroyTarget()
	local model = Instance.new("Model")
	model.Name = SPARKMITE_MODEL_NAME

	local body = createDisplayPart(
		model,
		"RootPart",
		atCFrame,
		CFrame.new(0, 0, 0),
		Vector3.new(2.6, 1.8, 3.2),
		Color3.fromRGB(53, 66, 72),
		Enum.Material.Metal,
		Enum.PartType.Ball
	)
	createDisplayPart(model, "FacePlate", atCFrame, CFrame.new(0, 0, -1.45), Vector3.new(1.7, 0.9, 0.25), Color3.fromRGB(192, 119, 45), Enum.Material.CorrodedMetal, nil)
	createDisplayPart(model, "SignalEye", atCFrame, CFrame.new(0, 0.12, -1.62), Vector3.new(0.65, 0.65, 0.2), Color3.fromRGB(95, 240, 255), Enum.Material.Neon, Enum.PartType.Ball)
	createDisplayPart(model, "LeftLeg", atCFrame, CFrame.new(-0.85, -1, 0.35), Vector3.new(0.45, 1.1, 0.55), Color3.fromRGB(116, 124, 126), Enum.Material.Metal, nil)
	createDisplayPart(model, "RightLeg", atCFrame, CFrame.new(0.85, -1, 0.35), Vector3.new(0.45, 1.1, 0.55), Color3.fromRGB(116, 124, 126), Enum.Material.Metal, nil)
	createDisplayPart(model, "SparkCoil", atCFrame, CFrame.new(0, 0.95, 0.35), Vector3.new(0.55, 1.1, 0.55), Color3.fromRGB(255, 192, 56), Enum.Material.Neon, nil)
	model.PrimaryPart = body
	model:SetAttribute("ActivityGeneration", attemptGeneration)
	model:SetAttribute("OwnerUserId", if attemptOwner then attemptOwner.UserId else 0)
	model:SetAttribute("OddityId", "Sparkmite")
	model.Parent = folder
	targetModel = model
	return model
end

local function resetTargetToSpawn()
	local activityRuntime = runtime
	if not activityRuntime then
		return
	end
	buildSparkmite(activityRuntime.Waypoints.Spawn.CFrame, generation, nil)
end

local function isTargetValid(attemptToken: number): boolean
	local model = targetModel
	return model ~= nil
		and model.Parent == runtimeFolder
		and model.PrimaryPart ~= nil
		and model.PrimaryPart:IsDescendantOf(model)
		and model:GetAttribute("ActivityGeneration") == attemptToken
end

local function isOwnerReady(player: Player): boolean
	return player.Parent == Players
		and PlayerStateService.HasState(player)
		and ModularPrototypeStateService.HasState(player)
		and WorkshopService.HasPlot(player)
		and getCharacterRootAndHumanoid(player) ~= nil
end

local function transitionToAvailable()
	phase = "AVAILABLE"
	owner = nil
	disconnectActiveLifecycle()
	resetGates()
	setGatePromptsEnabled(false)
	setStartAvailable(true)
	resetTargetToSpawn()
end

local function scheduleReset(resetToken: number, delaySeconds: number)
	task.delay(delaySeconds, function()
		if generation ~= resetToken or phase ~= "RESETTING" then
			return
		end
		transitionToAvailable()
	end)
end

local function terminateAttempt(player: Player, attemptToken: number, kind: string, useDelay: boolean)
	if generation ~= attemptToken or owner ~= player or (phase ~= "ACTIVE" and phase ~= "RESOLVING") then
		return
	end

	generation += 1
	local resetToken = generation
	phase = if kind == "ESCAPED" then "FAILED" else "RESETTING"
	disconnectActiveLifecycle()
	setGatePromptsEnabled(false)
	setStartAvailable(false)
	if player.Parent == Players then
		sendState(player, { Kind = kind })
	end
	owner = nil
	resetGates()

	if useDelay then
		phase = "RESETTING"
		local candidate = definition
		if candidate then
			scheduleReset(resetToken, candidate.FailureResetSeconds)
		end
	else
		phase = "RESETTING"
		transitionToAvailable()
	end
end

local function completeContainment(player: Player, attemptToken: number, candidate: Definition)
	if generation ~= attemptToken or owner ~= player or phase ~= "ACTIVE" then
		return
	end
	phase = "RESOLVING"
	setGatePromptsEnabled(false)

	if not isOwnerReady(player) or claimedRewards[player] == true then
		terminateAttempt(player, attemptToken, "CANCELLED", false)
		return
	end

	local granted = ModularPrototypeStateService.AddBankedComponent(
		player,
		candidate.RewardComponentId,
		candidate.RewardRarity,
		candidate.RewardCount
	)
	if not granted then
		warn(string.format("[ODDWORKS][OddityContainment] Reward transaction failed for %s.", player.Name))
		terminateAttempt(player, attemptToken, "REWARD_FAILED", true)
		return
	end

	claimedRewards[player] = true
	generation += 1
	local resetToken = generation
	phase = "SUCCEEDED"
	disconnectActiveLifecycle()
	setStartAvailable(false)
	setGatePromptsEnabled(false)
	owner = nil
	sendState(player, {
		Kind = "CONTAINED",
		ComponentId = candidate.RewardComponentId,
		Rarity = candidate.RewardRarity,
		Count = candidate.RewardCount,
	})
	print(string.format("[ODDWORKS][OddityContainment] %s contained Sparkmite and banked ServoArm [Rare] x1.", player.Name))
	phase = "RESETTING"
	scheduleReset(resetToken, candidate.SuccessResetSeconds)
end

local function chooseNextNode(currentNode: string, previousNode: string?): string?
	if currentNode == "Spawn" then
		return "SouthRun"
	elseif currentNode == "SouthRun" then
		return "BranchA"
	elseif currentNode == "BranchA" then
		return if gateOpen.GateA then "OuterRun" else "InnerCross"
	elseif currentNode == "InnerCross" or currentNode == "OuterRun" then
		return "BranchB"
	elseif currentNode == "BranchB" then
		if gateOpen.GateB then
			return "SouthRun"
		end
		return if previousNode == "InnerCross" then "CageEntry" else "Escape"
	elseif currentNode == "CageEntry" then
		return "Cage"
	end
	return nil
end

local function moveTargetTo(player: Player, attemptToken: number, waypoint: BasePart, candidate: Definition): boolean
	local model = targetModel
	if not model or not model.PrimaryPart then
		return false
	end
	local startCFrame = model:GetPivot()
	local targetCFrame = CFrame.lookAt(waypoint.Position, waypoint.Position + Vector3.new(0, 0, -1))
	local distance = (startCFrame.Position - targetCFrame.Position).Magnitude
	local duration = math.max(distance / candidate.MovementSpeed, candidate.MovementStepSeconds)
	local startedAt = os.clock()

	while generation == attemptToken and owner == player and phase == "ACTIVE" do
		if not isTargetValid(attemptToken) or not isOwnerReady(player) then
			return false
		end
		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		model:PivotTo(startCFrame:Lerp(targetCFrame, alpha))
		if alpha >= 1 then
			return true
		end
		task.wait(candidate.MovementStepSeconds)
	end
	return false
end

local function runAttempt(player: Player, attemptToken: number, candidate: Definition)
	local activityRuntime = runtime
	if not activityRuntime then
		terminateAttempt(player, attemptToken, "CANCELLED", false)
		return
	end

	local currentNode = "Spawn"
	local previousNode: string? = nil
	while generation == attemptToken and owner == player and phase == "ACTIVE" do
		local nextNode = chooseNextNode(currentNode, previousNode)
		local nextWaypoint = if nextNode then activityRuntime.Waypoints[nextNode] else nil
		if not nextNode or not nextWaypoint then
			terminateAttempt(player, attemptToken, "CANCELLED", false)
			return
		end

		if not moveTargetTo(player, attemptToken, nextWaypoint, candidate) then
			if generation == attemptToken and owner == player and phase == "ACTIVE" then
				warn("[ODDWORKS][OddityContainment] Sparkmite runtime or owner lifecycle became invalid; resetting attempt.")
				terminateAttempt(player, attemptToken, "CANCELLED", false)
			end
			return
		end

		previousNode = currentNode
		currentNode = nextNode
		local model = targetModel
		local root = if model then model.PrimaryPart else nil
		if currentNode == "Cage" then
			if root and isInsideVolume(root.Position, activityRuntime.ContainmentVolume) then
				completeContainment(player, attemptToken, candidate)
			else
				terminateAttempt(player, attemptToken, "CANCELLED", false)
			end
			return
		elseif currentNode == "Escape" then
			if root and isInsideVolume(root.Position, activityRuntime.EscapeVolume) then
				terminateAttempt(player, attemptToken, "ESCAPED", true)
			else
				terminateAttempt(player, attemptToken, "CANCELLED", false)
			end
			return
		end
	end
end

local function passesThrottle(times: { [Player]: number }, player: Player, interval: number): boolean
	local now = os.clock()
	local lastTime = times[player]
	if lastTime and now - lastTime < interval then
		return false
	end
	times[player] = now
	return true
end

local function beginAttempt(player: Player)
	local activityRuntime = runtime
	local candidate = definition
	if not activityRuntime or not candidate or phase ~= "AVAILABLE" or owner ~= nil then
		return
	end
	if not passesThrottle(lastStartTimes, player, candidate.StartIntervalSeconds)
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not WorkshopService.HasPlot(player)
	then
		return
	end
	if claimedRewards[player] == true then
		sendState(player, { Kind = "COMPLETED" })
		return
	end

	local root, humanoid = getCharacterRootAndHumanoid(player)
	if not root
		or not humanoid
		or (root.Position - activityRuntime.StartConsole.Position).Magnitude > candidate.MaxStartDistance
	then
		return
	end

	generation += 1
	local attemptToken = generation
	phase = "ACTIVE"
	owner = player
	resetGates()
	setStartAvailable(false)
	setGatePromptsEnabled(true)
	local model = buildSparkmite(activityRuntime.Waypoints.Spawn.CFrame, attemptToken, player)
	if not model then
		terminateAttempt(player, attemptToken, "CANCELLED", false)
		return
	end

	activeDeathConnection = humanoid.Died:Connect(function()
		terminateAttempt(player, attemptToken, "CANCELLED", false)
	end)
	activeCharacterRemovingConnection = player.CharacterRemoving:Connect(function()
		terminateAttempt(player, attemptToken, "CANCELLED", false)
	end)
	sendState(player, {
		Kind = "ACTIVE",
		GateAOpen = gateOpen.GateA,
		GateBOpen = gateOpen.GateB,
	})
	print(string.format("[ODDWORKS][OddityContainment] %s started containment attempt %d.", player.Name, attemptToken))
	task.spawn(runAttempt, player, attemptToken, candidate)
end

local function toggleGate(player: Player, gateId: string)
	local activityRuntime = runtime
	local candidate = definition
	if not activityRuntime or not candidate or phase ~= "ACTIVE" or owner ~= player then
		return
	end
	local gate = activityRuntime.Gates[gateId]
	if not gate
		or not passesThrottle(lastGateTimes, player, candidate.GateIntervalSeconds)
		or not isOwnerReady(player)
	then
		return
	end
	local root = getCharacterRootAndHumanoid(player)
	if not root or (root.Position - gate.Control.Position).Magnitude > candidate.MaxGateDistance then
		return
	end

	gateOpen[gateId] = not gateOpen[gateId]
	updateGatePresentation(gate, gateOpen[gateId])
	sendState(player, {
		Kind = "GATE_STATE",
		GateAOpen = gateOpen.GateA,
		GateBOpen = gateOpen.GateB,
	})
end

local function clearPlayer(player: Player)
	claimedRewards[player] = nil
	lastStartTimes[player] = nil
	lastGateTimes[player] = nil
	if owner == player then
		terminateAttempt(player, generation, "CANCELLED", false)
	end
end

local function discoverRuntime(candidate: Definition): ActivityRuntime
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local model = requireChildOfClass(world, candidate.WorldModelName, "Model") :: Model
	local startConsole = requireChildOfClass(model, candidate.StartConsoleName, "BasePart") :: BasePart
	local startPrompt = requireChildOfClass(startConsole, "Prompt", "ProximityPrompt") :: ProximityPrompt
	local waypointFolder = requireChildOfClass(model, candidate.WaypointFolderName, "Folder")
	local waypoints: { [string]: BasePart } = {}
	for _, waypointName in ipairs(REQUIRED_WAYPOINTS) do
		waypoints[waypointName] = requireChildOfClass(waypointFolder, waypointName, "BasePart") :: BasePart
	end

	local gates: { [string]: GateRuntime } = {}
	for gateId, modelName in pairs(candidate.GateModelNames) do
		local gateModel = requireChildOfClass(model, modelName, "Model") :: Model
		local control = requireChildOfClass(gateModel, "Control", "BasePart") :: BasePart
		local barrier = requireChildOfClass(gateModel, "Barrier", "BasePart") :: BasePart
		local prompt = requireChildOfClass(control, "Prompt", "ProximityPrompt") :: ProximityPrompt
		gates[gateId] = {
			Id = gateId,
			Model = gateModel,
			Control = control,
			Barrier = barrier,
			Prompt = prompt,
			ClosedCFrame = barrier.CFrame,
		}
	end

	return {
		Model = model,
		StartConsole = startConsole,
		StartPrompt = startPrompt,
		Gates = gates,
		Waypoints = waypoints,
		ContainmentVolume = requireChildOfClass(model, candidate.ContainmentVolumeName, "BasePart") :: BasePart,
		EscapeVolume = requireChildOfClass(model, candidate.EscapeVolumeName, "BasePart") :: BasePart,
	}
end

function OddityContainmentService.Start()
	if started then
		return
	end
	started = true

	local candidate = OddityContainmentConfig.GetDefinition()
	validateDefinition(candidate)
	definition = candidate
	runtime = discoverRuntime(candidate)

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	stateRemote = requireChildOfClass(network, "OddityContainmentState", "RemoteEvent") :: RemoteEvent
	local runtimeRoot = getOrCreateFolder(Workspace, RUNTIME_ROOT_NAME)
	runtimeFolder = getOrCreateFolder(runtimeRoot, RUNTIME_FOLDER_NAME)
	for _, child in ipairs((runtimeFolder :: Folder):GetChildren()) do
		child:Destroy()
	end

	local activityRuntime = runtime :: ActivityRuntime
	activityRuntime.StartPrompt.Triggered:Connect(beginAttempt)
	for gateId, gate in pairs(activityRuntime.Gates) do
		local capturedGateId = gateId
		gate.Prompt.Triggered:Connect(function(player: Player)
			toggleGate(player, capturedGateId)
		end)
	end
	PlayerStateService.ObserveStateRemoved(clearPlayer)
	ModularPrototypeStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)
	transitionToAvailable()
	print("[ODDWORKS][OddityContainment] Shared eastern-yard containment prototype started.")
end

return OddityContainmentService
