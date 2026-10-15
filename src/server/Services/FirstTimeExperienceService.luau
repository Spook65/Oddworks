--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][FTUE] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local KineticPodRecoveryConfig = require(Config:WaitForChild("KineticPodRecoveryConfig"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type Stage =
	"RECOVER_KINETIC"
	| "KINETIC_ACTIVE"
	| "WAITING_FOR_HYPE"
	| "EQUIP_SPRINGLEGS"
	| "ADVANCED_AVAILABLE"
	| "RETURNING_PLAYER"

type TimingState = {
	SessionStartedAt: number,
	FirstObjectiveActiveAt: number?,
	FirstKineticInteractionAt: number?,
	FirstKineticTheftAt: number?,
	FirstKineticSecureAt: number?,
	FirstVoltletRevealAt: number?,
	FirstHypeExplanationAt: number?,
	FirstAssemblerOpenAt: number?,
	FirstSpringLegsInstallAt: number?,
}

type FTUEState = {
	Stage: Stage,
	ReturningPlayer: boolean,
	FirstKineticCompleted: boolean,
	FirstHypeExplanationSeen: boolean,
	Generation: number,
	Timings: TimingState,
}

local FirstTimeExperienceService = {}

local STATE_REMOTE_NAME = "FirstTimeExperienceState"
local REQUEST_REMOTE_NAME = "FirstTimeExperienceRequest"
local REQUEST_INTERVAL_SECONDS = 0.25
local VOLTLET_REVEAL_DELAY_SECONDS = 1.2
local POST_HYPE_GUIDANCE_DELAY_SECONDS = 3.2
local POST_INSTALL_TEASE_DELAY_SECONDS = 2.6

local states: { [Player]: FTUEState } = {}
local lastRequestTimes: { [Player]: number } = {}
local stateRemote: RemoteEvent? = nil
local kineticTargetPosition: Vector3? = nil
local furnaceTargetPosition: Vector3? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][FTUE] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][FTUE] %s.%s must be a %s, but found %s.",
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

local function elapsed(timestamp: number?, startedAt: number): number?
	return if timestamp then math.max(0, timestamp - startedAt) else nil
end

local function firePlayer(player: Player, payload: { [string]: any })
	local remote = stateRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

local function getAssemblerPosition(player: Player): Vector3?
	local definition = KineticPodRecoveryConfig.GetDefinition()
	local plot = WorkshopService.GetAssignedPlot(player)
	local assembler = if plot then plot:FindFirstChild(definition.AssemblerName) else nil
	return if assembler and assembler:IsA("BasePart") then assembler.Position else nil
end

local function hasSpringLegsInstalled(player: Player): boolean
	local snapshot = ModularPrototypeStateService.GetSnapshot(player)
	local construct = if snapshot then snapshot.PrototypeConstruct else nil
	return construct ~= nil and construct.Legs.ComponentId == "SpringLegs"
end

local function sendKineticObjective(player: Player)
	local destination = kineticTargetPosition
	if destination then
		firePlayer(player, {
			Kind = "KINETIC_OBJECTIVE",
			DestinationPosition = destination,
		})
	end
end

local function sendAssemblerGuidance(player: Player)
	local destination = getAssemblerPosition(player)
	if destination then
		firePlayer(player, {
			Kind = "SPRINGLEGS_GUIDANCE",
			DestinationPosition = destination,
		})
	end
end

local function sendAdvancedGuidance(player: Player)
	local destination = furnaceTargetPosition
	if destination then
		firePlayer(player, {
			Kind = "ADVANCED_GUIDANCE",
			DestinationPosition = destination,
		})
	end
end

local function replayCurrentGuidance(player: Player, state: FTUEState)
	if state.ReturningPlayer then
		return
	end
	if state.Stage == "RECOVER_KINETIC" then
		sendKineticObjective(player)
	elseif state.Stage == "EQUIP_SPRINGLEGS" then
		sendAssemblerGuidance(player)
	elseif state.Stage == "ADVANCED_AVAILABLE" then
		sendAdvancedGuidance(player)
	end
end

local function initializePlayer(player: Player)
	if states[player] or player.Parent ~= Players then
		return
	end
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot or not snapshot.AssignedPlotId then
		return
	end

	local now = os.clock()
	local returningPlayer = (snapshot.OwnedOddlings.Voltlet or 0) > 0
		or (snapshot.OwnedOddlings.Kilnback or 0) > 0
	local state: FTUEState = {
		Stage = if returningPlayer then "RETURNING_PLAYER" else "RECOVER_KINETIC",
		ReturningPlayer = returningPlayer,
		FirstKineticCompleted = false,
		FirstHypeExplanationSeen = false,
		Generation = 1,
		Timings = {
			SessionStartedAt = now,
			FirstObjectiveActiveAt = if returningPlayer then nil else now,
			FirstKineticInteractionAt = nil,
			FirstKineticTheftAt = nil,
			FirstKineticSecureAt = nil,
			FirstVoltletRevealAt = nil,
			FirstHypeExplanationAt = nil,
			FirstAssemblerOpenAt = nil,
			FirstSpringLegsInstallAt = nil,
		},
	}
	states[player] = state
	if not returningPlayer then
		sendKineticObjective(player)
	end
