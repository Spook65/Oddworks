--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][FurnacePodChase] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local ConstructCapabilityResolver = require(Services:WaitForChild("ConstructCapabilityResolver"))
local FurnacePodChaseConfig = require(Config:WaitForChild("FurnacePodChaseConfig"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local SignatureDiscoveryService = require(Services:WaitForChild("SignatureDiscoveryService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type ChaseState = "AVAILABLE" | "STOLEN" | "ACTIVATING" | "CHASE_ACTIVE" | "RESETTING" | "SECURED"
type Definition = FurnacePodChaseConfig.FurnacePodChaseDefinition
type PartPresentation = {
	Transparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
	CanTouch: boolean,
}
type ChaseRuntime = {
	TargetModel: Model,
	InteractionPart: BasePart,
	Prompt: ProximityPrompt,
	WardenSpawnMarker: BasePart,
	TargetPresentation: { [BasePart]: PartPresentation },
}
type MovementOverride = {
	Player: Player,
	Humanoid: Humanoid,
	BaselineWalkSpeed: number,
	AppliedWalkSpeed: number,
}
export type DiagnosticSnapshot = {
	Phase: string,
	IsCarrier: boolean,
	WardenStage: number?,
	SpringLegsEligible: boolean,
	SpringLegsApplicationRecord: boolean,
	SpringLegsSpeedMatchesExpected: boolean,
	SpringLegsEffectApplied: boolean,
	MovementBaselineWalkSpeed: number?,
	ExpectedSpringLegsWalkSpeed: number?,
	ConfiguredSpringLegsMultiplier: number,
}

local FurnacePodChaseService = {}

local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "FurnacePodChase"

local state: ChaseState = "AVAILABLE"
local carrier: Player? = nil
local generation = 0
local chaseStartedAt = 0
local currentStage = 0
local hasSeenExplanation: { [Player]: boolean } = {}
local pendingConfirmations: { [Player]: number } = {}
local lastAttemptTimes: { [Player]: number } = {}
local lastConfirmationTimes: { [Player]: number } = {}
local movementOverride: MovementOverride? = nil
local springLegsEligibleForAttempt = false
local activeDeathConnection: RBXScriptConnection? = nil
local carryModel: Model? = nil
local wardenModel: Model? = nil
local runtimeFolder: Folder? = nil
local runtime: ChaseRuntime? = nil
local definition: Definition? = nil
local stateRemote: RemoteEvent? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][FurnacePodChase] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][FurnacePodChase] %s.%s must be a %s, but found %s.",
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
			error(string.format("[ODDWORKS][FurnacePodChase] %s must be a Folder.", existing:GetFullName()))
		end
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = childName
	folder.Parent = parent
	return folder
end

local function isPositiveFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value > 0
end

local function validateDefinition(candidate: Definition)
	if not isPositiveFinite(candidate.MaxStealDistance)
		or #candidate.RouteModelName == 0
		or #candidate.WorkshopAreaMarkerName == 0
		or #candidate.SafeRouteMarkerName == 0
		or #candidate.ShortcutMarkerName == 0
		or #candidate.FurnaceSiteMarkerName == 0
		or not isPositiveFinite(candidate.AttemptIntervalSeconds)
		or not isPositiveFinite(candidate.ConfirmationIntervalSeconds)
		or not isPositiveFinite(candidate.ConfirmationLifetimeSeconds)
		or not isPositiveFinite(candidate.HeadStartSeconds)
		or candidate.HeadStartSeconds > 5
		or not isPositiveFinite(candidate.SpringLegsSpeedMultiplier)
		or candidate.SpringLegsSpeedMultiplier <= 1
		or candidate.SpringLegsSpeedMultiplier > 1.5
		or not isPositiveFinite(candidate.PollSeconds)
		or not isPositiveFinite(candidate.CatchRadius)
		or not isPositiveFinite(candidate.StageOneSeconds)
		or not isPositiveFinite(candidate.StageTwoSeconds)
		or candidate.StageTwoSeconds <= candidate.StageOneSeconds
		or #candidate.StageSpeeds ~= 3
		or not isPositiveFinite(candidate.StageSpeeds[1])
		or not isPositiveFinite(candidate.StageSpeeds[2])
		or not isPositiveFinite(candidate.StageSpeeds[3])
		or not isPositiveFinite(candidate.ResetSeconds)
		or not isPositiveFinite(candidate.RevealDelaySeconds)
	then
		error("[ODDWORKS][FurnacePodChase] Chase configuration is invalid.")
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

local function restoreChaseMovement(player: Player)
	local activeOverride = movementOverride
	if activeOverride and activeOverride.Player == player then
		if activeOverride.Humanoid.Parent ~= nil then
			activeOverride.Humanoid.WalkSpeed = activeOverride.BaselineWalkSpeed
		end
		movementOverride = nil
		springLegsEligibleForAttempt = false
	elseif carrier == player then
		springLegsEligibleForAttempt = false
	end
end

local function applySpringLegsMovement(player: Player, humanoid: Humanoid, candidate: Definition): boolean
	restoreChaseMovement(player)
	if not ConstructCapabilityResolver.HasSpringLegsChaseCapability(player) then
		return false
	end
	local baseline = humanoid.WalkSpeed
	if not isPositiveFinite(baseline) then
		return false
	end
	local applied = baseline * candidate.SpringLegsSpeedMultiplier
	movementOverride = {
		Player = player,
		Humanoid = humanoid,
		BaselineWalkSpeed = baseline,
		AppliedWalkSpeed = applied,
	}
	springLegsEligibleForAttempt = true
	humanoid.WalkSpeed = applied
	return math.abs(humanoid.WalkSpeed - applied) <= 0.01
end

local function verifySpringLegsMovement(player: Player, humanoid: Humanoid): boolean
	local activeOverride = movementOverride
	if not activeOverride
		or activeOverride.Player ~= player
		or activeOverride.Humanoid ~= humanoid
		or not springLegsEligibleForAttempt
		or not ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	then
		return false
	end

	if math.abs(humanoid.WalkSpeed - activeOverride.AppliedWalkSpeed) > 0.01 then
		warn(string.format(
			"[ODDWORKS][FurnacePodChase] SpringLegs WalkSpeed for %s changed from expected %.2f to %.2f during activation; restoring once at chase start.",
			player.Name,
			activeOverride.AppliedWalkSpeed,
			humanoid.WalkSpeed
		))
		humanoid.WalkSpeed = activeOverride.AppliedWalkSpeed
	end
	return math.abs(humanoid.WalkSpeed - activeOverride.AppliedWalkSpeed) <= 0.01
end

local function fireCarrier(player: Player, payload: { [string]: any })
	local remote = stateRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function setTargetAvailable(isAvailable: boolean)
	local chaseRuntime = runtime
	if not chaseRuntime then
		return
	end
	for part, presentation in pairs(chaseRuntime.TargetPresentation) do
		if part.Parent ~= nil then
			part.Transparency = if isAvailable then presentation.Transparency else 1
			part.CanCollide = if isAvailable then presentation.CanCollide else false
			part.CanQuery = if isAvailable then presentation.CanQuery else false
			part.CanTouch = if isAvailable then presentation.CanTouch else false
		end
	end
	chaseRuntime.Prompt.Enabled = isAvailable
end

local function disconnectActiveDeath()
	if activeDeathConnection then
		activeDeathConnection:Disconnect()
		activeDeathConnection = nil
	end
end

local function destroyAttemptModels()
	if carryModel then
		carryModel:Destroy()
		carryModel = nil
	end
	if wardenModel then
		wardenModel:Destroy()
		wardenModel = nil
	end
end

local function newDisplayPart(
	parent: Instance,
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
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.CFrame = rootCFrame * localCFrame
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createCarry(player: Player, characterRoot: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "CarriedFurnacePod"
	model:SetAttribute("CarrierUserId", player.UserId)

	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Anchored = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.Transparency = 1
	root.CFrame = characterRoot.CFrame * CFrame.new(0, 1.5, 1.65)
	root.Parent = model
	model.PrimaryPart = root

	local function addPart(name: string, localCFrame: CFrame, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?)
		local part = newDisplayPart(model, name, root.CFrame, localCFrame, size, color, material, shape)
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = name .. "Weld"
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
	end

	addPart("PodShell", CFrame.identity, Vector3.new(2.4, 3, 2.2), Color3.fromRGB(73, 76, 78), Enum.Material.CorrodedMetal, Enum.PartType.Ball)
	addPart("FurnaceCore", CFrame.new(0, 0, -0.95), Vector3.new(1.25, 1.6, 0.35), Color3.fromRGB(255, 116, 31), Enum.Material.Neon, nil)
	addPart("TopBand", CFrame.new(0, 1.05, 0), Vector3.new(2.5, 0.35, 2.3), Color3.fromRGB(224, 164, 56), Enum.Material.Metal, nil)
	addPart("BottomBand", CFrame.new(0, -1.05, 0), Vector3.new(2.5, 0.35, 2.3), Color3.fromRGB(224, 164, 56), Enum.Material.Metal, nil)

	local characterWeld = Instance.new("WeldConstraint")
	characterWeld.Name = "CharacterCarryWeld"
	characterWeld.Part0 = characterRoot
	characterWeld.Part1 = root
	characterWeld.Parent = root
	model.Parent = characterRoot.Parent
	return model
end

local function createWarden(spawnMarker: BasePart): Model
	local folder = assert(runtimeFolder, "Furnace Pod chase runtime folder is unavailable.")
	local model = Instance.new("Model")
	model.Name = "ScrapWarden"
	model:SetAttribute("PrototypePursuer", true)

	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CFrame = spawnMarker.CFrame
	root.Parent = model
	model.PrimaryPart = root

	newDisplayPart(model, "FurnaceBody", root.CFrame, CFrame.new(0, 2.5, 0), Vector3.new(3.8, 4.2, 2.8), Color3.fromRGB(62, 68, 70), Enum.Material.CorrodedMetal, Enum.PartType.Ball)
	newDisplayPart(model, "ChestGlow", root.CFrame, CFrame.new(0, 2.5, -1.3), Vector3.new(1.8, 2.2, 0.35), Color3.fromRGB(244, 70, 38), Enum.Material.Neon, nil)
	newDisplayPart(model, "Head", root.CFrame, CFrame.new(0, 5, 0), Vector3.new(2.5, 1.8, 2.1), Color3.fromRGB(98, 91, 79), Enum.Material.Metal, nil)
	local eye = newDisplayPart(model, "Eye", root.CFrame, CFrame.new(0, 5, -1.1), Vector3.new(1.2, 0.45, 0.25), Color3.fromRGB(255, 190, 54), Enum.Material.Neon, nil)
	local alarmBeacon = newDisplayPart(model, "AlarmBeacon", root.CFrame, CFrame.new(0, 6.25, 0), Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(244, 70, 38), Enum.Material.Neon, Enum.PartType.Ball)
	newDisplayPart(model, "LeftArm", root.CFrame, CFrame.new(-2.25, 2.7, 0), Vector3.new(0.8, 3.2, 0.9), Color3.fromRGB(80, 83, 80), Enum.Material.DiamondPlate, nil)
	newDisplayPart(model, "RightArm", root.CFrame, CFrame.new(2.25, 2.7, 0), Vector3.new(0.8, 3.2, 0.9), Color3.fromRGB(80, 83, 80), Enum.Material.DiamondPlate, nil)
	newDisplayPart(model, "LeftTread", root.CFrame, CFrame.new(-1.05, 0.55, 0), Vector3.new(1.5, 1.1, 2.3), Color3.fromRGB(38, 41, 41), Enum.Material.Metal, nil)
	newDisplayPart(model, "RightTread", root.CFrame, CFrame.new(1.05, 0.55, 0), Vector3.new(1.5, 1.1, 2.3), Color3.fromRGB(38, 41, 41), Enum.Material.Metal, nil)

	local alarmLight = Instance.new("PointLight")
	alarmLight.Name = "ActivationLight"
	alarmLight.Brightness = 0
	alarmLight.Color = Color3.fromRGB(255, 76, 43)
	alarmLight.Range = 20
	alarmLight.Parent = alarmBeacon
	eye.Transparency = 0.65
	alarmBeacon.Transparency = 0.65

	model.Parent = folder
	return model
end

local function setWardenAlarm(bright: boolean)
	local model = wardenModel
	if not model then
		return
	end
	local chest = model:FindFirstChild("ChestGlow")
	local eye = model:FindFirstChild("Eye")
	local beacon = model:FindFirstChild("AlarmBeacon")
	if chest and chest:IsA("BasePart") then
		chest.Transparency = if bright then 0 else 0.65
	end
	if eye and eye:IsA("BasePart") then
		eye.Transparency = if bright then 0 else 0.65
	end
	if beacon and beacon:IsA("BasePart") then
		beacon.Transparency = if bright then 0 else 0.65
		local light = beacon:FindFirstChild("ActivationLight")
		if light and light:IsA("PointLight") then
			light.Brightness = if bright then 4 else 0
		end
	end
end

local function runActivationTelegraph(player: Player, attemptToken: number)
	local bright = false
	while generation == attemptToken and carrier == player and state == "ACTIVATING" do
		bright = not bright
		setWardenAlarm(bright)
		task.wait(0.25)
	end
end

local function getAssignedSecureZone(player: Player, candidate: Definition): BasePart?
	local plot = WorkshopService.GetAssignedPlot(player)
	local zone = if plot then plot:FindFirstChild(candidate.SecureZoneName) else nil
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function returnToWorkshop(player: Player)
	local plot = WorkshopService.GetAssignedPlot(player)
	local character = player.Character
	if plot and character and character.Parent == Workspace then
		character:PivotTo(plot.CFrame * CFrame.new(0, 4, 0))
	end
end

local function scheduleReset(resetToken: number, candidate: Definition)
	task.delay(candidate.ResetSeconds, function()
		if generation ~= resetToken or state ~= "RESETTING" then
			return
		end
		state = "AVAILABLE"
		setTargetAvailable(true)
		print("[ODDWORKS][FurnacePodChase] Furnace Pod reset and is available again.")
	end)
end

local function failAttempt(player: Player, attemptToken: number, shouldReturnToWorkshop: boolean, notifyClient: boolean)
	if generation ~= attemptToken
		or carrier ~= player
		or (state ~= "ACTIVATING" and state ~= "CHASE_ACTIVE" and state ~= "SECURED")
	then
		return
	end

	generation += 1
	local resetToken = generation
	state = "RESETTING"
	carrier = nil
	restoreChaseMovement(player)
	disconnectActiveDeath()
	destroyAttemptModels()
	if shouldReturnToWorkshop then
		returnToWorkshop(player)
	end
	if notifyClient then
		fireCarrier(player, { Kind = "CAUGHT" })
	end
	local candidate = definition
	if candidate then
		scheduleReset(resetToken, candidate)
	end
end

local function getStage(elapsed: number, candidate: Definition): number
	if elapsed < candidate.StageOneSeconds then
		return 1
	elseif elapsed < candidate.StageTwoSeconds then
		return 2
	end
	return 3
end

local function moveWardenToward(targetPosition: Vector3, speed: number, deltaTime: number): number
	local model = wardenModel
	if not model or model.Parent == nil or not model.PrimaryPart then
		return math.huge
	end
	local pivot = model:GetPivot()
	local flatTarget = Vector3.new(targetPosition.X, pivot.Position.Y, targetPosition.Z)
	local offset = flatTarget - pivot.Position
	local distance = offset.Magnitude
	if distance > 0.001 then
		local direction = offset.Unit
		local newPosition = pivot.Position + direction * math.min(speed * deltaTime, distance)
		model:PivotTo(CFrame.lookAt(newPosition, newPosition + direction))
	end
	return distance
end

local function completeSecure(player: Player, attemptToken: number, candidate: Definition)
	if generation ~= attemptToken or carrier ~= player or state ~= "CHASE_ACTIVE" then
		return
	end

	state = "SECURED"
	restoreChaseMovement(player)
	destroyAttemptModels()
	fireCarrier(player, { Kind = "SECURED" })
	print(string.format("[ODDWORKS][FurnacePodChase] %s secured the Furnace Pod.", player.Name))

	task.delay(candidate.RevealDelaySeconds, function()
		if generation ~= attemptToken
			or state ~= "SECURED"
			or carrier ~= player
			or player.Parent ~= Players
			or not PlayerStateService.HasState(player)
			or not ModularPrototypeStateService.HasState(player)
		then
			return
		end
		local _, humanoid = getCharacterRootAndHumanoid(player)
		if not humanoid then
			failAttempt(player, attemptToken, false, false)
			return
		end

		if not SignatureDiscoveryService.RevealKilnbackFromFurnacePod(player) then
			warn(string.format("[ODDWORKS][FurnacePodChase] Kilnback reveal failed for %s; resetting attempt.", player.Name))
			failAttempt(player, attemptToken, false, true)
			return
		end

		disconnectActiveDeath()
		carrier = nil
		fireCarrier(player, { Kind = "REVEALED", SignatureId = "Kilnback" })
	end)
end

local function runChase(player: Player, attemptToken: number, candidate: Definition)
	local previousClock = os.clock()
	while generation == attemptToken and carrier == player and state == "CHASE_ACTIVE" do
		local root = getCharacterRootAndHumanoid(player)
		if not root then
			failAttempt(player, attemptToken, false, player.Parent == Players)
			return
		end

		local secureZone = getAssignedSecureZone(player, candidate)
		if secureZone and isInsideVolume(root.Position, secureZone) then
			completeSecure(player, attemptToken, candidate)
			return
		end

		local now = os.clock()
		local elapsed = now - chaseStartedAt
		local stage = getStage(elapsed, candidate)
		if stage ~= currentStage then
			currentStage = stage
			fireCarrier(player, { Kind = "STAGE", Stage = stage })
		end

		local distance = moveWardenToward(root.Position, candidate.StageSpeeds[stage], math.min(now - previousClock, 0.25))
		previousClock = now
		if distance <= candidate.CatchRadius then
			failAttempt(player, attemptToken, true, true)
			return
		end
		task.wait(candidate.PollSeconds)
	end
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

local function passesConfirmationThrottle(player: Player, candidate: Definition): boolean
	local now = os.clock()
	local lastAttempt = lastConfirmationTimes[player]
	if lastAttempt and now - lastAttempt < candidate.ConfirmationIntervalSeconds then
		return false
	end
	lastConfirmationTimes[player] = now
	return true
end

local function validateAttemptContext(
	player: Player,
	candidate: Definition,
	chaseRuntime: ChaseRuntime
): (BasePart?, Humanoid?, BasePart?)
	if player.Parent ~= Players
		or state ~= "AVAILABLE"
		or carrier ~= nil
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not WorkshopService.GetAssignedPlot(player)
		or chaseRuntime.TargetModel.Parent == nil
		or chaseRuntime.InteractionPart.Parent ~= chaseRuntime.TargetModel
		or chaseRuntime.Prompt.Parent ~= chaseRuntime.InteractionPart
	then
		return nil, nil, nil
	end

	local root, humanoid = getCharacterRootAndHumanoid(player)
	if not root or not humanoid or (root.Position - chaseRuntime.InteractionPart.Position).Magnitude > candidate.MaxStealDistance then
		return nil, nil, nil
	end
	local secureZone = getAssignedSecureZone(player, candidate)
	if not secureZone then
		return nil, nil, nil
	end
	return root, humanoid, secureZone
end

local function beginAttempt(
	player: Player,
	candidate: Definition,
	chaseRuntime: ChaseRuntime,
	root: BasePart,
	humanoid: Humanoid,
	secureZone: BasePart
)
	pendingConfirmations[player] = nil
	generation += 1
	local attemptToken = generation
	state = "STOLEN"
	carrier = player
	setTargetAvailable(false)
	destroyAttemptModels()

	carryModel = createCarry(player, root)
	wardenModel = createWarden(chaseRuntime.WardenSpawnMarker)
	local springLegsActive = applySpringLegsMovement(player, humanoid, candidate)
	activeDeathConnection = humanoid.Died:Connect(function()
		failAttempt(player, attemptToken, false, player.Parent == Players)
	end)
	state = "ACTIVATING"
	fireCarrier(player, {
		Kind = "ACTIVATING",
		HeadStartSeconds = candidate.HeadStartSeconds,
		DestinationPosition = secureZone.Position,
		SpringLegsActive = springLegsActive,
	})
	print(string.format("[ODDWORKS][FurnacePodChase] %s stole the Furnace Pod; Warden activating.", player.Name))
	task.spawn(runActivationTelegraph, player, attemptToken)
	task.delay(candidate.HeadStartSeconds, function()
		if generation ~= attemptToken or carrier ~= player or state ~= "ACTIVATING" then
			return
		end
		local activeRoot, activeHumanoid = getCharacterRootAndHumanoid(player)
		if not activeRoot
			or not activeHumanoid
			or player.Parent ~= Players
			or not PlayerStateService.HasState(player)
			or not ModularPrototypeStateService.HasState(player)
		then
			failAttempt(player, attemptToken, false, player.Parent == Players)
			return
		end
		if springLegsEligibleForAttempt then
			verifySpringLegsMovement(player, activeHumanoid)
		end
		setWardenAlarm(true)
		chaseStartedAt = os.clock()
		currentStage = 1
		state = "CHASE_ACTIVE"
		fireCarrier(player, { Kind = "CHASE_STARTED", Stage = 1 })
		print(string.format("[ODDWORKS][FurnacePodChase] Scrap Warden chase active for %s.", player.Name))
		task.spawn(runChase, player, attemptToken, candidate)
	end)
end

local function handlePromptTriggered(player: Player)
	local candidate = definition
	local chaseRuntime = runtime
	if not candidate or not chaseRuntime or not passesAttemptThrottle(player, candidate) then
		return
	end
	local root, humanoid, secureZone = validateAttemptContext(player, candidate, chaseRuntime)
	if not root or not humanoid or not secureZone then
		return
	end

	if not hasSeenExplanation[player] then
		pendingConfirmations[player] = os.clock() + candidate.ConfirmationLifetimeSeconds
		fireCarrier(player, { Kind = "EXPLANATION" })
		return
	end
	beginAttempt(player, candidate, chaseRuntime, root, humanoid, secureZone)
end

local function handleConfirmation(player: Player, intent: any, ...: any)
	local candidate = definition
	local chaseRuntime = runtime
	if select("#", ...) ~= 0
		or player.Parent ~= Players
		or typeof(intent) ~= "string"
		or (intent ~= "STEAL" and intent ~= "NOT_YET")
		or not candidate
		or not chaseRuntime
		or not passesConfirmationThrottle(player, candidate)
	then
		return
	end
	local expiresAt = pendingConfirmations[player]
	if not expiresAt or os.clock() > expiresAt then
		pendingConfirmations[player] = nil
		return
	end
	if intent == "NOT_YET" then
		pendingConfirmations[player] = nil
		return
	end
	local root, humanoid, secureZone = validateAttemptContext(player, candidate, chaseRuntime)
	if not root or not humanoid or not secureZone then
		return
	end

	pendingConfirmations[player] = nil
	hasSeenExplanation[player] = true
	beginAttempt(player, candidate, chaseRuntime, root, humanoid, secureZone)
end

local function clearPlayer(player: Player)
	hasSeenExplanation[player] = nil
	pendingConfirmations[player] = nil
	lastAttemptTimes[player] = nil
	lastConfirmationTimes[player] = nil
	if carrier == player then
		local shouldNotifyClient = player.Parent == Players
		failAttempt(player, generation, false, false)
		if shouldNotifyClient then
			fireCarrier(player, { Kind = "CANCELLED" })
		end
	else
		restoreChaseMovement(player)
	end
end

local function handleModularStateChanged(player: Player)
	if carrier ~= player
		or not springLegsEligibleForAttempt
		or (state ~= "ACTIVATING" and state ~= "CHASE_ACTIVE")
		or ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	then
		return
	end
	restoreChaseMovement(player)
end

local function createLandmarkLabel(
	part: BasePart,
	name: string,
	text: string,
	color: Color3,
	maxDistance: number,
	size: Vector2
)
	local previous = part:FindFirstChild(name)
	if previous then
		previous:Destroy()
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Adornee = part
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = maxDistance
	billboard.Size = UDim2.fromOffset(size.X, size.Y)
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(25, 28, 29)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 15
	label.TextWrapped = true
	label.Parent = billboard
end

local function addSignFace(sign: BasePart, face: Enum.NormalId, text: string)
	local surface = Instance.new("SurfaceGui")
	surface.Name = face.Name .. "Face"
	surface.Face = face
	surface.LightInfluence = 0.2
	surface.PixelsPerStud = 40
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Color3.fromRGB(245, 247, 237)
	label.TextScaled = true
	label.Parent = surface
end

local function createRouteSign(routeModel: Model, marker: BasePart, name: string, text: string, color: Color3)
	local previous = routeModel:FindFirstChild(name)
	if previous then
		previous:Destroy()
	end

	local sign = Instance.new("Part")
	sign.Name = name
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	sign.Size = Vector3.new(8, 3, 0.35)
	sign.Position = Vector3.new(marker.Position.X, 2.5, marker.Position.Z)
	sign.Color = color
	sign.Material = Enum.Material.Metal
	sign.TopSurface = Enum.SurfaceType.Smooth
	sign.BottomSurface = Enum.SurfaceType.Smooth
	sign.Parent = routeModel
	addSignFace(sign, Enum.NormalId.Front, text)
	addSignFace(sign, Enum.NormalId.Back, text)
end

local function discoverRuntime(candidate: Definition): ChaseRuntime
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local routeModel = requireChildOfClass(world, candidate.RouteModelName, "Model") :: Model
	local workshopMarker = requireChildOfClass(routeModel, candidate.WorkshopAreaMarkerName, "BasePart") :: BasePart
	local safeRouteMarker = requireChildOfClass(routeModel, candidate.SafeRouteMarkerName, "BasePart") :: BasePart
	local shortcutMarker = requireChildOfClass(routeModel, candidate.ShortcutMarkerName, "BasePart") :: BasePart
	local furnaceSiteMarker = requireChildOfClass(routeModel, candidate.FurnaceSiteMarkerName, "BasePart") :: BasePart
	local retiredSafeLabel = safeRouteMarker:FindFirstChild("SafeRouteLabel")
	if retiredSafeLabel then
		retiredSafeLabel:Destroy()
	end
	local retiredShortcutLabel = shortcutMarker:FindFirstChild("ShortcutLabel")
	if retiredShortcutLabel then
		retiredShortcutLabel:Destroy()
	end
	createLandmarkLabel(
		workshopMarker,
		"WorkshopAreaLabel",
		"WORKSHOPS",
		Color3.fromRGB(92, 238, 157),
		85,
		Vector2.new(140, 36)
	)
	createRouteSign(routeModel, safeRouteMarker, "LongOpenRouteSign", "GREEN\nLONG / OPEN", Color3.fromRGB(46, 126, 84))
	createRouteSign(
		routeModel,
		shortcutMarker,
		"ShortTechnicalRouteSign",
		"ORANGE\nSHORT / TECHNICAL",
		Color3.fromRGB(176, 89, 35)
	)
	createLandmarkLabel(
		furnaceSiteMarker,
		"FurnaceSiteLabel",
		"FURNACE SITE",
		Color3.fromRGB(255, 132, 76),
		120,
		Vector2.new(150, 38)
	)
	local targetModel = requireChildOfClass(world, candidate.WorldModelName, "Model") :: Model
	local interactionPart = requireChildOfClass(targetModel, candidate.InteractionPartName, "BasePart") :: BasePart
	local prompt = requireChildOfClass(interactionPart, "Prompt", "ProximityPrompt") :: ProximityPrompt
	local wardenSpawnMarker = requireChildOfClass(targetModel, candidate.WardenSpawnMarkerName, "BasePart") :: BasePart
	local presentation: { [BasePart]: PartPresentation } = {}
	for _, descendant in ipairs(targetModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= wardenSpawnMarker then
			presentation[descendant] = {
				Transparency = descendant.Transparency,
				CanCollide = descendant.CanCollide,
				CanQuery = descendant.CanQuery,
				CanTouch = descendant.CanTouch,
			}
		end
	end
	return {
		TargetModel = targetModel,
		InteractionPart = interactionPart,
		Prompt = prompt,
		WardenSpawnMarker = wardenSpawnMarker,
		TargetPresentation = presentation,
	}
end

-- Returns a narrow read-only view for the Studio-only inspector. Runtime models,
-- private chase tables, and mutation functions remain inside this service.
function FurnacePodChaseService.GetDiagnosticSnapshot(player: Player): DiagnosticSnapshot
	local candidate = definition or FurnacePodChaseConfig.GetDefinition()
	local isCarrier = carrier == player
	local activePhase = state == "ACTIVATING" or state == "CHASE_ACTIVE"
	local activeMovement = movementOverride
	local playerMovement = if activeMovement and activeMovement.Player == player then activeMovement else nil
	local _, humanoid = getCharacterRootAndHumanoid(player)
	local applicationRecord = playerMovement ~= nil
	local speedMatchesExpected = playerMovement ~= nil
		and humanoid == playerMovement.Humanoid
		and math.abs((humanoid :: Humanoid).WalkSpeed - playerMovement.AppliedWalkSpeed) <= 0.01

	local phase = state :: string
	if state == "SECURED" and carrier == nil then
		phase = "REVEAL"
	end

	return {
		Phase = phase,
		IsCarrier = isCarrier,
		WardenStage = if state == "CHASE_ACTIVE" then currentStage else nil,
		SpringLegsEligible = isCarrier
			and activePhase
			and ConstructCapabilityResolver.HasSpringLegsChaseCapability(player),
		SpringLegsApplicationRecord = applicationRecord,
		SpringLegsSpeedMatchesExpected = speedMatchesExpected,
		SpringLegsEffectApplied = applicationRecord and speedMatchesExpected,
		MovementBaselineWalkSpeed = if playerMovement then playerMovement.BaselineWalkSpeed else nil,
		ExpectedSpringLegsWalkSpeed = if playerMovement then playerMovement.AppliedWalkSpeed else nil,
		ConfiguredSpringLegsMultiplier = candidate.SpringLegsSpeedMultiplier,
	}
end

function FurnacePodChaseService.Start()
	if started then
		return
	end
	started = true

	local candidate = FurnacePodChaseConfig.GetDefinition()
	validateDefinition(candidate)
	definition = candidate
	runtime = discoverRuntime(candidate)

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	stateRemote = requireChildOfClass(network, "FurnacePodChaseState", "RemoteEvent") :: RemoteEvent
	local confirmRemote = requireChildOfClass(network, "FurnacePodStealConfirm", "RemoteEvent") :: RemoteEvent
	confirmRemote.OnServerEvent:Connect(handleConfirmation)
	local runtimeRoot = getOrCreateFolder(Workspace, RUNTIME_ROOT_NAME)
	runtimeFolder = getOrCreateFolder(runtimeRoot, RUNTIME_FOLDER_NAME)
	for _, child in ipairs((runtimeFolder :: Folder):GetChildren()) do
		child:Destroy()
	end

	setTargetAvailable(true)
	local chaseRuntime = runtime :: ChaseRuntime
	chaseRuntime.Prompt.Triggered:Connect(handlePromptTriggered)
	ModularPrototypeStateService.ObserveStateChanged(handleModularStateChanged)
	ModularPrototypeStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)
	print("[ODDWORKS][FurnacePodChase] Shared Furnace Pod chase prototype started.")
end

return FurnacePodChaseService
