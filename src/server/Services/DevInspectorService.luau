--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent
local ConstructCapabilityResolver = require(Services:WaitForChild("ConstructCapabilityResolver"))
local FurnacePodChaseService = require(Services:WaitForChild("FurnacePodChaseService"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local PersistenceService = require(Services:WaitForChild("PersistenceService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local PrototypeConstructRuntimeService = require(Services:WaitForChild("PrototypeConstructRuntimeService"))
local SignatureDiscoveryService = require(Services:WaitForChild("SignatureDiscoveryService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type SpeedOverride = {
	Humanoid: Humanoid,
	BaselineWalkSpeed: number,
	OverrideWalkSpeed: number,
}

local DevInspectorService = {}

local REMOTE_FOLDER_NAME = "ODDWORKSDevInspector"
local SNAPSHOT_REQUEST_NAME = "SnapshotRequest"
local SNAPSHOT_NAME = "Snapshot"
local SET_SPEED_NAME = "SetWalkSpeedRequest"
local RESET_SPEED_NAME = "ResetWalkSpeedRequest"
local MIN_WALK_SPEED = 4
local MAX_WALK_SPEED = 50
local SNAPSHOT_INTERVAL_SECONDS = 0.2
local MUTATION_INTERVAL_SECONDS = 0.5
local MAX_COMPONENT_SUMMARY_BUCKETS = 6

local speedOverrides: { [Player]: SpeedOverride } = {}
local lastSnapshotRequests: { [Player]: number } = {}
local lastMutationRequests: { [Player]: number } = {}
local snapshotRemote: RemoteEvent? = nil
local started = false

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function getLiveHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

local function isDevelopmentContext(player: Player): boolean
	return RunService:IsStudio() and player.Parent == Players
end

local function isMutationAuthorized(player: Player): boolean
	return isDevelopmentContext(player)
		and PlayerStateService.HasState(player)
		and ModularPrototypeStateService.HasState(player)
end

local function passesThrottle(requests: { [Player]: number }, player: Player, interval: number): boolean
	local now = os.clock()
	local previous = requests[player]
	if previous and now - previous < interval then
		return false
	end
	requests[player] = now
	return true
end

local function getOrCreateRemoteFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	if existing then
		if not existing:IsA("Folder") then
			error(string.format("[ODDWORKS][DevInspector] %s must be a Folder.", existing:GetFullName()))
		end
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = REMOTE_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function getOrCreateRemote(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing then
		if not existing:IsA("RemoteEvent") then
			error(string.format("[ODDWORKS][DevInspector] %s must be a RemoteEvent.", existing:GetFullName()))
		end
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function summarizeComponents(componentCounts: ModularPrototypeStateService.ComponentCounts): string
	local entries: { string } = {}
	local total = 0
	for componentId, rarityCounts in pairs(componentCounts) do
		for rarity, count in pairs(rarityCounts) do
			if count > 0 then
				total += count
				table.insert(entries, string.format("%s[%s] x%d", componentId, rarity, count))
			end
		end
	end
	table.sort(entries)
	if #entries == 0 then
		return "Empty"
	end
	local visible: { string } = {}
	for index = 1, math.min(#entries, MAX_COMPONENT_SUMMARY_BUCKETS) do
		table.insert(visible, entries[index])
	end
	local suffix = if #entries > #visible then string.format("; +%d buckets", #entries - #visible) else ""
	return string.format("Total %d: %s%s", total, table.concat(visible, "; "), suffix)
end

local function buildSnapshot(player: Player, actionMessage: string?, actionSucceeded: boolean?): { [string]: any }?
	if not isDevelopmentContext(player) then
		return nil
	end
	local playerState = PlayerStateService.GetSnapshot(player)
	local modularState = ModularPrototypeStateService.GetSnapshot(player)

	local humanoid = getLiveHumanoid(player)
	local construct = if modularState then modularState.PrototypeConstruct else nil
	local chase = FurnacePodChaseService.GetDiagnosticSnapshot(player)
	local constructRuntime = PrototypeConstructRuntimeService.GetDiagnosticSnapshot(player)
	local signatureRuntime = SignatureDiscoveryService.GetDiagnosticSnapshot(player)
	local persistenceStatus = PersistenceService.GetStatus(player)
	local speedOverride = speedOverrides[player]
	if speedOverride and speedOverride.Humanoid.Parent == nil then
		speedOverrides[player] = nil
		speedOverride = nil
	end

	local currentWalkSpeed = if humanoid then humanoid.WalkSpeed else nil
	local baselineWalkSpeed = chase.MovementBaselineWalkSpeed
	if baselineWalkSpeed == nil then
		baselineWalkSpeed = if speedOverride then speedOverride.BaselineWalkSpeed else currentWalkSpeed
	end
	local hasSpringLegs = ConstructCapabilityResolver.HasSpringLegsChaseCapability(player)
	local expectedWalkSpeed = chase.ExpectedSpringLegsWalkSpeed
	if expectedWalkSpeed == nil and hasSpringLegs and baselineWalkSpeed ~= nil then
		expectedWalkSpeed = baselineWalkSpeed * chase.ConfiguredSpringLegsMultiplier
	end

	local constructView: { [string]: string }? = nil
	if construct then
		constructView = {
			FrameId = construct.FrameId,
			HeadComponentId = construct.Head.ComponentId,
			ArmComponentId = construct.Arm.ComponentId,
			LegsComponentId = construct.Legs.ComponentId,
		}
	end

	return {
		PlayerName = player.Name,
		UserId = player.UserId,
		PlayerStateReady = PlayerStateService.HasState(player),
		ModularStateReady = ModularPrototypeStateService.HasState(player),
		PersistenceStatus = persistenceStatus,
		ProfileSessionActive = persistenceStatus == "Ready",
		CharacterPresent = humanoid ~= nil,
		Health = if humanoid then humanoid.Health else nil,
		MaxHealth = if humanoid then humanoid.MaxHealth else nil,
		WalkSpeed = currentWalkSpeed,
		JumpMode = if humanoid then (if humanoid.UseJumpPower then "JumpPower" else "JumpHeight") else nil,
		JumpValue = if humanoid then (if humanoid.UseJumpPower then humanoid.JumpPower else humanoid.JumpHeight) else nil,
		Construct = constructView,
		DetectStrangeSignals = ConstructCapabilityResolver.CanDetectStrangeSignals(player),
		SpringLegsChaseCapability = hasSpringLegs,
		SpringLegsEffectApplied = chase.SpringLegsEffectApplied,
		SpringLegsApplicationRecord = chase.SpringLegsApplicationRecord,
		SpringLegsSpeedMatchesExpected = chase.SpringLegsSpeedMatchesExpected,
		BaselineWalkSpeed = baselineWalkSpeed,
		ConfiguredSpringLegsMultiplier = chase.ConfiguredSpringLegsMultiplier,
		ExpectedSpringLegsWalkSpeed = expectedWalkSpeed,
		SpringLegsEligible = chase.SpringLegsEligible,
		ChasePhase = chase.Phase,
		ChaseAttemptGeneration = chase.AttemptGeneration,
		IsCarrier = chase.IsCarrier,
		WardenStage = chase.WardenStage,
		CarryRuntimePresent = chase.CarryRuntimePresent,
		WardenRuntimePresent = chase.WardenRuntimePresent,
		AssignedPlotId = WorkshopService.GetAssignedPlotId(player) or (if playerState then playerState.AssignedPlotId else nil),
		ConstructRuntimeExpected = constructRuntime.Expected,
		ConstructRuntimePresent = constructRuntime.ModelPresent,
		ConstructRuntimeCount = constructRuntime.ModelCount,
		KilnbackDiscovered = signatureRuntime.Discovered,
		KilnbackRuntimePresent = signatureRuntime.RuntimePresent,
		KilnbackRuntimeCount = signatureRuntime.RuntimeCount,
		Scrap = if playerState then playerState.Scrap else nil,
		Hype = if playerState then playerState.Hype else nil,
		WorkshopLevel = if playerState then playerState.WorkshopLevel else nil,
		BankedSummary = if modularState then summarizeComponents(modularState.BankedComponents) else "Unavailable",
		UnbankedSummary = if modularState then summarizeComponents(modularState.UnbankedComponents) else "Unavailable",
		DevWalkSpeedOverride = speedOverride ~= nil,
		DevOverrideWalkSpeed = if speedOverride then speedOverride.OverrideWalkSpeed else nil,
		DevOverrideBaselineWalkSpeed = if speedOverride then speedOverride.BaselineWalkSpeed else nil,
		ActionMessage = actionMessage,
		ActionSucceeded = actionSucceeded,
	}
end

local function sendSnapshot(player: Player, actionMessage: string?, actionSucceeded: boolean?)
	local remote = snapshotRemote
	local snapshot = buildSnapshot(player, actionMessage, actionSucceeded)
	if remote and snapshot then
		remote:FireClient(player, snapshot)
	end
end

local function isActiveCarrier(player: Player): boolean
	local chase = FurnacePodChaseService.GetDiagnosticSnapshot(player)
	return chase.IsCarrier and (chase.Phase == "ACTIVATING" or chase.Phase == "CHASE_ACTIVE")
end

local function handleSnapshotRequest(player: Player, ...: any)
	if select("#", ...) ~= 0
		or not isDevelopmentContext(player)
		or not passesThrottle(lastSnapshotRequests, player, SNAPSHOT_INTERVAL_SECONDS)
	then
		return
	end
	sendSnapshot(player, nil, nil)
end

local function handleSetWalkSpeed(player: Player, requestedWalkSpeed: any, ...: any)
	if select("#", ...) ~= 0
		or not isMutationAuthorized(player)
		or not passesThrottle(lastMutationRequests, player, MUTATION_INTERVAL_SECONDS)
	then
		return
	end
	if not isFiniteNumber(requestedWalkSpeed)
		or requestedWalkSpeed < MIN_WALK_SPEED
		or requestedWalkSpeed > MAX_WALK_SPEED
	then
		sendSnapshot(player, string.format("WalkSpeed must be between %d and %d.", MIN_WALK_SPEED, MAX_WALK_SPEED), false)
		return
	end
	if isActiveCarrier(player) then
		sendSnapshot(player, "WalkSpeed override rejected during an active chase.", false)
		return
	end
	local humanoid = getLiveHumanoid(player)
	if not humanoid then
		sendSnapshot(player, "WalkSpeed override requires a living character.", false)
		return
	end

	local walkSpeed = requestedWalkSpeed :: number
	local existing = speedOverrides[player]
	local baseline = if existing and existing.Humanoid == humanoid then existing.BaselineWalkSpeed else humanoid.WalkSpeed
	humanoid.WalkSpeed = walkSpeed
	speedOverrides[player] = {
		Humanoid = humanoid,
		BaselineWalkSpeed = baseline,
		OverrideWalkSpeed = walkSpeed,
	}
	print(string.format("[ODDWORKS][DevInspector] %s (%d) set local WalkSpeed override to %.2f.", player.Name, player.UserId, walkSpeed))
	sendSnapshot(player, string.format("DEV WalkSpeed override set to %.2f.", walkSpeed), true)
end

local function handleResetWalkSpeed(player: Player, ...: any)
	if select("#", ...) ~= 0
		or not isMutationAuthorized(player)
		or not passesThrottle(lastMutationRequests, player, MUTATION_INTERVAL_SECONDS)
	then
		return
	end
	if isActiveCarrier(player) then
		sendSnapshot(player, "WalkSpeed reset rejected during an active chase.", false)
		return
	end
	local existing = speedOverrides[player]
	if not existing then
		sendSnapshot(player, "No DEV WalkSpeed override is active.", true)
		return
	end
	if existing.Humanoid.Parent ~= nil then
		existing.Humanoid.WalkSpeed = existing.BaselineWalkSpeed
	end
	speedOverrides[player] = nil
	print(string.format("[ODDWORKS][DevInspector] %s (%d) reset the local WalkSpeed override.", player.Name, player.UserId))
	sendSnapshot(player, "DEV WalkSpeed override reset.", true)
end

local function clearPlayer(player: Player)
	local existing = speedOverrides[player]
	if existing and existing.Humanoid.Parent ~= nil then
		existing.Humanoid.WalkSpeed = existing.BaselineWalkSpeed
	end
	speedOverrides[player] = nil
	lastSnapshotRequests[player] = nil
	lastMutationRequests[player] = nil
end

local function bindPlayer(player: Player)
	player.CharacterRemoving:Connect(function()
		speedOverrides[player] = nil
	end)
end

function DevInspectorService.Start()
	if started then
		return
	end
	started = true
	if not RunService:IsStudio() then
		return
	end

	local folder = getOrCreateRemoteFolder()
	local snapshotRequest = getOrCreateRemote(folder, SNAPSHOT_REQUEST_NAME)
	snapshotRemote = getOrCreateRemote(folder, SNAPSHOT_NAME)
	local setSpeedRequest = getOrCreateRemote(folder, SET_SPEED_NAME)
	local resetSpeedRequest = getOrCreateRemote(folder, RESET_SPEED_NAME)

	snapshotRequest.OnServerEvent:Connect(handleSnapshotRequest)
	setSpeedRequest.OnServerEvent:Connect(handleSetWalkSpeed)
	resetSpeedRequest.OnServerEvent:Connect(handleResetWalkSpeed)
	Players.PlayerAdded:Connect(bindPlayer)
	PlayerStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	print(string.format("[ODDWORKS][DevInspector] Studio-only inspector ready; WalkSpeed range is %d-%d.", MIN_WALK_SPEED, MAX_WALK_SPEED))
end

return DevInspectorService