end

local function passesRequestThrottle(player: Player): boolean
	local now = os.clock()
	local previous = lastRequestTimes[player]
	if previous and now - previous < REQUEST_INTERVAL_SECONDS then
		return false
	end
	lastRequestTimes[player] = now
	return true
end

local function handleRequest(player: Player, ...: any)
	if select("#", ...) ~= 0
		or player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not passesRequestThrottle(player)
	then
		return
	end
	initializePlayer(player)
	local state = states[player]
	if state then
		replayCurrentGuidance(player, state)
	end
end

local function cleanupPlayer(player: Player)
	local state = states[player]
	if state and not state.ReturningPlayer then
		local timings = state.Timings
		print(string.format(
			"[ODDWORKS][FTUE] %s session summary: stage=%s objective=%.2f theft=%s secure=%s hype=%s assembler=%s install=%s",
			player.Name,
			state.Stage,
			elapsed(timings.FirstObjectiveActiveAt, timings.SessionStartedAt) or -1,
			tostring(elapsed(timings.FirstKineticTheftAt, timings.SessionStartedAt)),
			tostring(elapsed(timings.FirstKineticSecureAt, timings.SessionStartedAt)),
			tostring(elapsed(timings.FirstHypeExplanationAt, timings.SessionStartedAt)),
			tostring(elapsed(timings.FirstAssemblerOpenAt, timings.SessionStartedAt)),
			tostring(elapsed(timings.FirstSpringLegsInstallAt, timings.SessionStartedAt))
		))
	end
	states[player] = nil
	lastRequestTimes[player] = nil
end

function FirstTimeExperienceService.IsManaging(player: Player): boolean
	local state = states[player]
	return state ~= nil and not state.ReturningPlayer and state.Stage ~= "ADVANCED_AVAILABLE"
end

function FirstTimeExperienceService.RecordKineticTheft(player: Player)
	local state = states[player]
	if not state or state.ReturningPlayer or state.FirstKineticCompleted then
		return
	end
	local now = os.clock()
	state.Timings.FirstKineticInteractionAt = state.Timings.FirstKineticInteractionAt or now
	state.Timings.FirstKineticTheftAt = state.Timings.FirstKineticTheftAt or now
	state.Stage = "KINETIC_ACTIVE"
	state.Generation += 1
end

function FirstTimeExperienceService.RecordKineticFailure(player: Player, retryDelaySeconds: number)
	local state = states[player]
	if not state or state.ReturningPlayer or state.FirstKineticCompleted then
		return
	end
	state.Stage = "RECOVER_KINETIC"
	state.Generation += 1
	local generation = state.Generation
	task.delay(math.max(0, retryDelaySeconds), function()
		local current = states[player]
		if current == state
			and current.Generation == generation
			and current.Stage == "RECOVER_KINETIC"
			and player.Parent == Players
		then
			sendKineticObjective(player)
		end
	end)
end

function FirstTimeExperienceService.RecordKineticSecure(player: Player): boolean
	local state = states[player]
	if not state or state.ReturningPlayer or state.FirstKineticCompleted then
		return false
	end
	local now = os.clock()
	state.FirstKineticCompleted = true
	state.Timings.FirstKineticSecureAt = state.Timings.FirstKineticSecureAt or now
	state.Stage = "WAITING_FOR_HYPE"
	state.Generation += 1
	task.delay(VOLTLET_REVEAL_DELAY_SECONDS, function()
		local current = states[player]
		if current == state
			and current.FirstKineticCompleted
			and player.Parent == Players
		then
			current.Timings.FirstVoltletRevealAt = current.Timings.FirstVoltletRevealAt or os.clock()
		end
	end)
	return true
end

function FirstTimeExperienceService.RecordHypeProduced(player: Player, amount: number)
	local state = states[player]
	if not state
		or state.ReturningPlayer
		or not state.FirstKineticCompleted
		or state.FirstHypeExplanationSeen
		or amount <= 0
	then
		return
	end
	state.FirstHypeExplanationSeen = true
	state.Timings.FirstHypeExplanationAt = os.clock()
	state.Generation += 1
	local generation = state.Generation
	firePlayer(player, {
		Kind = "FIRST_HYPE",
		Amount = amount,
	})

	task.delay(POST_HYPE_GUIDANCE_DELAY_SECONDS, function()
		local current = states[player]
		if current ~= state or current.Generation ~= generation or player.Parent ~= Players then
			return
		end
		if hasSpringLegsInstalled(player) then
			current.Stage = "ADVANCED_AVAILABLE"
			sendAdvancedGuidance(player)
		else
			current.Stage = "EQUIP_SPRINGLEGS"
			sendAssemblerGuidance(player)
		end
	end)
