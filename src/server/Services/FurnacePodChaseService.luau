--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][FurnacePodChase] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local ConstructCapabilityResolver = require(Services:WaitForChild("ConstructCapabilityResolver"))
local FurnacePodChaseConfig = require(Config:WaitForChild("FurnacePodChaseConfig"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local OddlingDisplayService = require(Services:WaitForChild("OddlingDisplayService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local RecoveryCarrierRegistry = require(Services:WaitForChild("RecoveryCarrierRegistry"))
local SignatureDiscoveryService = require(Services:WaitForChild("SignatureDiscoveryService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type ChaseState = "AVAILABLE" | "STOLEN" | "ACTIVATING" | "CHASE_ACTIVE" | "DROPPED_CONTESTED" | "RECLAIMING" | "RESETTING" | "SECURED"
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
	AvailabilityLabel: TextLabel,
}
type MovementOverride = {
	Player: Player,
	Humanoid: Humanoid,
	BaselineWalkSpeed: number,
	ChaseMultiplier: number,
	PulseMultiplier: number,
	ChaseWalkSpeed: number,
	AppliedWalkSpeed: number,
}
type ScrapPulseState = {
	AttackId: number,
	TargetPosition: Vector3,
	ResolveAt: number,
	ForecastEligible: boolean,
	ForecastSent: boolean,
	TelegraphModel: Model?,
}
export type DiagnosticSnapshot = {
	Phase: string,
	AttemptGeneration: number,
	IsCarrier: boolean,
	WardenStage: number?,
	CarryRuntimePresent: boolean,
	WardenRuntimePresent: boolean,
	SpringLegsEligible: boolean,
	SpringLegsApplicationRecord: boolean,
	SpringLegsSpeedMatchesExpected: boolean,
	SpringLegsEffectApplied: boolean,
	MovementBaselineWalkSpeed: number?,
	ExpectedSpringLegsWalkSpeed: number?,
	ConfiguredSpringLegsMultiplier: number,
	ExpectedCurrentWalkSpeed: number?,
	PossessionId: number,
	CarrierUserId: number?,
	DroppedPosition: Vector3?,
	DroppedInteractionPosition: Vector3?,
	ClaimOpenRemaining: number,
	DropTimeoutRemaining: number,
	WardenDistanceToDroppedPod: number?,
	WardenReclaimRadius: number,
	WardenReclaimEligible: boolean,
	LastDisruptorUserId: number?,
	DisruptCooldownRemaining: number,
	PostClaimProtectionRemaining: number,
	DisruptPromptPresent: boolean,
	DisruptPromptInteractionId: number?,
	DisruptPromptGeneration: number?,
	DisruptPromptPossessionId: number?,
	DisruptPromptParent: string?,
	ServoArmInstalled: boolean,
	SecureGripCapability: boolean,
	SecureGripAvailable: boolean,
	SecureGripConsumed: boolean,
	SecureGripCapabilityGeneration: number?,
	SecureGripCapabilityPossessionId: number?,
	SignalScannerInstalled: boolean,
	PulseForecastCapability: boolean,
	ConfiguredScrapPulseForecastSeconds: number,
	ScrapPulseForecastSent: boolean,
	ScrapPulseReady: boolean,
	ScrapPulseAttackId: number,
	ScrapPulseTelegraphActive: boolean,
	ScrapPulseTargetPosition: Vector3?,
	ScrapPulseDebuffActive: boolean,
	ScrapPulseDebuffMultiplier: number,
	ScrapPulseDebuffRemaining: number,
	CooldownRemaining: number,
}

local FurnacePodChaseService = {}

local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "FurnacePodChase"
local RECOVERY_ACTIVITY_ID = "FURNACE_POD"
local CARRY_BASE_CFRAME = CFrame.new(0, 0.4, -1.85) * CFrame.Angles(math.rad(-6), 0, math.rad(3))

local state: ChaseState = "AVAILABLE"
local carrier: Player? = nil
local generation = 0
local possessionId = 0
local chaseStartedAt = 0
local currentStage = 0
local hasSeenExplanation: { [Player]: boolean } = {}
local pendingConfirmations: { [Player]: number } = {}
local lastAttemptTimes: { [Player]: number } = {}
local lastConfirmationTimes: { [Player]: number } = {}
local lastDisruptTimes: { [Player]: number } = {}
local movementOverride: MovementOverride? = nil
local springLegsEligibleForAttempt = false
local secureGripEligibleForPossession = false
local secureGripAvailable = false
local secureGripCapabilityGeneration = 0
local secureGripCapabilityPossessionId = 0
local servoBraceEffect: Model? = nil
local nextScrapPulseAt = 0
local nextScrapPulseId = 0
local activeScrapPulse: ScrapPulseState? = nil
local pulseDebuffAttackId: number? = nil
local pulseDebuffExpiresAt = 0
local activeDeathConnection: RBXScriptConnection? = nil
local carryModel: Model? = nil
local droppedModel: Model? = nil
local droppedPosition: Vector3? = nil
local claimOpenAt = 0
local dropTimeoutAt = 0
local lastDisruptorUserId: number? = nil
local postClaimProtectionEndsAt = 0
local wardenModel: Model? = nil
local wardenCFrame: CFrame? = nil
local runtimeFolder: Folder? = nil
local runtime: ChaseRuntime? = nil
local definition: Definition? = nil
local stateRemote: RemoteEvent? = nil
local cooldownEndsAt = 0
local started = false
local disruptPromptHandler: ((Player, number, number) -> ())? = nil
local claimPromptHandler: ((Player, number, number) -> ())? = nil
local nextDisruptInteractionId = 0

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
		or not isPositiveFinite(candidate.ScrapPulseForecastSeconds)
		or candidate.ScrapPulseForecastSeconds > 0.75
		or not isPositiveFinite(candidate.ScrapPulseTelegraphSeconds)
		or candidate.ScrapPulseTelegraphSeconds < 0.8
		or candidate.ScrapPulseTelegraphSeconds > 1.1
		or not isPositiveFinite(candidate.ScrapPulseCooldownSeconds)
		or candidate.ScrapPulseCooldownSeconds < 4
		or candidate.ScrapPulseCooldownSeconds > 6
		or not isPositiveFinite(candidate.ScrapPulseRadius)
		or not isPositiveFinite(candidate.ScrapPulsePredictionDistance)
		or not isPositiveFinite(candidate.ScrapPulseSlowMultiplier)
		or candidate.ScrapPulseSlowMultiplier >= 1
		or not isPositiveFinite(candidate.ScrapPulseSlowSeconds)
		or not isPositiveFinite(candidate.DisruptRange)
		or candidate.DisruptRange > 12
		or not isPositiveFinite(candidate.DisruptCooldownSeconds)
		or not isPositiveFinite(candidate.ClaimGraceSeconds)
		or candidate.ClaimGraceSeconds > 1
		or not isPositiveFinite(candidate.ClaimRange)
		or candidate.ClaimRange > 12
		or not isPositiveFinite(candidate.ClaimAnchorHeight)
		or candidate.ClaimAnchorHeight > 5
		or not isPositiveFinite(candidate.DropPlacementDistance)
		or candidate.DropPlacementDistance < candidate.DisruptRange * 0.5
		or candidate.DropPlacementDistance > candidate.DisruptRange
		or not isPositiveFinite(candidate.WardenReclaimRadius)
		or candidate.WardenReclaimRadius > candidate.ClaimRange
		or candidate.WardenReclaimRadius > 8
		or not isPositiveFinite(candidate.ReclaimHeadStartSeconds)
		or candidate.ReclaimHeadStartSeconds > 2
		or not isPositiveFinite(candidate.PostClaimProtectionSeconds)
		or candidate.PostClaimProtectionSeconds < candidate.ReclaimHeadStartSeconds
		or not isPositiveFinite(candidate.ReclaimPulseDelaySeconds)
		or candidate.ReclaimPulseDelaySeconds < 2
		or not isPositiveFinite(candidate.DroppedTimeoutSeconds)
		or candidate.DroppedTimeoutSeconds < 3
		or not isPositiveFinite(candidate.ResetSeconds)
		or not isPositiveFinite(candidate.SuccessCooldownSeconds)
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
		pulseDebuffAttackId = nil
		pulseDebuffExpiresAt = 0
	elseif carrier == player then
		springLegsEligibleForAttempt = false
		pulseDebuffAttackId = nil
		pulseDebuffExpiresAt = 0
	end
end

local function applyDerivedMovement(activeOverride: MovementOverride): boolean
	local expected = activeOverride.BaselineWalkSpeed
		* activeOverride.ChaseMultiplier
		* activeOverride.PulseMultiplier
	activeOverride.ChaseWalkSpeed = activeOverride.BaselineWalkSpeed * activeOverride.ChaseMultiplier
	activeOverride.AppliedWalkSpeed = expected
	activeOverride.Humanoid.WalkSpeed = expected
	return math.abs(activeOverride.Humanoid.WalkSpeed - expected) <= 0.01
end

local function applyChaseMovement(player: Player, humanoid: Humanoid, candidate: Definition): boolean
	restoreChaseMovement(player)
	local baseline = humanoid.WalkSpeed
	if not isPositiveFinite(baseline) then
		return false
	end
	local hasSpringLegs = ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	local chaseMultiplier = if hasSpringLegs then candidate.SpringLegsSpeedMultiplier else 1
	movementOverride = {
		Player = player,
		Humanoid = humanoid,
		BaselineWalkSpeed = baseline,
		ChaseMultiplier = chaseMultiplier,
		PulseMultiplier = 1,
		ChaseWalkSpeed = baseline * chaseMultiplier,
		AppliedWalkSpeed = baseline * chaseMultiplier,
	}
	springLegsEligibleForAttempt = hasSpringLegs
	local applied = applyDerivedMovement(movementOverride :: MovementOverride)
	return hasSpringLegs and applied
end

local function verifyChaseMovement(player: Player, humanoid: Humanoid): boolean
	local activeOverride = movementOverride
	if not activeOverride
		or activeOverride.Player ~= player
		or activeOverride.Humanoid ~= humanoid
	then
		return false
	end

	if math.abs(humanoid.WalkSpeed - activeOverride.AppliedWalkSpeed) > 0.01 then
		warn(string.format(
			"[ODDWORKS][FurnacePodChase] Derived WalkSpeed for %s changed from expected %.2f to %.2f during activation; restoring once at chase start.",
			player.Name,
			activeOverride.AppliedWalkSpeed,
			humanoid.WalkSpeed
		))
		applyDerivedMovement(activeOverride)
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
	for _, descendant in ipairs(chaseRuntime.TargetModel:GetDescendants()) do
		if descendant:IsA("Light") or descendant:IsA("Highlight") then
			descendant.Enabled = isAvailable
		end
	end
	chaseRuntime.Prompt.Enabled = isAvailable
end

local function startTargetPulse(targetModel: Model)
	for _, lightName in ipairs({ "CoreLight", "WarningLight" }) do
		local light = targetModel:FindFirstChild(lightName, true)
		if light and light:IsA("PointLight") then
			local brightness = if lightName == "CoreLight" then 4.8 else 3.4
			TweenService:Create(
				light,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Brightness = brightness }
			):Play()
		end
	end
end

local function setAvailabilityText(status: string)
	local chaseRuntime = runtime
	if chaseRuntime then
		chaseRuntime.AvailabilityLabel.Text = string.format("FURNACE POD\nHIGH SECURITY - %s", status)
	end
end

local function disconnectActiveDeath()
	if activeDeathConnection then
		activeDeathConnection:Disconnect()
		activeDeathConnection = nil
	end
end

local function destroyScrapPulseTelegraph()
	local pulse = activeScrapPulse
	activeScrapPulse = nil
	local telegraphModel = if pulse then pulse.TelegraphModel else nil
	if telegraphModel and telegraphModel.Parent ~= nil then
		telegraphModel:Destroy()
	end
end

local function destroyCarryModel()
	if carryModel then
		carryModel:Destroy()
		carryModel = nil
	end
end

local function destroyDroppedModel()
	if droppedModel then
		droppedModel:Destroy()
		droppedModel = nil
	end
end

local function clearPossessionCapabilitySnapshot()
	secureGripEligibleForPossession = false
	secureGripAvailable = false
	secureGripCapabilityGeneration = 0
	secureGripCapabilityPossessionId = 0
	if servoBraceEffect then
		servoBraceEffect:Destroy()
		servoBraceEffect = nil
	end
end

local function capturePossessionCapabilities(player: Player, attemptToken: number, possessionToken: number)
	secureGripEligibleForPossession = ConstructCapabilityResolver.HasSecureGripCapability(player)
	secureGripAvailable = secureGripEligibleForPossession
	secureGripCapabilityGeneration = attemptToken
	secureGripCapabilityPossessionId = possessionToken
end

local function destroyAttemptModels()
	destroyScrapPulseTelegraph()
	nextScrapPulseAt = 0
	clearPossessionCapabilitySnapshot()
	destroyCarryModel()
	destroyDroppedModel()
	droppedPosition = nil
	claimOpenAt = 0
	dropTimeoutAt = 0
	postClaimProtectionEndsAt = 0
	lastDisruptorUserId = nil
	if wardenModel then
		wardenModel:Destroy()
		wardenModel = nil
	end
	wardenCFrame = nil
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

local function destroyDisruptPrompts(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "DisruptPrompt" then
			descendant:Destroy()
		end
	end
end

local function createDisruptPrompt(
	model: Model,
	anchor: BasePart,
	player: Player,
	attemptToken: number,
	possessionToken: number,
	candidate: Definition
): ProximityPrompt
	-- The prompt is a possession-scoped projection. Replacing it gives nearby
	-- clients a fresh ProximityPrompt lifetime instead of re-enabling stale focus.
	destroyDisruptPrompts(model)
	nextDisruptInteractionId += 1
	local interactionId = nextDisruptInteractionId

	local disruptPrompt = Instance.new("ProximityPrompt")
	disruptPrompt.Name = "DisruptPrompt"
	disruptPrompt.ActionText = "DISRUPT"
	disruptPrompt.ObjectText = "FURNACE POD CARRIER"
	disruptPrompt.HoldDuration = 0.2
	disruptPrompt.MaxActivationDistance = candidate.DisruptRange
	disruptPrompt.RequiresLineOfSight = true
	disruptPrompt.ClickablePrompt = true
	disruptPrompt.KeyboardKeyCode = Enum.KeyCode.E
	disruptPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	disruptPrompt.Enabled = true
	disruptPrompt:SetAttribute("ODDWORKSPromptKind", "FurnaceDisrupt")
	disruptPrompt:SetAttribute("CarrierUserId", player.UserId)
	disruptPrompt:SetAttribute("RecoveryGeneration", attemptToken)
	disruptPrompt:SetAttribute("PossessionId", possessionToken)
	disruptPrompt:SetAttribute("InteractionId", interactionId)
	disruptPrompt.Triggered:Connect(function(attacker: Player)
		if RunService:IsStudio() then
			print(string.format(
				"[ODDWORKS][FurnaceDisruptPrompt] Triggered interaction=%d generation=%d possession=%d attacker=%s",
				interactionId,
				attemptToken,
				possessionToken,
				attacker.Name
			))
		end
		local handler = disruptPromptHandler
		if handler then
			handler(attacker, attemptToken, possessionToken)
		end
	end)
	disruptPrompt.Parent = anchor
	return disruptPrompt
end

local function createCarry(
	player: Player,
	characterRoot: BasePart,
	attemptToken: number,
	possessionToken: number,
	candidate: Definition,
	disruptEnabled: boolean
): Model
	local model = Instance.new("Model")
	model.Name = "CarriedFurnacePod"
	model:SetAttribute("CarrierUserId", player.UserId)
	model:SetAttribute("RecoveryGeneration", attemptToken)
	model:SetAttribute("PossessionId", possessionToken)

	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Anchored = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.Transparency = 1
	root.CFrame = characterRoot.CFrame * CARRY_BASE_CFRAME
	root.Parent = model
	model.PrimaryPart = root

	local function addPart(name: string, localCFrame: CFrame, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local part = newDisplayPart(model, name, root.CFrame, localCFrame, size, color, material, shape)
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = name .. "Weld"
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
		return part
	end

	addPart("PodShell", CFrame.identity, Vector3.new(2.8, 3.4, 2.6), Color3.fromRGB(73, 76, 78), Enum.Material.CorrodedMetal, Enum.PartType.Ball)
	local core = addPart("FurnaceCore", CFrame.new(0, 0, -1.15), Vector3.new(1.5, 1.95, 0.4), Color3.fromRGB(255, 116, 31), Enum.Material.Neon, nil)
	addPart("TopBand", CFrame.new(0, 1.2, 0), Vector3.new(2.9, 0.4, 2.7), Color3.fromRGB(224, 164, 56), Enum.Material.Metal, nil)
	addPart("BottomBand", CFrame.new(0, -1.2, 0), Vector3.new(2.9, 0.4, 2.7), Color3.fromRGB(224, 164, 56), Enum.Material.Metal, nil)
	addPart("LeftGrip", CFrame.new(-1.5, 0, 0), Vector3.new(0.28, 2.15, 0.42), Color3.fromRGB(194, 143, 53), Enum.Material.Metal, nil)
	addPart("RightGrip", CFrame.new(1.5, 0, 0), Vector3.new(0.28, 2.15, 0.42), Color3.fromRGB(194, 143, 53), Enum.Material.Metal, nil)

	local carryLight = Instance.new("PointLight")
	carryLight.Name = "CarryLight"
	carryLight.Color = Color3.fromRGB(255, 105, 28)
	carryLight.Brightness = 3.2
	carryLight.Range = 14
	carryLight.Shadows = false
	carryLight.Parent = core
	local highlight = Instance.new("Highlight")
	highlight.Name = "CarryOutline"
	highlight.FillColor = Color3.fromRGB(255, 105, 28)
	highlight.FillTransparency = 0.93
	highlight.OutlineColor = Color3.fromRGB(255, 177, 66)
	highlight.OutlineTransparency = 0.18
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local disruptAnchor = addPart(
		"DisruptAnchor",
		CFrame.new(0, 1.8, 0),
		Vector3.new(0.4, 0.4, 0.4),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.SmoothPlastic,
		nil
	)
	disruptAnchor.Transparency = 1
	disruptAnchor:SetAttribute("RecoveryGeneration", attemptToken)
	disruptAnchor:SetAttribute("PossessionId", possessionToken)
	disruptAnchor:SetAttribute("CarrierUserId", player.UserId)
	if disruptEnabled then
		createDisruptPrompt(model, disruptAnchor, player, attemptToken, possessionToken, candidate)
	end

	local characterWeld = Instance.new("Weld")
	characterWeld.Name = "CharacterCarryWeld"
	characterWeld.Part0 = characterRoot
	characterWeld.Part1 = root
	characterWeld.C0 = CARRY_BASE_CFRAME
	characterWeld.C1 = CFrame.identity
	characterWeld.Parent = root
	model.Parent = characterRoot.Parent
	return model
end

local function createDroppedPod(
	position: Vector3,
	attemptToken: number,
	droppedPossessionToken: number,
	candidate: Definition
): Model
	local folder = assert(runtimeFolder, "Furnace Pod chase runtime folder is unavailable.")
	local model = Instance.new("Model")
	model.Name = "DroppedContestedFurnacePod"
	model:SetAttribute("RecoveryGeneration", attemptToken)
	model:SetAttribute("DroppedFromPossessionId", droppedPossessionToken)
	model:SetAttribute("Contested", true)

	local rootCFrame = CFrame.new(position)
	local shell = newDisplayPart(
		model,
		"PodShell",
		rootCFrame,
		CFrame.identity,
		Vector3.new(2.8, 3.4, 2.6),
		Color3.fromRGB(73, 76, 78),
		Enum.Material.CorrodedMetal,
		Enum.PartType.Ball
	)
	model.PrimaryPart = shell
	local core = newDisplayPart(
		model,
		"ContestedCore",
		rootCFrame,
		CFrame.new(0, 0, -1.15),
		Vector3.new(1.5, 1.95, 0.4),
		Color3.fromRGB(255, 104, 31),
		Enum.Material.Neon,
		nil
	)
	newDisplayPart(model, "TopBand", rootCFrame, CFrame.new(0, 1.2, 0), Vector3.new(2.9, 0.4, 2.7), Color3.fromRGB(224, 164, 56), Enum.Material.Metal, nil)
	newDisplayPart(model, "BottomBand", rootCFrame, CFrame.new(0, -1.2, 0), Vector3.new(2.9, 0.4, 2.7), Color3.fromRGB(224, 164, 56), Enum.Material.Metal, nil)
	local claimRing = newDisplayPart(
		model,
		"ClaimRing",
		rootCFrame,
		CFrame.new(0, -1.65, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(0.12, candidate.ClaimRange * 1.15, candidate.ClaimRange * 1.15),
		Color3.fromRGB(255, 132, 38),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	claimRing.Transparency = 0.58

	local light = Instance.new("PointLight")
	light.Name = "ContestedLight"
	light.Color = Color3.fromRGB(255, 105, 28)
	light.Brightness = 2.5
	light.Range = 16
	light.Shadows = false
	light.Parent = core
	TweenService:Create(
		light,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Brightness = 5 }
	):Play()

	local label = Instance.new("BillboardGui")
	label.Name = "ContestedLabel"
	label.Adornee = core
	label.AlwaysOnTop = false
	label.MaxDistance = 70
	label.Size = UDim2.fromOffset(180, 38)
	label.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	label.Parent = core
	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.fromScale(1, 1)
	labelText.BackgroundColor3 = Color3.fromRGB(52, 31, 22)
	labelText.BackgroundTransparency = 0.18
	labelText.BorderSizePixel = 0
	labelText.Font = Enum.Font.GothamBold
	labelText.Text = "CONTESTED / UNCLAIMED"
	labelText.TextColor3 = Color3.fromRGB(255, 188, 79)
	labelText.TextSize = 14
	labelText.Parent = label

	local claimPrompt = Instance.new("ProximityPrompt")
	claimPrompt.Name = "ClaimPrompt"
	claimPrompt.ActionText = "CLAIM POD"
	claimPrompt.ObjectText = "CONTESTED FURNACE POD"
	claimPrompt.HoldDuration = 0
	claimPrompt.MaxActivationDistance = candidate.ClaimRange
	claimPrompt.RequiresLineOfSight = false
	claimPrompt.ClickablePrompt = true
	claimPrompt.KeyboardKeyCode = Enum.KeyCode.E
	claimPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	claimPrompt.Enabled = false
	claimPrompt:SetAttribute("ODDWORKSPromptKind", "FurnaceClaim")
	claimPrompt.Triggered:Connect(function(claimant: Player)
		local handler = claimPromptHandler
		if handler then
			handler(claimant, attemptToken, droppedPossessionToken)
		end
	end)
	local claimAnchor = newDisplayPart(
		model,
		"ClaimAnchor",
		rootCFrame,
		CFrame.new(0, candidate.ClaimAnchorHeight, 0),
		Vector3.new(0.4, 0.4, 0.4),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.SmoothPlastic,
		nil
	)
	claimAnchor.Transparency = 1
	claimPrompt.Parent = claimAnchor

	model.Parent = folder
	return model
end

local function updateCarryMotion(player: Player, now: number)
	local model = carryModel
	local character = player.Character
	local characterRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local root = if model then model:FindFirstChild("RootPart") else nil
	local joint = if root then root:FindFirstChild("CharacterCarryWeld") else nil
	if not characterRoot
		or not characterRoot:IsA("BasePart")
		or not joint
		or not joint:IsA("Weld")
	then
		return
	end
	local velocity = characterRoot.AssemblyLinearVelocity
	local movementScale = math.clamp(Vector3.new(velocity.X, 0, velocity.Z).Magnitude / 16, 0, 1.25)
	local bob = math.sin(now * 4.6) * 0.075 * movementScale
	local roll = math.sin(now * 2.7) * math.rad(3.2) * movementScale
	joint.C0 = CARRY_BASE_CFRAME * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, roll)
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
	local pulseEmitter = newDisplayPart(model, "PulseEmitter", root.CFrame, CFrame.new(2.65, 3.15, -0.2), Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(255, 112, 38), Enum.Material.Neon, Enum.PartType.Ball)
	local wakePulse = newDisplayPart(model, "WakePulse", root.CFrame, CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.15, 6.2, 6.2), Color3.fromRGB(255, 76, 43), Enum.Material.Neon, Enum.PartType.Cylinder)
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
	local pulseLight = Instance.new("PointLight")
	pulseLight.Name = "PulseWindupLight"
	pulseLight.Brightness = 0
	pulseLight.Color = Color3.fromRGB(255, 104, 36)
	pulseLight.Range = 16
	pulseLight.Parent = pulseEmitter
	eye.Transparency = 0.65
	alarmBeacon.Transparency = 0.65
	pulseEmitter.Transparency = 0.78
	wakePulse.Transparency = 1

	model.Parent = folder
	return model
end

local function isCarryRuntimePresent(player: Player): boolean
	local model = carryModel
	local character = player.Character
	if not model or not character or model.Parent ~= character then
		return false
	end
	local root = model:FindFirstChild("RootPart")
	local weld = if root then root:FindFirstChild("CharacterCarryWeld") else nil
	return root ~= nil
		and root:IsA("BasePart")
		and model.PrimaryPart == root
		and weld ~= nil
		and weld:IsA("Weld")
		and weld.Part0 ~= nil
		and weld.Part0:IsDescendantOf(character)
		and weld.Part1 == root
end

local function isWardenRuntimePresent(): boolean
	local model = wardenModel
	local folder = runtimeFolder
	return model ~= nil
		and folder ~= nil
		and model.Parent == folder
		and model.PrimaryPart ~= nil
		and model.PrimaryPart:IsDescendantOf(model)
end

local function activateCurrentDisruptInteraction(
	player: Player,
	attemptToken: number,
	possessionToken: number,
	candidate: Definition
)
	local model = carryModel
	if not model
		or model:GetAttribute("RecoveryGeneration") ~= attemptToken
		or model:GetAttribute("PossessionId") ~= possessionToken
		or generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or state ~= "CHASE_ACTIVE"
		or os.clock() < postClaimProtectionEndsAt
	then
		return
	end
	local anchor = model:FindFirstChild("DisruptAnchor", true)
	if anchor and anchor:IsA("BasePart")
		and anchor:GetAttribute("RecoveryGeneration") == attemptToken
		and anchor:GetAttribute("PossessionId") == possessionToken
	then
		createDisruptPrompt(model, anchor, player, attemptToken, possessionToken, candidate)
	end
end

local function setDroppedClaimEnabled(enabled: boolean)
	local model = droppedModel
	local prompt = if model then model:FindFirstChild("ClaimPrompt", true) else nil
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
end

-- Carry and Warden models are disposable projections of an active server
-- attempt. If either whole model disappears, rebuild it without touching chase
-- ownership, rewards, or the attempt generation.
local function ensureAttemptModels(
	player: Player,
	characterRoot: BasePart,
	chaseRuntime: ChaseRuntime,
	candidate: Definition,
	attemptToken: number,
	possessionToken: number
): boolean
	if not isCarryRuntimePresent(player) then
		if carryModel then
			carryModel:Destroy()
		end
		local disruptEnabled = state == "CHASE_ACTIVE" and os.clock() >= postClaimProtectionEndsAt
		carryModel = createCarry(player, characterRoot, attemptToken, possessionToken, candidate, disruptEnabled)
	end

	if not isWardenRuntimePresent() then
		if wardenModel then
			wardenModel:Destroy()
		end
		local replacement = createWarden(chaseRuntime.WardenSpawnMarker)
		replacement:PivotTo(wardenCFrame or chaseRuntime.WardenSpawnMarker.CFrame)
		wardenModel = replacement
	end

	return isCarryRuntimePresent(player) and isWardenRuntimePresent()
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
	local wakePulse = model:FindFirstChild("WakePulse")
	if wakePulse and wakePulse:IsA("BasePart") then
		wakePulse.Transparency = if bright then 0.42 else 1
	end
end

local function runActivationTelegraph(player: Player, attemptToken: number, possessionToken: number)
	local bright = false
	local nextAlarmToggle = 0
	while generation == attemptToken
		and possessionId == possessionToken
		and carrier == player
		and state == "ACTIVATING"
	do
		local now = os.clock()
		updateCarryMotion(player, now)
		if now >= nextAlarmToggle then
			bright = not bright
			setWardenAlarm(bright)
			nextAlarmToggle = now + 0.25
		end
		task.wait(0.1)
	end
end

local function setWardenPulseWindup(active: boolean)
	local model = wardenModel
	local emitter = if model then model:FindFirstChild("PulseEmitter") else nil
	if emitter and emitter:IsA("BasePart") then
		emitter.Transparency = if active then 0 else 0.78
		local light = emitter:FindFirstChild("PulseWindupLight")
		if light and light:IsA("PointLight") then
			light.Brightness = if active then 5 else 0
		end
	end
end

local function getScrapPulseTargetPosition(player: Player, root: BasePart, humanoid: Humanoid, candidate: Definition): Vector3
	local moveDirection = humanoid.MoveDirection
	local flatDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flatDirection.Magnitude > 1 then
		flatDirection = flatDirection.Unit
	end
	local predicted = root.Position + flatDirection * candidate.ScrapPulsePredictionDistance
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	if player.Character then
		table.insert(excluded, player.Character)
	end
	if carryModel then
		table.insert(excluded, carryModel :: Model)
	end
	if wardenModel then
		table.insert(excluded, wardenModel :: Model)
	end
	raycastParams.FilterDescendantsInstances = excluded
	local result = Workspace:Raycast(predicted + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), raycastParams)
	if result then
		return result.Position + Vector3.new(0, 0.12, 0)
	end
	return Vector3.new(predicted.X, root.Position.Y - 3, predicted.Z)
end

local function createScrapPulseTelegraph(targetPosition: Vector3, candidate: Definition, attackId: number): Model
	local folder = assert(runtimeFolder, "Furnace Pod chase runtime folder is unavailable.")
	local model = Instance.new("Model")
	model.Name = string.format("ScrapPulse_%d", attackId)
	model:SetAttribute("AttackId", attackId)
	model:SetAttribute("TargetPosition", targetPosition)
	local orientation = CFrame.new(targetPosition) * CFrame.Angles(0, 0, math.rad(90))
	local diameter = candidate.ScrapPulseRadius * 2
	local warning = newDisplayPart(
		model,
		"WarningZone",
		orientation,
		CFrame.identity,
		Vector3.new(0.16, diameter, diameter),
		Color3.fromRGB(255, 78, 34),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	warning.Transparency = 0.52
	local center = newDisplayPart(
		model,
		"ImpactCore",
		orientation,
		CFrame.new(-0.04, 0, 0),
		Vector3.new(0.2, diameter * 0.34, diameter * 0.34),
		Color3.fromRGB(255, 184, 48),
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	center.Transparency = 0.28
	local warningLight = Instance.new("PointLight")
	warningLight.Name = "WarningLight"
	warningLight.Color = Color3.fromRGB(255, 92, 35)
	warningLight.Brightness = 2.5
	warningLight.Range = candidate.ScrapPulseRadius * 2
	warningLight.Shadows = false
	warningLight.Parent = center
	model.Parent = folder
	TweenService:Create(
		warning,
		TweenInfo.new(candidate.ScrapPulseTelegraphSeconds, Enum.EasingStyle.Linear),
		{ Transparency = 0.3, Color = Color3.fromRGB(255, 43, 24) }
	):Play()
	TweenService:Create(
		center,
		TweenInfo.new(candidate.ScrapPulseTelegraphSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 0.05, Size = Vector3.new(0.22, diameter * 0.62, diameter * 0.62) }
	):Play()
	return model
end

local function applyScrapPulseSlow(
	player: Player,
	humanoid: Humanoid,
	attemptToken: number,
	possessionToken: number,
	attackId: number,
	candidate: Definition
)
	local activeOverride = movementOverride
	if not activeOverride or activeOverride.Player ~= player or activeOverride.Humanoid ~= humanoid then
		return
	end
	activeOverride.PulseMultiplier = candidate.ScrapPulseSlowMultiplier
	pulseDebuffAttackId = attackId
	pulseDebuffExpiresAt = os.clock() + candidate.ScrapPulseSlowSeconds
	applyDerivedMovement(activeOverride)
	task.delay(candidate.ScrapPulseSlowSeconds, function()
		if generation ~= attemptToken
			or possessionId ~= possessionToken
			or carrier ~= player
			or state ~= "CHASE_ACTIVE"
			or pulseDebuffAttackId ~= attackId
		then
			return
		end
		local currentOverride = movementOverride
		if not currentOverride or currentOverride ~= activeOverride or currentOverride.Humanoid ~= humanoid then
			return
		end
		pulseDebuffAttackId = nil
		pulseDebuffExpiresAt = 0
		currentOverride.PulseMultiplier = 1
		applyDerivedMovement(currentOverride)
	end)
end

local function resolveScrapPulse(
	player: Player,
	attemptToken: number,
	possessionToken: number,
	attackId: number,
	candidate: Definition
)
	local pulse = activeScrapPulse
	if generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or state ~= "CHASE_ACTIVE"
		or not pulse
		or pulse.AttackId ~= attackId
	then
		return
	end
	activeScrapPulse = nil
	setWardenPulseWindup(false)
	local telegraphModel = pulse.TelegraphModel
	if telegraphModel then
		for _, descendant in ipairs(telegraphModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Color = Color3.fromRGB(255, 214, 90)
				descendant.Transparency = 0.08
				TweenService:Create(descendant, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(telegraphModel, 0.25)
	end

	local root, humanoid = getCharacterRootAndHumanoid(player)
	if not root or not humanoid then
		return
	end
	local offset = root.Position - pulse.TargetPosition
	local horizontalDistance = Vector2.new(offset.X, offset.Z).Magnitude
	if horizontalDistance <= candidate.ScrapPulseRadius then
		applyScrapPulseSlow(player, humanoid, attemptToken, possessionToken, attackId, candidate)
		fireCarrier(player, { Kind = "PULSE_HIT" })
	else
		fireCarrier(player, { Kind = "PULSE_DODGED" })
	end
end

local function beginPublicScrapPulseTelegraph(
	player: Player,
	attemptToken: number,
	possessionToken: number,
	attackId: number,
	candidate: Definition
)
	local pulse = activeScrapPulse
	if generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or state ~= "CHASE_ACTIVE"
		or not pulse
		or pulse.AttackId ~= attackId
		or pulse.TelegraphModel ~= nil
	then
		return
	end

	pulse.TelegraphModel = createScrapPulseTelegraph(pulse.TargetPosition, candidate, attackId)
	setWardenPulseWindup(true)
	task.delay(candidate.ScrapPulseTelegraphSeconds, function()
		resolveScrapPulse(player, attemptToken, possessionToken, attackId, candidate)
	end)
end

local function tryStartScrapPulse(
	player: Player,
	root: BasePart,
	humanoid: Humanoid,
	wardenDistance: number,
	now: number,
	attemptToken: number,
	possessionToken: number,
	candidate: Definition
)
	if state ~= "CHASE_ACTIVE"
		or generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or activeScrapPulse ~= nil
		or now < nextScrapPulseAt
		or wardenDistance <= candidate.CatchRadius + 4
		or not isWardenRuntimePresent()
	then
		return
	end
	nextScrapPulseId += 1
	local attackId = nextScrapPulseId
	local targetPosition = getScrapPulseTargetPosition(player, root, humanoid, candidate)
	local forecastEligible = ConstructCapabilityResolver.HasScrapPulseForecastCapability(player)
	activeScrapPulse = {
		AttackId = attackId,
		TargetPosition = targetPosition,
		ResolveAt = now + candidate.ScrapPulseForecastSeconds + candidate.ScrapPulseTelegraphSeconds,
		ForecastEligible = forecastEligible,
		ForecastSent = forecastEligible,
		TelegraphModel = nil,
	}
	nextScrapPulseAt = now + candidate.ScrapPulseCooldownSeconds
	if forecastEligible then
		fireCarrier(player, {
			Kind = "PULSE_FORECAST",
			AttackId = attackId,
			TargetPosition = targetPosition,
			ForecastDuration = candidate.ScrapPulseForecastSeconds,
		})
	end
	task.delay(candidate.ScrapPulseForecastSeconds, function()
		beginPublicScrapPulseTelegraph(player, attemptToken, possessionToken, attackId, candidate)
	end)
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

local function scheduleReset(resetToken: number, delaySeconds: number)
	cooldownEndsAt = os.clock() + delaySeconds
	task.spawn(function()
		while generation == resetToken and state == "RESETTING" do
			local remaining = math.max(0, math.ceil(cooldownEndsAt - os.clock()))
			setAvailabilityText(string.format("RECHARGING %ds", remaining))
			if remaining <= 0 then
				break
			end
			task.wait(1)
		end
	end)
	task.delay(delaySeconds, function()
		if generation ~= resetToken or state ~= "RESETTING" then
			return
		end
		cooldownEndsAt = 0
		state = "AVAILABLE"
		setTargetAvailable(true)
		setAvailabilityText("AVAILABLE")
		print("[ODDWORKS][FurnacePodChase] Furnace Pod reset and is available again.")
	end)
end

local function failAttempt(
	player: Player,
	attemptToken: number,
	possessionToken: number,
	shouldReturnToWorkshop: boolean,
	notifyClient: boolean
)
	if generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or (state ~= "ACTIVATING" and state ~= "RECLAIMING" and state ~= "CHASE_ACTIVE" and state ~= "SECURED")
	then
		return
	end

	generation += 1
	local resetToken = generation
	state = "RESETTING"
	setAvailabilityText("RESETTING")
	RecoveryCarrierRegistry.Release(player, RECOVERY_ACTIVITY_ID)
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
		scheduleReset(resetToken, candidate.ResetSeconds)
	end
end

local function cancelAttempt(player: Player, attemptToken: number, possessionToken: number, reason: string)
	if generation ~= attemptToken or possessionId ~= possessionToken or carrier ~= player then
		return
	end
	failAttempt(player, attemptToken, possessionToken, false, false)
	fireCarrier(player, { Kind = "CANCELLED" })
	warn(string.format("[ODDWORKS][FurnacePodChase] Cancelled %s attempt: %s.", player.Name, reason))
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
		wardenCFrame = model:GetPivot()
	end
	return distance
end

local function completeSecure(player: Player, attemptToken: number, possessionToken: number, candidate: Definition)
	if generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or state ~= "CHASE_ACTIVE"
	then
		return
	end

	state = "SECURED"
	restoreChaseMovement(player)
	destroyAttemptModels()
	fireCarrier(player, { Kind = "SECURED" })
	print(string.format("[ODDWORKS][FurnacePodChase] %s secured the Furnace Pod.", player.Name))

	task.delay(candidate.RevealDelaySeconds, function()
		if generation ~= attemptToken
			or possessionId ~= possessionToken
			or state ~= "SECURED"
			or carrier ~= player
			or player.Parent ~= Players
			or not PlayerStateService.HasState(player)
			or not ModularPrototypeStateService.HasState(player)
		then
			return
		end
		if not WorkshopService.GetAssignedPlot(player) then
			cancelAttempt(player, attemptToken, possessionToken, "WORKSHOP_UNAVAILABLE")
			return
		end
		local _, humanoid = getCharacterRootAndHumanoid(player)
		if not humanoid then
			failAttempt(player, attemptToken, possessionToken, false, false)
			return
		end

		local preRewardState = PlayerStateService.GetSnapshot(player)
		if not preRewardState then
			cancelAttempt(player, attemptToken, possessionToken, "REWARD_FAILED")
			return
		end
		local firstDiscovery = (preRewardState.OwnedOddlings.Kilnback or 0) == 0

		if not OddlingDisplayService.HasRuntimeTemplate("Kilnback")
			or not SignatureDiscoveryService.CanRevealKilnbackFromFurnacePod(player)
			or not PlayerStateService.CanAddOwnedOddling(player, "Kilnback", 1)
		then
			warn(string.format("[ODDWORKS][FurnacePodChase] Kilnback reward preflight failed for %s.", player.Name))
			cancelAttempt(player, attemptToken, possessionToken, "REWARD_FAILED")
			return
		end
		if not PlayerStateService.AddOwnedOddling(player, "Kilnback", 1) then
			warn(string.format("[ODDWORKS][FurnacePodChase] Kilnback ownership commit failed for %s.", player.Name))
			cancelAttempt(player, attemptToken, possessionToken, "REWARD_FAILED")
			return
		end

		if not SignatureDiscoveryService.RevealKilnbackFromFurnacePod(player) then
			-- Ownership has already committed and remains authoritative. Presentation
			-- failure must not reopen the attempt and duplicate the persistent reward.
			warn(string.format("[ODDWORKS][FurnacePodChase] Kilnback presentation failed after ownership commit for %s.", player.Name))
		end

		disconnectActiveDeath()
		RecoveryCarrierRegistry.Release(player, RECOVERY_ACTIVITY_ID)
		carrier = nil
		local updatedState = PlayerStateService.GetSnapshot(player)
		local ownedCount = if updatedState then updatedState.OwnedOddlings.Kilnback or 0 else 0
		fireCarrier(player, {
			Kind = "REVEALED",
			SignatureId = "Kilnback",
			OwnedCount = ownedCount,
			FirstDiscovery = firstDiscovery,
		})
		generation += 1
		local resetToken = generation
		state = "RESETTING"
		setAvailabilityText(string.format("RECHARGING %ds", math.ceil(candidate.SuccessCooldownSeconds)))
		scheduleReset(resetToken, candidate.SuccessCooldownSeconds)
		print(string.format("[ODDWORKS][FurnacePodChase] %s recovered Kilnback x%d.", player.Name, ownedCount))
	end)
end

local function runChase(player: Player, attemptToken: number, possessionToken: number, candidate: Definition)
	local previousClock = os.clock()
	while generation == attemptToken
		and possessionId == possessionToken
		and carrier == player
		and state == "CHASE_ACTIVE"
	do
		local root, humanoid = getCharacterRootAndHumanoid(player)
		if not root or not humanoid then
			failAttempt(player, attemptToken, possessionToken, false, player.Parent == Players)
			return
		end
		local chaseRuntime = runtime
		if not chaseRuntime or not ensureAttemptModels(player, root, chaseRuntime, candidate, attemptToken, possessionToken) then
			cancelAttempt(player, attemptToken, possessionToken, "RUNTIME_UNAVAILABLE")
			return
		end
		if activeScrapPulse and activeScrapPulse.TelegraphModel ~= nil then
			setWardenPulseWindup(true)
		end

		local secureZone = getAssignedSecureZone(player, candidate)
		if not secureZone then
			cancelAttempt(player, attemptToken, possessionToken, "WORKSHOP_UNAVAILABLE")
			return
		end
		if isInsideVolume(root.Position, secureZone) then
			completeSecure(player, attemptToken, possessionToken, candidate)
			return
		end

		local now = os.clock()
		updateCarryMotion(player, now)
		local elapsed = now - chaseStartedAt
		local stage = getStage(elapsed, candidate)
		if stage ~= currentStage then
			currentStage = stage
			fireCarrier(player, { Kind = "STAGE", Stage = stage })
		end

		local distance = moveWardenToward(root.Position, candidate.StageSpeeds[stage], math.min(now - previousClock, 0.25))
		previousClock = now
		if distance <= candidate.CatchRadius then
			failAttempt(player, attemptToken, possessionToken, true, true)
			return
		end
		tryStartScrapPulse(player, root, humanoid, distance, now, attemptToken, possessionToken, candidate)
		task.wait(candidate.PollSeconds)
	end
end

local function createContestPulse(position: Vector3, name: string, color: Color3)
	local folder = runtimeFolder
	if not folder then
		return
	end
	local model = Instance.new("Model")
	model.Name = name
	local pulse = newDisplayPart(
		model,
		"Pulse",
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		CFrame.identity,
		Vector3.new(0.12, 3, 3),
		color,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	pulse.Transparency = 0.25
	model.Parent = folder
	TweenService:Create(
		pulse,
		TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.12, 10, 10), Transparency = 1 }
	):Play()
	Debris:AddItem(model, 0.4)
end

local function createContestStatus(position: Vector3, text: string, color: Color3)
	local folder = runtimeFolder
	if not folder then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "FurnaceContestStatus"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Position = position + Vector3.new(0, 3.5, 0)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StatusLabel"
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 75
	billboard.Size = UDim2.fromOffset(170, 36)
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(48, 27, 22)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 14
	label.Parent = billboard

	anchor.Parent = folder
	Debris:AddItem(anchor, 1.2)
end

local function createServoBraceEffect(attemptToken: number, possessionToken: number)
	local folder = runtimeFolder
	local model = carryModel
	if not folder or not model or not model.PrimaryPart then
		return
	end
	if servoBraceEffect then
		servoBraceEffect:Destroy()
		servoBraceEffect = nil
	end

	local carryRoot = model.PrimaryPart
	local rootCFrame = carryRoot.CFrame
	local effect = Instance.new("Model")
	effect.Name = "ServoBraceEffect"
	effect:SetAttribute("RecoveryGeneration", attemptToken)
	effect:SetAttribute("PossessionId", possessionToken)
	local color = Color3.fromRGB(186, 240, 255)
	local brackets = {
		{ CFrame.new(-1.75, 0, -0.1), Vector3.new(0.22, 2.8, 0.35) },
		{ CFrame.new(1.75, 0, -0.1), Vector3.new(0.22, 2.8, 0.35) },
		{ CFrame.new(0, 1.75, -0.1), Vector3.new(2.8, 0.22, 0.35) },
		{ CFrame.new(0, -1.75, -0.1), Vector3.new(2.8, 0.22, 0.35) },
	}
	for index, bracketDefinition in ipairs(brackets) do
		local bracket = newDisplayPart(
			effect,
			"LockBracket" .. index,
			rootCFrame,
			bracketDefinition[1] :: CFrame,
			bracketDefinition[2] :: Vector3,
			color,
			Enum.Material.Neon,
			nil
		)
		bracket.Anchored = false
		bracket.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "ServoBraceWeld"
		weld.Part0 = carryRoot
		weld.Part1 = bracket
		weld.Parent = bracket
		bracket.Transparency = 0.12
		TweenService:Create(
			bracket,
			TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		):Play()
	end
	effect.Parent = folder
	servoBraceEffect = effect
	task.delay(0.52, function()
		if effect.Parent ~= nil then
			effect:Destroy()
		end
		if servoBraceEffect == effect then
			servoBraceEffect = nil
		end
	end)
end

local function consumeSecureGrip(player: Player, attemptToken: number, possessionToken: number): boolean
	if generation ~= attemptToken
		or possessionId ~= possessionToken
		or carrier ~= player
		or state ~= "CHASE_ACTIVE"
		or secureGripCapabilityGeneration ~= attemptToken
		or secureGripCapabilityPossessionId ~= possessionToken
		or not secureGripEligibleForPossession
		or not secureGripAvailable
	then
		return false
	end
	secureGripAvailable = false
	return true
end

local function projectDropCandidate(candidatePosition: Vector3, excluded: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	local result = Workspace:Raycast(
		candidatePosition + Vector3.new(0, 8, 0),
		Vector3.new(0, -32, 0),
		params
	)
	if result and result.Normal.Y >= 0.55 then
		return result.Position + Vector3.new(0, 1.75, 0)
	end
	return nil
end

local function getGroundedDropPosition(
	targetPlayer: Player,
	carrierRoot: BasePart,
	attacker: Player,
	attackerRoot: BasePart,
	candidate: Definition
): Vector3
	local excluded: { Instance } = {}
	if targetPlayer.Character then
		table.insert(excluded, targetPlayer.Character)
	end
	if attacker.Character then
		table.insert(excluded, attacker.Character)
	end
	if carryModel then
		table.insert(excluded, carryModel :: Model)
	end
	if wardenModel then
		table.insert(excluded, wardenModel :: Model)
	end

	local interactionOffset = attackerRoot.Position - carrierRoot.Position
	local flatAxis = Vector3.new(interactionOffset.X, 0, interactionOffset.Z)
	if flatAxis.Magnitude < 0.05 then
		local look = carrierRoot.CFrame.LookVector
		flatAxis = Vector3.new(look.X, 0, look.Z)
	end
	if flatAxis.Magnitude < 0.05 then
		flatAxis = Vector3.new(0, 0, -1)
	end

	local axis = flatAxis.Unit
	local perpendicular = Vector3.new(-axis.Z, 0, axis.X)
	local contestantDistance = math.min(flatAxis.Magnitude, candidate.DisruptRange)
	local halfDistance = contestantDistance * 0.5
	local neutralSideDistance = math.sqrt(math.max(0, candidate.DropPlacementDistance ^ 2 - halfDistance ^ 2))
	local midpoint = carrierRoot.Position + axis * halfDistance
	local candidates = {
		midpoint + perpendicular * neutralSideDistance,
		midpoint - perpendicular * neutralSideDistance,
		carrierRoot.Position + perpendicular * candidate.DropPlacementDistance,
		carrierRoot.Position - perpendicular * candidate.DropPlacementDistance,
	}
	for _, candidatePosition in ipairs(candidates) do
		local grounded = projectDropCandidate(candidatePosition, excluded)
		if grounded then
			return grounded
		end
	end

	local fallback = candidates[1]
	return Vector3.new(fallback.X, carrierRoot.Position.Y - 1.1, fallback.Z)
end

local function hasDisruptLineOfSight(
	attacker: Player,
	attackerRoot: BasePart,
	targetPlayer: Player,
	targetRoot: BasePart
): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	if attacker.Character then
		table.insert(excluded, attacker.Character)
	end
	if targetPlayer.Character then
		table.insert(excluded, targetPlayer.Character)
	end
	if carryModel then
		table.insert(excluded, carryModel :: Model)
	end
	params.FilterDescendantsInstances = excluded
	return Workspace:Raycast(attackerRoot.Position, targetRoot.Position - attackerRoot.Position, params) == nil
end

local function hasClaimLineOfSight(claimant: Player, claimantRoot: BasePart, targetPosition: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	if droppedModel then
		table.insert(excluded, droppedModel :: Model)
	end
	if wardenModel then
		table.insert(excluded, wardenModel :: Model)
	end
	params.FilterDescendantsInstances = excluded
	return Workspace:Raycast(claimantRoot.Position, targetPosition - claimantRoot.Position, params) == nil
end

local function resetDroppedAttempt(attemptToken: number, droppedPossessionToken: number, reason: string)
	if generation ~= attemptToken
		or possessionId ~= droppedPossessionToken
		or state ~= "DROPPED_CONTESTED"
		or carrier ~= nil
	then
		return
	end

	generation += 1
	local resetToken = generation
	state = "RESETTING"
	setAvailabilityText("RESETTING")
	disconnectActiveDeath()
	destroyAttemptModels()
	local candidate = definition
	if candidate then
		scheduleReset(resetToken, candidate.ResetSeconds)
	end
	warn(string.format("[ODDWORKS][FurnacePodChase] Contested attempt reset: %s.", reason))
end

local function runDroppedContest(attemptToken: number, droppedPossessionToken: number, candidate: Definition)
	local previousClock = os.clock()
	while generation == attemptToken
		and possessionId == droppedPossessionToken
		and state == "DROPPED_CONTESTED"
		and carrier == nil
	do
		local targetPosition = droppedPosition
		local chaseRuntime = runtime
		if not targetPosition or not chaseRuntime then
			resetDroppedAttempt(attemptToken, droppedPossessionToken, "DROPPED_RUNTIME_UNAVAILABLE")
			return
		end
		if not isWardenRuntimePresent() then
			if wardenModel then
				wardenModel:Destroy()
			end
			local replacement = createWarden(chaseRuntime.WardenSpawnMarker)
			replacement:PivotTo(wardenCFrame or chaseRuntime.WardenSpawnMarker.CFrame)
			wardenModel = replacement
		end

		local now = os.clock()
		local stage = getStage(now - chaseStartedAt, candidate)
		currentStage = stage
		local distance = moveWardenToward(
			targetPosition,
			candidate.StageSpeeds[stage],
			math.min(now - previousClock, 0.25)
		)
		previousClock = now
		if now >= claimOpenAt and distance <= candidate.WardenReclaimRadius then
			createContestPulse(targetPosition, "FurnaceWardenReclaimImpact", Color3.fromRGB(255, 83, 37))
			createContestStatus(targetPosition, "POD RECLAIMED", Color3.fromRGB(255, 151, 67))
			resetDroppedAttempt(attemptToken, droppedPossessionToken, "WARDEN_RECLAIM")
			return
		end
		task.wait(candidate.PollSeconds)
	end
end

disruptPromptHandler = function(attacker: Player, attemptToken: number, possessionToken: number)
	local candidate = definition
	local targetPlayer = carrier
	if not candidate
		or generation ~= attemptToken
		or possessionId ~= possessionToken
		or state ~= "CHASE_ACTIVE"
		or not targetPlayer
		or attacker == targetPlayer
		or attacker.Parent ~= Players
		or targetPlayer.Parent ~= Players
		or RecoveryCarrierRegistry.GetActiveActivity(attacker) ~= nil
		or RecoveryCarrierRegistry.GetActiveActivity(targetPlayer) ~= RECOVERY_ACTIVITY_ID
	then
		return
	end

	local now = os.clock()
	local lastDisrupt = lastDisruptTimes[attacker]
	if now < postClaimProtectionEndsAt
		or (lastDisrupt and now - lastDisrupt < candidate.DisruptCooldownSeconds)
	then
		return
	end

	local attackerRoot, attackerHumanoid = getCharacterRootAndHumanoid(attacker)
	local targetRoot, targetHumanoid = getCharacterRootAndHumanoid(targetPlayer)
	if not attackerRoot
		or not attackerHumanoid
		or not targetRoot
		or not targetHumanoid
		or (attackerRoot.Position - targetRoot.Position).Magnitude > candidate.DisruptRange
		or not PlayerStateService.HasState(attacker)
		or not ModularPrototypeStateService.HasState(attacker)
	then
		return
	end
	local secureZone = getAssignedSecureZone(targetPlayer, candidate)
	if not secureZone
		or isInsideVolume(targetRoot.Position, secureZone)
		or not hasDisruptLineOfSight(attacker, attackerRoot, targetPlayer, targetRoot)
	then
		return
	end

	lastDisruptTimes[attacker] = now
	lastDisruptorUserId = attacker.UserId
	if consumeSecureGrip(targetPlayer, attemptToken, possessionToken) then
		createServoBraceEffect(attemptToken, possessionToken)
		fireCarrier(targetPlayer, { Kind = "SERVO_BRACE" })
		fireCarrier(attacker, { Kind = "DISRUPTION_BLOCKED" })
		return
	end

	local dropPosition = getGroundedDropPosition(targetPlayer, targetRoot, attacker, attackerRoot, candidate)
	clearPossessionCapabilitySnapshot()
	destroyScrapPulseTelegraph()
	setWardenPulseWindup(false)
	restoreChaseMovement(targetPlayer)
	disconnectActiveDeath()
	destroyCarryModel()
	RecoveryCarrierRegistry.Release(targetPlayer, RECOVERY_ACTIVITY_ID)
	carrier = nil
	state = "DROPPED_CONTESTED"
	droppedPosition = dropPosition
	claimOpenAt = now + candidate.ClaimGraceSeconds
	dropTimeoutAt = now + candidate.DroppedTimeoutSeconds
	postClaimProtectionEndsAt = 0
	droppedModel = createDroppedPod(dropPosition, attemptToken, possessionToken, candidate)
	setAvailabilityText("CONTESTED - CLAIM POD")
	setWardenAlarm(true)
	createContestPulse(dropPosition, "FurnaceDisruptionImpact", Color3.fromRGB(255, 84, 43))
	fireCarrier(targetPlayer, { Kind = "POD_DROPPED" })
	fireCarrier(attacker, { Kind = "DISRUPTION_SUCCESS" })

	task.delay(candidate.ClaimGraceSeconds, function()
		if generation == attemptToken
			and possessionId == possessionToken
			and state == "DROPPED_CONTESTED"
			and carrier == nil
			and os.clock() >= claimOpenAt
		then
			setDroppedClaimEnabled(true)
		end
	end)
	task.delay(candidate.DroppedTimeoutSeconds, function()
		resetDroppedAttempt(attemptToken, possessionToken, "DROP_TIMEOUT")
	end)
	task.spawn(runDroppedContest, attemptToken, possessionToken, candidate)
end

claimPromptHandler = function(claimant: Player, attemptToken: number, droppedPossessionToken: number)
	local candidate = definition
	if not candidate
		or generation ~= attemptToken
		or possessionId ~= droppedPossessionToken
		or state ~= "DROPPED_CONTESTED"
		or carrier ~= nil
		or os.clock() < claimOpenAt
		or claimant.Parent ~= Players
		or RecoveryCarrierRegistry.GetActiveActivity(claimant) ~= nil
		or not PlayerStateService.HasState(claimant)
		or not ModularPrototypeStateService.HasState(claimant)
		or not WorkshopService.GetAssignedPlot(claimant)
	then
		return
	end
	local claimantRoot, humanoid = getCharacterRootAndHumanoid(claimant)
	local authoritativeDropPosition = droppedPosition
	if not claimantRoot
		or not humanoid
		or not authoritativeDropPosition
		or (claimantRoot.Position - authoritativeDropPosition).Magnitude > candidate.ClaimRange
		or not hasClaimLineOfSight(claimant, claimantRoot, authoritativeDropPosition)
	then
		return
	end
	local secureZone = getAssignedSecureZone(claimant, candidate)
	if not secureZone then
		return
	end

	-- TryAcquire and the shared-state commit contain no yield. Once the registry
	-- accepts this claimant, every later handler observes a non-dropped phase.
	if not RecoveryCarrierRegistry.TryAcquire(claimant, RECOVERY_ACTIVITY_ID) then
		return
	end
	local now = os.clock()
	local newPossessionToken = droppedPossessionToken + 1
	carrier = claimant
	possessionId = newPossessionToken
	state = "RECLAIMING"
	droppedPosition = nil
	claimOpenAt = 0
	dropTimeoutAt = 0
	postClaimProtectionEndsAt = now + candidate.PostClaimProtectionSeconds
	destroyDroppedModel()
	capturePossessionCapabilities(claimant, attemptToken, newPossessionToken)

	carryModel = createCarry(claimant, claimantRoot, attemptToken, newPossessionToken, candidate, false)
	local springLegsActive = applyChaseMovement(claimant, humanoid, candidate)
	activeDeathConnection = humanoid.Died:Connect(function()
		failAttempt(claimant, attemptToken, newPossessionToken, false, claimant.Parent == Players)
	end)
	nextScrapPulseAt = now + candidate.ReclaimPulseDelaySeconds
	setAvailabilityText("IN RECOVERY")
	createContestPulse(authoritativeDropPosition, "FurnaceClaimImpact", Color3.fromRGB(255, 187, 67))
	fireCarrier(claimant, {
		Kind = "POD_CLAIMED",
		ReclaimHeadStartSeconds = candidate.ReclaimHeadStartSeconds,
		DestinationPosition = secureZone.Position,
		SpringLegsActive = springLegsActive,
	})

	task.delay(candidate.PostClaimProtectionSeconds, function()
		if generation == attemptToken
			and possessionId == newPossessionToken
			and carrier == claimant
			and state == "CHASE_ACTIVE"
		then
			activateCurrentDisruptInteraction(claimant, attemptToken, newPossessionToken, candidate)
		end
	end)
	task.delay(candidate.ReclaimHeadStartSeconds, function()
		if generation ~= attemptToken
			or possessionId ~= newPossessionToken
			or carrier ~= claimant
			or state ~= "RECLAIMING"
		then
			return
		end
		local activeRoot, activeHumanoid = getCharacterRootAndHumanoid(claimant)
		local chaseRuntime = runtime
		if not activeRoot
			or not activeHumanoid
			or not chaseRuntime
			or not PlayerStateService.HasState(claimant)
			or not ModularPrototypeStateService.HasState(claimant)
			or not getAssignedSecureZone(claimant, candidate)
		then
			failAttempt(claimant, attemptToken, newPossessionToken, false, claimant.Parent == Players)
			return
		end
		if not ensureAttemptModels(claimant, activeRoot, chaseRuntime, candidate, attemptToken, newPossessionToken) then
			cancelAttempt(claimant, attemptToken, newPossessionToken, "RUNTIME_UNAVAILABLE")
			return
		end
		verifyChaseMovement(claimant, activeHumanoid)
		currentStage = getStage(os.clock() - chaseStartedAt, candidate)
		state = "CHASE_ACTIVE"
		setWardenAlarm(true)
		fireCarrier(claimant, { Kind = "CHASE_STARTED", Stage = currentStage })
		task.spawn(runChase, claimant, attemptToken, newPossessionToken, candidate)
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
		or RecoveryCarrierRegistry.GetActiveActivity(player) ~= nil
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
	if not RecoveryCarrierRegistry.TryAcquire(player, RECOVERY_ACTIVITY_ID) then
		return
	end
	generation += 1
	local attemptToken = generation
	possessionId = 1
	local possessionToken = possessionId
	state = "STOLEN"
	carrier = player
	setTargetAvailable(false)
	setAvailabilityText("IN RECOVERY")
	destroyAttemptModels()
	capturePossessionCapabilities(player, attemptToken, possessionToken)

	carryModel = createCarry(player, root, attemptToken, possessionToken, candidate, false)
	wardenModel = createWarden(chaseRuntime.WardenSpawnMarker)
	wardenCFrame = chaseRuntime.WardenSpawnMarker.CFrame
	local springLegsActive = applyChaseMovement(player, humanoid, candidate)
	activeDeathConnection = humanoid.Died:Connect(function()
		failAttempt(player, attemptToken, possessionToken, false, player.Parent == Players)
	end)
	state = "ACTIVATING"
	fireCarrier(player, {
		Kind = "ACTIVATING",
		HeadStartSeconds = candidate.HeadStartSeconds,
		DestinationPosition = secureZone.Position,
		SpringLegsActive = springLegsActive,
	})
	print(string.format("[ODDWORKS][FurnacePodChase] %s stole the Furnace Pod; Warden activating.", player.Name))
	task.spawn(runActivationTelegraph, player, attemptToken, possessionToken)
	task.delay(candidate.HeadStartSeconds, function()
		if generation ~= attemptToken
			or possessionId ~= possessionToken
			or carrier ~= player
			or state ~= "ACTIVATING"
		then
			return
		end
		local activeRoot, activeHumanoid = getCharacterRootAndHumanoid(player)
		if not activeRoot
			or not activeHumanoid
			or player.Parent ~= Players
			or not PlayerStateService.HasState(player)
			or not ModularPrototypeStateService.HasState(player)
		then
			failAttempt(player, attemptToken, possessionToken, false, player.Parent == Players)
			return
		end
		local currentSecureZone = getAssignedSecureZone(player, candidate)
		if not currentSecureZone then
			cancelAttempt(player, attemptToken, possessionToken, "WORKSHOP_UNAVAILABLE")
			return
		end
		if not ensureAttemptModels(player, activeRoot, chaseRuntime, candidate, attemptToken, possessionToken) then
			cancelAttempt(player, attemptToken, possessionToken, "RUNTIME_UNAVAILABLE")
			return
		end
		verifyChaseMovement(player, activeHumanoid)
		setWardenAlarm(true)
		chaseStartedAt = os.clock()
		nextScrapPulseAt = chaseStartedAt + candidate.ScrapPulseCooldownSeconds
		currentStage = 1
		state = "CHASE_ACTIVE"
		activateCurrentDisruptInteraction(player, attemptToken, possessionToken, candidate)
		fireCarrier(player, { Kind = "CHASE_STARTED", Stage = 1 })
		print(string.format("[ODDWORKS][FurnacePodChase] Scrap Warden chase active for %s.", player.Name))
		task.spawn(runChase, player, attemptToken, possessionToken, candidate)
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
	lastDisruptTimes[player] = nil
	if carrier == player then
		local shouldNotifyClient = player.Parent == Players
		failAttempt(player, generation, possessionId, false, false)
		if shouldNotifyClient then
			fireCarrier(player, { Kind = "CANCELLED" })
		end
	else
		restoreChaseMovement(player)
		RecoveryCarrierRegistry.Release(player, RECOVERY_ACTIVITY_ID)
	end
end

local function handleModularStateChanged(player: Player)
	if carrier ~= player
		or (state ~= "ACTIVATING" and state ~= "RECLAIMING" and state ~= "CHASE_ACTIVE")
	then
		return
	end
	local activeOverride = movementOverride
	if not activeOverride or activeOverride.Player ~= player then
		return
	end
	if springLegsEligibleForAttempt and not ConstructCapabilityResolver.HasSpringLegsChaseCapability(player) then
		springLegsEligibleForAttempt = false
		activeOverride.ChaseMultiplier = 1
		applyDerivedMovement(activeOverride)
	end
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

local function createAvailabilityLabel(marker: BasePart): TextLabel
	local previous = marker:FindFirstChild("FurnaceAvailabilityLabel")
	if previous then
		previous:Destroy()
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FurnaceAvailabilityLabel"
	billboard.Adornee = marker
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(180, 52)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	billboard.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(48, 31, 22)
	label.BackgroundTransparency = 0.14
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = "FURNACE POD\nHIGH SECURITY - AVAILABLE"
	label.TextColor3 = Color3.fromRGB(255, 151, 78)
	label.TextSize = 13
	label.TextWrapped = true
	label.Parent = billboard
	return label
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
	local availabilityLabel = createAvailabilityLabel(interactionPart)
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
		AvailabilityLabel = availabilityLabel,
	}
end

-- Returns a narrow read-only view for the Studio-only inspector. Runtime models,
-- private chase tables, and mutation functions remain inside this service.
function FurnacePodChaseService.GetDiagnosticSnapshot(player: Player): DiagnosticSnapshot
	local candidate = definition or FurnacePodChaseConfig.GetDefinition()
	local isCarrier = carrier == player
	local activePhase = state == "ACTIVATING" or state == "RECLAIMING" or state == "CHASE_ACTIVE"
	local activeMovement = movementOverride
	local playerMovement = if activeMovement and activeMovement.Player == player then activeMovement else nil
	local _, humanoid = getCharacterRootAndHumanoid(player)
	local applicationRecord = playerMovement ~= nil
	local speedMatchesExpected = playerMovement ~= nil
		and humanoid == playerMovement.Humanoid
		and math.abs((humanoid :: Humanoid).WalkSpeed - playerMovement.AppliedWalkSpeed) <= 0.01
	local now = os.clock()
	local pulse = if isCarrier then activeScrapPulse else nil
	local pulseDebuffActive = isCarrier and pulseDebuffAttackId ~= nil and pulseDebuffExpiresAt > now
	local secureGripSnapshotActive = isCarrier
		and activePhase
		and secureGripCapabilityGeneration == generation
		and secureGripCapabilityPossessionId == possessionId
	local wardenDistanceToDroppedPod: number? = nil
	local currentCarry = carryModel
	local disruptPrompt = if currentCarry then currentCarry:FindFirstChild("DisruptPrompt", true) else nil
	local activeDisruptPrompt = if disruptPrompt and disruptPrompt:IsA("ProximityPrompt") then disruptPrompt else nil
	if state == "DROPPED_CONTESTED" and droppedPosition and wardenModel and wardenModel.PrimaryPart then
		local wardenPosition = wardenModel:GetPivot().Position
		local offset = Vector3.new(droppedPosition.X - wardenPosition.X, 0, droppedPosition.Z - wardenPosition.Z)
		wardenDistanceToDroppedPod = offset.Magnitude
	end

	local phase = state :: string
	if state == "SECURED" and carrier == nil then
		phase = "REVEAL"
	end

	return {
		Phase = phase,
		AttemptGeneration = generation,
		IsCarrier = isCarrier,
		WardenStage = if state == "CHASE_ACTIVE" then currentStage else nil,
		CarryRuntimePresent = isCarrier and isCarryRuntimePresent(player),
		WardenRuntimePresent = isCarrier and isWardenRuntimePresent(),
		SpringLegsEligible = isCarrier
			and activePhase
			and ConstructCapabilityResolver.HasSpringLegsChaseCapability(player),
		SpringLegsApplicationRecord = applicationRecord and springLegsEligibleForAttempt,
		SpringLegsSpeedMatchesExpected = springLegsEligibleForAttempt and speedMatchesExpected,
		SpringLegsEffectApplied = applicationRecord and springLegsEligibleForAttempt and speedMatchesExpected,
		MovementBaselineWalkSpeed = if playerMovement then playerMovement.BaselineWalkSpeed else nil,
		ExpectedSpringLegsWalkSpeed = if playerMovement and springLegsEligibleForAttempt then playerMovement.ChaseWalkSpeed else nil,
		ConfiguredSpringLegsMultiplier = candidate.SpringLegsSpeedMultiplier,
		ExpectedCurrentWalkSpeed = if playerMovement then playerMovement.AppliedWalkSpeed else nil,
		PossessionId = possessionId,
		CarrierUserId = if carrier then carrier.UserId else nil,
		DroppedPosition = droppedPosition,
		DroppedInteractionPosition = if droppedPosition then droppedPosition + Vector3.new(0, candidate.ClaimAnchorHeight, 0) else nil,
		ClaimOpenRemaining = if state == "DROPPED_CONTESTED" then math.max(0, claimOpenAt - now) else 0,
		DropTimeoutRemaining = if state == "DROPPED_CONTESTED" then math.max(0, dropTimeoutAt - now) else 0,
		WardenDistanceToDroppedPod = wardenDistanceToDroppedPod,
		WardenReclaimRadius = candidate.WardenReclaimRadius,
		WardenReclaimEligible = state == "DROPPED_CONTESTED" and now >= claimOpenAt,
		LastDisruptorUserId = lastDisruptorUserId,
		DisruptCooldownRemaining = math.max(
			0,
			((lastDisruptTimes[player] or -candidate.DisruptCooldownSeconds) + candidate.DisruptCooldownSeconds) - now
		),
		PostClaimProtectionRemaining = math.max(0, postClaimProtectionEndsAt - now),
		DisruptPromptPresent = activeDisruptPrompt ~= nil,
		DisruptPromptInteractionId = if activeDisruptPrompt then activeDisruptPrompt:GetAttribute("InteractionId") else nil,
		DisruptPromptGeneration = if activeDisruptPrompt then activeDisruptPrompt:GetAttribute("RecoveryGeneration") else nil,
		DisruptPromptPossessionId = if activeDisruptPrompt then activeDisruptPrompt:GetAttribute("PossessionId") else nil,
		DisruptPromptParent = if activeDisruptPrompt and activeDisruptPrompt.Parent then activeDisruptPrompt.Parent.Name else nil,
		ServoArmInstalled = ConstructCapabilityResolver.HasSecureGripCapability(player),
		SecureGripCapability = secureGripSnapshotActive and secureGripEligibleForPossession,
		SecureGripAvailable = secureGripSnapshotActive and secureGripAvailable,
		SecureGripConsumed = secureGripSnapshotActive and secureGripEligibleForPossession and not secureGripAvailable,
		SecureGripCapabilityGeneration = if secureGripSnapshotActive then secureGripCapabilityGeneration else nil,
		SecureGripCapabilityPossessionId = if secureGripSnapshotActive then secureGripCapabilityPossessionId else nil,
		SignalScannerInstalled = ConstructCapabilityResolver.HasScrapPulseForecastCapability(player),
		PulseForecastCapability = ConstructCapabilityResolver.HasScrapPulseForecastCapability(player),
		ConfiguredScrapPulseForecastSeconds = candidate.ScrapPulseForecastSeconds,
		ScrapPulseForecastSent = pulse ~= nil and pulse.ForecastSent,
		ScrapPulseReady = isCarrier
			and state == "CHASE_ACTIVE"
			and pulse == nil
			and now >= nextScrapPulseAt,
		ScrapPulseAttackId = if pulse then pulse.AttackId else 0,
		ScrapPulseTelegraphActive = pulse ~= nil
			and pulse.TelegraphModel ~= nil
			and (pulse.TelegraphModel :: Model).Parent ~= nil,
		ScrapPulseTargetPosition = if pulse then pulse.TargetPosition else nil,
		ScrapPulseDebuffActive = pulseDebuffActive,
		ScrapPulseDebuffMultiplier = candidate.ScrapPulseSlowMultiplier,
		ScrapPulseDebuffRemaining = if pulseDebuffActive then math.max(0, pulseDebuffExpiresAt - now) else 0,
		CooldownRemaining = if state == "RESETTING" then math.max(0, cooldownEndsAt - os.clock()) else 0,
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
	startTargetPulse((runtime :: ChaseRuntime).TargetModel)

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
	setAvailabilityText("AVAILABLE")
	local chaseRuntime = runtime :: ChaseRuntime
	chaseRuntime.Prompt.Triggered:Connect(handlePromptTriggered)
	ModularPrototypeStateService.ObserveStateChanged(handleModularStateChanged)
	ModularPrototypeStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)
	print("[ODDWORKS][FurnacePodChase] Shared Furnace Pod chase prototype started.")
end

return FurnacePodChaseService
