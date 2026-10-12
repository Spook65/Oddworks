--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][KineticPodRecovery] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local ConstructCapabilityResolver = require(Services:WaitForChild("ConstructCapabilityResolver"))
local KineticPodRecoveryConfig = require(Config:WaitForChild("KineticPodRecoveryConfig"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local OddlingDisplayService = require(Services:WaitForChild("OddlingDisplayService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local RecoveryCarrierRegistry = require(Services:WaitForChild("RecoveryCarrierRegistry"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type Definition = KineticPodRecoveryConfig.KineticPodRecoveryDefinition
type RecoveryState = "AVAILABLE" | "ACTIVATING" | "CHASE_ACTIVE" | "SECURED" | "RESETTING"
type PartPresentation = {
	Transparency: number,
	CanCollide: boolean,
	CanQuery: boolean,
	CanTouch: boolean,
}
type RecoveryRuntime = {
	TargetModel: Model,
	InteractionPart: BasePart,
	Prompt: ProximityPrompt,
	WardenSpawnMarker: BasePart,
	TargetPresentation: { [BasePart]: PartPresentation },
	FurnaceInteractionPart: BasePart,
	AvailabilityLabel: TextLabel,
}
type MovementOverride = {
	Player: Player,
	Humanoid: Humanoid,
	BaselineWalkSpeed: number,
	AppliedWalkSpeed: number,
}

local KineticPodRecoveryService = {}

local RECOVERY_ACTIVITY_ID = "KINETIC_POD"
local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "KineticPodRecovery"

local state: RecoveryState = "AVAILABLE"
local carrier: Player? = nil
local generation = 0
local chaseStartedAt = 0
local currentStage = 0
local lastAttemptTimes: { [Player]: number } = {}
local springLegsBonusGranted: { [Player]: boolean } = {}
local guidanceStates: { [Player]: string } = {}
local movementOverride: MovementOverride? = nil
local springLegsEligibleForAttempt = false
local activeDeathConnection: RBXScriptConnection? = nil
local activeCharacterRemovingConnection: RBXScriptConnection? = nil
local carryModel: Model? = nil
local wardenModel: Model? = nil
local wardenCFrame: CFrame? = nil
local runtimeFolder: Folder? = nil
local runtime: RecoveryRuntime? = nil
local definition: Definition? = nil
local stateRemote: RemoteEvent? = nil
local cooldownEndsAt = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][KineticPodRecovery] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][KineticPodRecovery] %s.%s must be a %s, but found %s.",
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
			error(string.format("[ODDWORKS][KineticPodRecovery] %s must be a Folder.", existing:GetFullName()))
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
	if candidate.WorldModelName ~= "KineticPodTarget"
		or candidate.RewardSpeciesId ~= "Voltlet"
		or candidate.RewardSpeciesCount ~= 1
		or candidate.RewardComponentId ~= "SpringLegs"
		or candidate.RewardRarity ~= "Common"
		or candidate.RewardCount ~= 1
		or #candidate.StageSpeeds ~= 3
		or not isPositiveFinite(candidate.MaxStealDistance)
		or not isPositiveFinite(candidate.AttemptIntervalSeconds)
		or not isPositiveFinite(candidate.HeadStartSeconds)
		or not isPositiveFinite(candidate.SpringLegsSpeedMultiplier)
		or not isPositiveFinite(candidate.PollSeconds)
		or not isPositiveFinite(candidate.CatchRadius)
		or not isPositiveFinite(candidate.StageOneSeconds)
		or not isPositiveFinite(candidate.StageTwoSeconds)
		or candidate.StageOneSeconds >= candidate.StageTwoSeconds
		or not isPositiveFinite(candidate.ResetSeconds)
		or not isPositiveFinite(candidate.SuccessCooldownSeconds)
	then
		error("[ODDWORKS][KineticPodRecovery] Configuration is invalid.")
	end
	for _, speed in ipairs(candidate.StageSpeeds) do
		if not isPositiveFinite(speed) then
			error("[ODDWORKS][KineticPodRecovery] Scout Warden speed configuration is invalid.")
		end
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

local function firePlayer(player: Player, payload: { [string]: any })
	local remote = stateRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function setTargetAvailable(isAvailable: boolean)
	local recoveryRuntime = runtime
	if not recoveryRuntime then
		return
	end
	for part, presentation in pairs(recoveryRuntime.TargetPresentation) do
		if part.Parent ~= nil then
			part.Transparency = if isAvailable then presentation.Transparency else 1
			part.CanCollide = if isAvailable then presentation.CanCollide else false
			part.CanQuery = if isAvailable then presentation.CanQuery else false
			part.CanTouch = if isAvailable then presentation.CanTouch else false
		end
	end
	recoveryRuntime.Prompt.Enabled = isAvailable
end

local function setAvailabilityText(status: string)
	local recoveryRuntime = runtime
	if recoveryRuntime then
		recoveryRuntime.AvailabilityLabel.Text = string.format("KINETIC POD\nLOW SECURITY - %s", status)
	end
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

local function restoreMovement(player: Player)
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
	restoreMovement(player)
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
		humanoid.WalkSpeed = activeOverride.AppliedWalkSpeed
	end
	return math.abs(humanoid.WalkSpeed - activeOverride.AppliedWalkSpeed) <= 0.01
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

local function createCarry(player: Player, characterRoot: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "CarriedKineticPod"
	model:SetAttribute("CarrierUserId", player.UserId)

	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Anchored = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.CFrame = characterRoot.CFrame * CFrame.new(0, 1.25, 1.5)
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

	addPart("PodShell", CFrame.identity, Vector3.new(1.9, 2.4, 1.9), Color3.fromRGB(58, 79, 87), Enum.Material.Metal, Enum.PartType.Ball)
	addPart("KineticCore", CFrame.new(0, 0, -0.85), Vector3.new(0.9, 1.35, 0.3), Color3.fromRGB(58, 225, 255), Enum.Material.Neon, nil)
	addPart("UpperBand", CFrame.new(0, 0.78, 0), Vector3.new(2, 0.25, 2), Color3.fromRGB(98, 194, 210), Enum.Material.Metal, nil)
	addPart("LowerBand", CFrame.new(0, -0.78, 0), Vector3.new(2, 0.25, 2), Color3.fromRGB(98, 194, 210), Enum.Material.Metal, nil)

	local characterWeld = Instance.new("WeldConstraint")
	characterWeld.Name = "CharacterCarryWeld"
	characterWeld.Part0 = characterRoot
	characterWeld.Part1 = root
	characterWeld.Parent = root
	model.Parent = characterRoot.Parent
	return model
end

local function createScoutWarden(spawnMarker: BasePart): Model
	local folder = assert(runtimeFolder, "Kinetic recovery runtime folder is unavailable.")
	local model = Instance.new("Model")
	model.Name = "ScoutWarden"
	model:SetAttribute("PrototypePursuer", true)

	local root = newDisplayPart(model, "RootPart", spawnMarker.CFrame, CFrame.identity, Vector3.new(0.5, 0.5, 0.5), Color3.new(), Enum.Material.SmoothPlastic, nil)
	root.Transparency = 1
	model.PrimaryPart = root
	newDisplayPart(model, "ScoutBody", root.CFrame, CFrame.new(0, 1.7, 0), Vector3.new(2.6, 2.7, 2), Color3.fromRGB(66, 85, 89), Enum.Material.Metal, Enum.PartType.Ball)
	newDisplayPart(model, "ChestArc", root.CFrame, CFrame.new(0, 1.7, -0.95), Vector3.new(1.15, 1.35, 0.25), Color3.fromRGB(60, 220, 255), Enum.Material.Neon, nil)
	newDisplayPart(model, "Head", root.CFrame, CFrame.new(0, 3.55, 0), Vector3.new(1.8, 1.15, 1.6), Color3.fromRGB(104, 126, 126), Enum.Material.Metal, nil)
	local eye = newDisplayPart(model, "Eye", root.CFrame, CFrame.new(0, 3.55, -0.85), Vector3.new(0.9, 0.3, 0.2), Color3.fromRGB(255, 220, 87), Enum.Material.Neon, nil)
	local beacon = newDisplayPart(model, "AlarmBeacon", root.CFrame, CFrame.new(0, 4.45, 0), Vector3.new(0.55, 0.55, 0.55), Color3.fromRGB(52, 220, 255), Enum.Material.Neon, Enum.PartType.Ball)
	newDisplayPart(model, "LeftFoot", root.CFrame, CFrame.new(-0.7, 0.35, 0), Vector3.new(0.9, 0.7, 1.5), Color3.fromRGB(40, 48, 49), Enum.Material.Metal, nil)
	newDisplayPart(model, "RightFoot", root.CFrame, CFrame.new(0.7, 0.35, 0), Vector3.new(0.9, 0.7, 1.5), Color3.fromRGB(40, 48, 49), Enum.Material.Metal, nil)
	local light = Instance.new("PointLight")
	light.Name = "ActivationLight"
	light.Brightness = 0
	light.Color = Color3.fromRGB(58, 225, 255)
	light.Range = 14
	light.Parent = beacon
	eye.Transparency = 0.6
	beacon.Transparency = 0.6
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
		and weld:IsA("WeldConstraint")
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

local function ensureAttemptModels(player: Player, characterRoot: BasePart, recoveryRuntime: RecoveryRuntime): boolean
	if not isCarryRuntimePresent(player) then
		if carryModel then
			carryModel:Destroy()
		end
		carryModel = createCarry(player, characterRoot)
	end
	if not isWardenRuntimePresent() then
		if wardenModel then
			wardenModel:Destroy()
		end
		local replacement = createScoutWarden(recoveryRuntime.WardenSpawnMarker)
		replacement:PivotTo(wardenCFrame or recoveryRuntime.WardenSpawnMarker.CFrame)
		wardenModel = replacement
	end
	return isCarryRuntimePresent(player) and isWardenRuntimePresent()
end

local function setWardenAlarm(bright: boolean)
	local model = wardenModel
	if not model then
		return
	end
	for _, partName in ipairs({ "ChestArc", "Eye", "AlarmBeacon" }) do
		local part = model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = if bright then 0 else 0.6
		end
	end
	local beacon = model:FindFirstChild("AlarmBeacon")
	local light = if beacon then beacon:FindFirstChild("ActivationLight") else nil
	if light and light:IsA("PointLight") then
		light.Brightness = if bright then 3 else 0
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

local function getAssignedPart(player: Player, partName: string): BasePart?
	local plot = WorkshopService.GetAssignedPlot(player)
	local part = if plot then plot:FindFirstChild(partName) else nil
	return if part and part:IsA("BasePart") then part else nil
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
	end)
end

local function failAttempt(player: Player, attemptToken: number, shouldReturnToWorkshop: boolean, kind: string)
	if generation ~= attemptToken
		or carrier ~= player
		or (state ~= "ACTIVATING" and state ~= "CHASE_ACTIVE" and state ~= "SECURED")
	then
		return
	end
	generation += 1
	local resetToken = generation
	state = "RESETTING"
	setAvailabilityText("RESETTING")
	RecoveryCarrierRegistry.Release(player, RECOVERY_ACTIVITY_ID)
	carrier = nil
	restoreMovement(player)
	disconnectActiveLifecycle()
	destroyAttemptModels()
	if shouldReturnToWorkshop then
		returnToWorkshop(player)
	end
	firePlayer(player, { Kind = kind })
	local candidate = definition
	if candidate then
		scheduleReset(resetToken, candidate.ResetSeconds)
	end
end

local function getProgressDestination(player: Player, candidate: Definition, installed: boolean): Vector3?
	if installed then
		local recoveryRuntime = runtime
		return if recoveryRuntime then recoveryRuntime.FurnaceInteractionPart.Position else nil
	end
	local assembler = getAssignedPart(player, candidate.AssemblerName)
	return if assembler then assembler.Position else nil
end

local function sendProgressGuidance(player: Player, force: boolean)
	local candidate = definition
	if not candidate or not springLegsBonusGranted[player] or player.Parent ~= Players then
		return
	end
	local installed = ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	local nextState = if installed then "FURNACE" else "EQUIP"
	if not force and guidanceStates[player] == nextState then
		return
	end
	local destination = getProgressDestination(player, candidate, installed)
	if not destination then
		return
	end
	guidanceStates[player] = nextState
	firePlayer(player, {
		Kind = if installed then "ADVANCED_AVAILABLE" else "EQUIP_GUIDANCE",
		DestinationPosition = destination,
	})
end

local function completeSecure(player: Player, attemptToken: number, candidate: Definition)
	if generation ~= attemptToken or carrier ~= player or state ~= "CHASE_ACTIVE" then
		return
	end
	state = "SECURED"
	restoreMovement(player)
	disconnectActiveLifecycle()
	destroyAttemptModels()

	if player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not OddlingDisplayService.HasRuntimeTemplate(candidate.RewardSpeciesId)
	then
		failAttempt(player, attemptToken, false, "CANCELLED")
		return
	end
	local installed = ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	local destination = getProgressDestination(player, candidate, installed)
	if not destination then
		warn(string.format("[ODDWORKS][KineticPodRecovery] Progression destination is unavailable for %s.", player.Name))
		failAttempt(player, attemptToken, false, "REWARD_FAILED")
		return
	end
	local preRewardState = PlayerStateService.GetSnapshot(player)
	if not preRewardState then
		failAttempt(player, attemptToken, false, "REWARD_FAILED")
		return
	end
	-- The persisted Voltlet species count is already the narrow first-recovery
	-- fact: only the authoritative 0 -> 1 transition earns the component bonus.
	local shouldGrantSpringLegs = (preRewardState.OwnedOddlings[candidate.RewardSpeciesId] or 0) == 0
	if not PlayerStateService.CanAddOwnedOddling(player, candidate.RewardSpeciesId, candidate.RewardSpeciesCount)
		or (shouldGrantSpringLegs and not ModularPrototypeStateService.CanAddBankedComponent(
			player,
			candidate.RewardComponentId,
			candidate.RewardRarity,
			candidate.RewardCount
		))
	then
		warn(string.format("[ODDWORKS][KineticPodRecovery] Reward preflight failed for %s.", player.Name))
		failAttempt(player, attemptToken, false, "REWARD_FAILED")
		return
	end

	if not PlayerStateService.AddOwnedOddling(player, candidate.RewardSpeciesId, candidate.RewardSpeciesCount) then
		warn(string.format("[ODDWORKS][KineticPodRecovery] Voltlet ownership commit failed for %s.", player.Name))
		failAttempt(player, attemptToken, false, "REWARD_FAILED")
		return
	end

	local springLegsGranted = false
	if shouldGrantSpringLegs then
		springLegsGranted = ModularPrototypeStateService.AddBankedComponent(
			player,
			candidate.RewardComponentId,
			candidate.RewardRarity,
			candidate.RewardCount
		)
		if springLegsGranted then
			springLegsBonusGranted[player] = true
		else
			warn(string.format(
				"[ODDWORKS][KineticPodRecovery] Voltlet committed but first-time SpringLegs bonus failed for %s.",
				player.Name
			))
		end
	end

	RecoveryCarrierRegistry.Release(player, RECOVERY_ACTIVITY_ID)
	carrier = nil
	generation += 1
	local resetToken = generation
	state = "RESETTING"
	setTargetAvailable(false)
	setAvailabilityText(string.format("RECHARGING %ds", math.ceil(candidate.SuccessCooldownSeconds)))
	guidanceStates[player] = if installed then "FURNACE" else "EQUIP"
	local updatedState = PlayerStateService.GetSnapshot(player)
	local ownedCount = if updatedState then updatedState.OwnedOddlings[candidate.RewardSpeciesId] or 0 else 0
	firePlayer(player, {
		Kind = "SECURED",
		OddlingId = candidate.RewardSpeciesId,
		OwnedCount = ownedCount,
		SpringLegsBonusGranted = springLegsGranted,
		ComponentId = candidate.RewardComponentId,
		Rarity = candidate.RewardRarity,
		Count = candidate.RewardCount,
		NextStep = if installed then "FURNACE" else "EQUIP",
		DestinationPosition = destination,
	})
	print(string.format(
		"[ODDWORKS][KineticPodRecovery] %s secured the Kinetic Pod and recovered Voltlet x%d%s.",
		player.Name,
		ownedCount,
		if springLegsGranted then " with first-time SpringLegs bonus" else ""
	))
	scheduleReset(resetToken, candidate.SuccessCooldownSeconds)
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

local function runChase(player: Player, attemptToken: number, candidate: Definition)
	local previousClock = os.clock()
	while generation == attemptToken and carrier == player and state == "CHASE_ACTIVE" do
		local root = getCharacterRootAndHumanoid(player)
		if not root then
			failAttempt(player, attemptToken, false, "CANCELLED")
			return
		end
		local recoveryRuntime = runtime
		if not recoveryRuntime or not ensureAttemptModels(player, root, recoveryRuntime) then
			failAttempt(player, attemptToken, false, "CANCELLED")
			return
		end
		local secureZone = getAssignedPart(player, candidate.SecureZoneName)
		if not secureZone then
			failAttempt(player, attemptToken, false, "CANCELLED")
			return
		end
		if isInsideVolume(root.Position, secureZone) then
			completeSecure(player, attemptToken, candidate)
			return
		end

		local now = os.clock()
		local stage = getStage(now - chaseStartedAt, candidate)
		if stage ~= currentStage then
			currentStage = stage
			firePlayer(player, { Kind = "STAGE", Stage = stage })
		end
		local distance = moveWardenToward(root.Position, candidate.StageSpeeds[stage], math.min(now - previousClock, 0.25))
		previousClock = now
		if distance <= candidate.CatchRadius then
			failAttempt(player, attemptToken, true, "CAUGHT")
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

local function beginAttempt(player: Player)
	local candidate = definition
	local recoveryRuntime = runtime
	if not candidate
		or not recoveryRuntime
		or state ~= "AVAILABLE"
		or carrier ~= nil
		or RecoveryCarrierRegistry.GetActiveActivity(player) ~= nil
		or player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not WorkshopService.GetAssignedPlot(player)
		or not passesAttemptThrottle(player, candidate)
	then
		return
	end
	local root, humanoid = getCharacterRootAndHumanoid(player)
	local secureZone = getAssignedPart(player, candidate.SecureZoneName)
	if not root
		or not humanoid
		or not secureZone
		or (root.Position - recoveryRuntime.InteractionPart.Position).Magnitude > candidate.MaxStealDistance
		or not RecoveryCarrierRegistry.TryAcquire(player, RECOVERY_ACTIVITY_ID)
	then
		return
	end

	generation += 1
	local attemptToken = generation
	state = "ACTIVATING"
	carrier = player
	setTargetAvailable(false)
	setAvailabilityText("IN RECOVERY")
	destroyAttemptModels()
	carryModel = createCarry(player, root)
	wardenModel = createScoutWarden(recoveryRuntime.WardenSpawnMarker)
	wardenCFrame = recoveryRuntime.WardenSpawnMarker.CFrame
	local springLegsActive = applySpringLegsMovement(player, humanoid, candidate)
	activeDeathConnection = humanoid.Died:Connect(function()
		failAttempt(player, attemptToken, false, "CANCELLED")
	end)
	activeCharacterRemovingConnection = player.CharacterRemoving:Connect(function()
		failAttempt(player, attemptToken, false, "CANCELLED")
	end)
	firePlayer(player, {
		Kind = "ACTIVATING",
		HeadStartSeconds = candidate.HeadStartSeconds,
		DestinationPosition = secureZone.Position,
		SpringLegsActive = springLegsActive,
	})
	print(string.format("[ODDWORKS][KineticPodRecovery] %s stole the Kinetic Pod; Scout Warden activating.", player.Name))
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
			or not getAssignedPart(player, candidate.SecureZoneName)
			or not ensureAttemptModels(player, activeRoot, recoveryRuntime)
		then
			failAttempt(player, attemptToken, false, "CANCELLED")
			return
		end
		if springLegsEligibleForAttempt then
			verifySpringLegsMovement(player, activeHumanoid)
		end
		setWardenAlarm(true)
		chaseStartedAt = os.clock()
		currentStage = 1
		state = "CHASE_ACTIVE"
		firePlayer(player, { Kind = "CHASE_STARTED", Stage = 1 })
		task.spawn(runChase, player, attemptToken, candidate)
	end)
end

local function handleModularStateChanged(player: Player)
	if carrier == player
		and springLegsEligibleForAttempt
		and (state == "ACTIVATING" or state == "CHASE_ACTIVE")
		and not ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	then
		restoreMovement(player)
	end
	if springLegsBonusGranted[player] then
		sendProgressGuidance(player, false)
	end
end

local function clearPlayer(player: Player)
	lastAttemptTimes[player] = nil
	springLegsBonusGranted[player] = nil
	guidanceStates[player] = nil
	if carrier == player then
		failAttempt(player, generation, false, "CANCELLED")
	else
		restoreMovement(player)
		RecoveryCarrierRegistry.Release(player, RECOVERY_ACTIVITY_ID)
	end
end

local function createSiteLabel(marker: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "KineticSiteLabel"
	billboard.Adornee = marker
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Size = UDim2.fromOffset(180, 52)
	billboard.Parent = marker
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 40, 44)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = "KINETIC POD\nLOW SECURITY - AVAILABLE"
	label.TextColor3 = Color3.fromRGB(99, 231, 255)
	label.TextSize = 14
	label.TextWrapped = true
	label.Parent = billboard
	return label
end

local function discoverRuntime(candidate: Definition): RecoveryRuntime
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local targetModel = requireChildOfClass(world, candidate.WorldModelName, "Model") :: Model
	local interactionPart = requireChildOfClass(targetModel, candidate.InteractionPartName, "BasePart") :: BasePart
	local prompt = requireChildOfClass(interactionPart, "Prompt", "ProximityPrompt") :: ProximityPrompt
	local wardenSpawnMarker = requireChildOfClass(targetModel, candidate.WardenSpawnMarkerName, "BasePart") :: BasePart
	local siteMarker = requireChildOfClass(targetModel, candidate.SiteMarkerName, "BasePart") :: BasePart
	local furnaceModel = requireChildOfClass(world, candidate.FurnaceWorldModelName, "Model")
	local furnaceInteractionPart = requireChildOfClass(furnaceModel, candidate.FurnaceInteractionPartName, "BasePart") :: BasePart
	local availabilityLabel = createSiteLabel(siteMarker)

	local presentation: { [BasePart]: PartPresentation } = {}
	for _, descendant in ipairs(targetModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= wardenSpawnMarker and descendant ~= siteMarker then
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
		FurnaceInteractionPart = furnaceInteractionPart,
		AvailabilityLabel = availabilityLabel,
	}
end

function KineticPodRecoveryService.GetDiagnosticSnapshot(player: Player): { [string]: any }
	return {
		Phase = state,
		AttemptGeneration = generation,
		IsCarrier = carrier == player,
		CooldownRemaining = if state == "RESETTING" then math.max(0, cooldownEndsAt - os.clock()) else 0,
		SpringLegsBonusGranted = springLegsBonusGranted[player] == true,
	}
end

function KineticPodRecoveryService.Start()
	if started then
		return
	end
	started = true
	local candidate = KineticPodRecoveryConfig.GetDefinition()
	validateDefinition(candidate)
	definition = candidate
	runtime = discoverRuntime(candidate)

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	stateRemote = requireChildOfClass(network, "KineticPodRecoveryState", "RemoteEvent") :: RemoteEvent
	local runtimeRoot = getOrCreateFolder(Workspace, RUNTIME_ROOT_NAME)
	runtimeFolder = getOrCreateFolder(runtimeRoot, RUNTIME_FOLDER_NAME)
	for _, child in ipairs((runtimeFolder :: Folder):GetChildren()) do
		child:Destroy()
	end
	setTargetAvailable(true)
	setAvailabilityText("AVAILABLE")
	local recoveryRuntime = runtime :: RecoveryRuntime
	recoveryRuntime.Prompt.Triggered:Connect(beginAttempt)
	ModularPrototypeStateService.ObserveStateChanged(handleModularStateChanged)
	ModularPrototypeStateService.ObserveStateRemoved(clearPlayer)
	PlayerStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)
	print("[ODDWORKS][KineticPodRecovery] Low-security Kinetic Pod recovery started.")
end

return KineticPodRecoveryService