end

function FirstTimeExperienceService.RecordAssemblerOpened(player: Player)
	local state = states[player]
	if state and not state.ReturningPlayer then
		state.Timings.FirstAssemblerOpenAt = state.Timings.FirstAssemblerOpenAt or os.clock()
	end
end

function FirstTimeExperienceService.RecordAssemblySuccess(player: Player)
	local state = states[player]
	if not state
		or state.ReturningPlayer
		or not state.FirstKineticCompleted
		or state.Timings.FirstSpringLegsInstallAt ~= nil
		or not hasSpringLegsInstalled(player)
	then
		return
	end
	state.Timings.FirstSpringLegsInstallAt = state.Timings.FirstSpringLegsInstallAt or os.clock()
	state.Generation += 1
	local generation = state.Generation
	firePlayer(player, { Kind = "SPRINGLEGS_INSTALLED" })
	if not state.FirstHypeExplanationSeen then
		state.Stage = "WAITING_FOR_HYPE"
		return
	end
	state.Stage = "ADVANCED_AVAILABLE"
	task.delay(POST_INSTALL_TEASE_DELAY_SECONDS, function()
		local current = states[player]
		if current == state
			and current.Generation == generation
			and current.Stage == "ADVANCED_AVAILABLE"
			and player.Parent == Players
		then
			sendAdvancedGuidance(player)
		end
	end)
end

function FirstTimeExperienceService.GetDiagnosticSnapshot(player: Player): { [string]: any }
	local state = states[player]
	if not state then
		return {
			Stage = "NOT_READY",
			ElapsedSessionSeconds = 0,
			ReturningPlayer = false,
			FirstKineticCompleted = false,
			FirstHypeExplanationSeen = false,
			SpringLegsGuidanceActive = false,
			SpringLegsInstalled = hasSpringLegsInstalled(player),
		}
	end
	local timings = state.Timings
	return {
		Stage = state.Stage,
		ElapsedSessionSeconds = math.max(0, os.clock() - timings.SessionStartedAt),
		ReturningPlayer = state.ReturningPlayer,
		FirstKineticCompleted = state.FirstKineticCompleted,
		FirstHypeExplanationSeen = state.FirstHypeExplanationSeen,
		SpringLegsGuidanceActive = state.Stage == "EQUIP_SPRINGLEGS",
		SpringLegsInstalled = hasSpringLegsInstalled(player),
		FirstObjectiveSeconds = elapsed(timings.FirstObjectiveActiveAt, timings.SessionStartedAt),
		FirstKineticInteractionSeconds = elapsed(timings.FirstKineticInteractionAt, timings.SessionStartedAt),
		FirstKineticTheftSeconds = elapsed(timings.FirstKineticTheftAt, timings.SessionStartedAt),
		FirstSecureSeconds = elapsed(timings.FirstKineticSecureAt, timings.SessionStartedAt),
		FirstVoltletRevealSeconds = elapsed(timings.FirstVoltletRevealAt, timings.SessionStartedAt),
		FirstHypeExplanationSeconds = elapsed(timings.FirstHypeExplanationAt, timings.SessionStartedAt),
		FirstAssemblerOpenSeconds = elapsed(timings.FirstAssemblerOpenAt, timings.SessionStartedAt),
		FirstSpringLegsInstallSeconds = elapsed(timings.FirstSpringLegsInstallAt, timings.SessionStartedAt),
	}
end

function FirstTimeExperienceService.Start()
	if started then
		return
	end
	started = true
	local definition = KineticPodRecoveryConfig.GetDefinition()
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local kineticModel = requireChildOfClass(world, definition.WorldModelName, "Model")
	local kineticPart = requireChildOfClass(kineticModel, definition.InteractionPartName, "BasePart") :: BasePart
	local furnaceModel = requireChildOfClass(world, definition.FurnaceWorldModelName, "Model")
	local furnacePart = requireChildOfClass(furnaceModel, definition.FurnaceInteractionPartName, "BasePart") :: BasePart
	kineticTargetPosition = kineticPart.Position
	furnaceTargetPosition = furnacePart.Position

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	stateRemote = requireChildOfClass(network, STATE_REMOTE_NAME, "RemoteEvent") :: RemoteEvent
	local requestRemote = requireChildOfClass(network, REQUEST_REMOTE_NAME, "RemoteEvent") :: RemoteEvent
	requestRemote.OnServerEvent:Connect(handleRequest)
	PlayerStateService.ObserveStateChanged(initializePlayer)
	PlayerStateService.ObserveStateRemoved(cleanupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end
	print("[ODDWORKS][FTUE] Contextual first-session guidance started.")
end

return FirstTimeExperienceService
