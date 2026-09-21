--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][ActiveSalvage] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local Components = require(Config:WaitForChild("Components"))
local ActiveSalvageConfig = require(Config:WaitForChild("ActiveSalvageConfig"))

type EncounterStatus = "AVAILABLE" | "ACTIVE" | "COOLDOWN"

type WeightedComponent = {
	ComponentId: string,
	Weight: number,
}

type WeightedRarity = {
	Rarity: string,
	Weight: number,
}

type EncounterDefinition = {
	EncounterId: string,
	StageCount: number,
	StageDurationSeconds: number,
	WindowStartSeconds: number,
	WindowEndSeconds: number,
	InterstageDelaySeconds: number,
	FailureResetSeconds: number,
	SuccessCooldownSeconds: number,
	MaxValidDistance: number,
	InputMinimumIntervalSeconds: number,
	RewardQuantity: number,
	ComponentWeights: { WeightedComponent },
	RarityWeights: { WeightedRarity },
}

type EncounterRuntime = {
	Definition: EncounterDefinition,
	Model: Model,
	InteractionPart: BasePart,
	Prompt: ProximityPrompt,
	SignalLight: BasePart?,
	Status: EncounterStatus,
	Participant: Player?,
	Stage: number,
	StageOpen: boolean,
	WindowStartTime: number,
	WindowEndTime: number,
	LifecycleToken: number,
}

local ActiveSalvageEncounterService = {}

local EXPECTED_ENCOUNTER_ID = "JammedSalvageWreck"
local MAX_ENCOUNTER_ID_LENGTH = 40

local encounter: EncounterRuntime? = nil
local extractionInputRequest: RemoteEvent? = nil
local activeSalvageState: RemoteEvent? = nil
local lastInputTimes: { [Player]: number } = {}
local random = Random.new()
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][ActiveSalvage] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][ActiveSalvage] %s.%s must be a %s, but found %s.",
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

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function isPlayerInRange(player: Player, runtime: EncounterRuntime): boolean
	local root = getCharacterRoot(player)
	return root ~= nil
		and (root.Position - runtime.InteractionPart.Position).Magnitude <= runtime.Definition.MaxValidDistance
end

local function setVisualState(runtime: EncounterRuntime, status: EncounterStatus)
	runtime.Status = status
	runtime.Prompt.Enabled = status == "AVAILABLE"

	local light = runtime.SignalLight
	if light then
		if status == "AVAILABLE" then
			light.Color = Color3.fromRGB(90, 230, 150)
		elseif status == "ACTIVE" then
			light.Color = Color3.fromRGB(255, 195, 70)
		else
			light.Color = Color3.fromRGB(220, 75, 65)
		end
	end
end

local function fireParticipant(runtime: EncounterRuntime, payload: { [string]: any })
	local player = runtime.Participant
	local remote = activeSalvageState
	if player and player.Parent == Players and remote then
		remote:FireClient(player, payload)
	end
end

local function validateDefinition(definition: EncounterDefinition)
	if definition.StageCount ~= 3
		or definition.StageDurationSeconds <= 0
		or definition.WindowStartSeconds <= 0
		or definition.WindowStartSeconds >= definition.WindowEndSeconds
		or definition.WindowEndSeconds >= definition.StageDurationSeconds
		or definition.MaxValidDistance <= 0
		or definition.RewardQuantity <= 0
	then
		error("[ODDWORKS][ActiveSalvage] Encounter timing/reward configuration is invalid.")
	end

	for _, entry in ipairs(definition.ComponentWeights) do
		if not Components.GetDefinition(entry.ComponentId) or entry.Weight <= 0 or math.floor(entry.Weight) ~= entry.Weight then
			error(string.format("[ODDWORKS][ActiveSalvage] Invalid component reward entry: %s", entry.ComponentId))
		end
	end
	for _, entry in ipairs(definition.RarityWeights) do
		if not Components.IsValidRarity(entry.Rarity) or entry.Weight <= 0 or math.floor(entry.Weight) ~= entry.Weight then
			error(string.format("[ODDWORKS][ActiveSalvage] Invalid rarity reward entry: %s", entry.Rarity))
		end
	end
end

local function chooseWeightedComponent(entries: { WeightedComponent }): string?
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		totalWeight += entry.Weight
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = random:NextInteger(1, totalWeight)
	local cumulative = 0
	for _, entry in ipairs(entries) do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry.ComponentId
		end
	end
	return nil
end

local function chooseWeightedRarity(entries: { WeightedRarity }): string?
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		totalWeight += entry.Weight
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = random:NextInteger(1, totalWeight)
	local cumulative = 0
	for _, entry in ipairs(entries) do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry.Rarity
		end
	end
	return nil
end

local function resetAvailable(runtime: EncounterRuntime, token: number)
	if encounter ~= runtime or runtime.LifecycleToken ~= token or runtime.Status ~= "COOLDOWN" then
		return
	end

	runtime.Participant = nil
	runtime.Stage = 0
	runtime.StageOpen = false
	setVisualState(runtime, "AVAILABLE")
end

-- Failure invalidates only this pending reward. Existing unbanked haul and all
-- production state remain untouched for the forgiving first encounter.
local function failEncounter(runtime: EncounterRuntime, code: string)
	if runtime.Status ~= "ACTIVE" then
		return
	end

	local token = runtime.LifecycleToken
	fireParticipant(runtime, {
		Kind = "FAILED",
		EncounterId = runtime.Definition.EncounterId,
		Code = code,
		RetryAfterSeconds = runtime.Definition.FailureResetSeconds,
	})
	print(
		string.format(
			"[ODDWORKS][ActiveSalvage] %s failed %s at stage %d (%s).",
			runtime.Participant and runtime.Participant.Name or "unknown player",
			runtime.Definition.EncounterId,
			runtime.Stage,
			code
		)
	)
	runtime.StageOpen = false
	runtime.Participant = nil
	setVisualState(runtime, "COOLDOWN")
	task.delay(runtime.Definition.FailureResetSeconds, function()
		resetAvailable(runtime, token)
	end)
end

local function completeEncounter(runtime: EncounterRuntime)
	local player = runtime.Participant
	if not player or player.Parent ~= Players then
		failEncounter(runtime, "PARTICIPANT_UNAVAILABLE")
		return
	end

	local componentId = chooseWeightedComponent(runtime.Definition.ComponentWeights)
	local rarity = chooseWeightedRarity(runtime.Definition.RarityWeights)
	if not componentId or not rarity then
		failEncounter(runtime, "REWARD_CONFIG_INVALID")
		return
	end

	local quantity = runtime.Definition.RewardQuantity
	local didAward = ModularPrototypeStateService.AddUnbankedComponent(player, componentId, rarity, quantity)
	if not didAward then
		failEncounter(runtime, "UNBANKED_CAP_REACHED")
		return
	end

	local definition = Components.GetDefinition(componentId)
	fireParticipant(runtime, {
		Kind = "COMPLETED",
		EncounterId = runtime.Definition.EncounterId,
		Reward = {
			ComponentId = componentId,
			DisplayName = if definition then definition.DisplayName else componentId,
			Rarity = rarity,
			Quantity = quantity,
		},
		CooldownSeconds = runtime.Definition.SuccessCooldownSeconds,
	})
	print(
		string.format(
			"[ODDWORKS][ActiveSalvage] %s completed %s (+%d %s [%s] to unbanked haul).",
			player.Name,
			runtime.Definition.EncounterId,
			quantity,
			componentId,
			rarity
		)
	)

	local token = runtime.LifecycleToken
	runtime.StageOpen = false
	runtime.Participant = nil
	setVisualState(runtime, "COOLDOWN")
	task.delay(runtime.Definition.SuccessCooldownSeconds, function()
		resetAvailable(runtime, token)
	end)
end

local function beginStage(runtime: EncounterRuntime, token: number, stage: number)
	if encounter ~= runtime
		or runtime.LifecycleToken ~= token
		or runtime.Status ~= "ACTIVE"
		or not runtime.Participant
	then
		return
	end

	local stageStart = Workspace:GetServerTimeNow()
	runtime.Stage = stage
	runtime.StageOpen = true
	runtime.WindowStartTime = stageStart + runtime.Definition.WindowStartSeconds
	runtime.WindowEndTime = stageStart + runtime.Definition.WindowEndSeconds
	fireParticipant(runtime, {
		Kind = "STAGE",
		EncounterId = runtime.Definition.EncounterId,
		Stage = stage,
		StageCount = runtime.Definition.StageCount,
		StageStartedAt = stageStart,
		WindowStartAt = runtime.WindowStartTime,
		WindowEndAt = runtime.WindowEndTime,
		StageEndsAt = stageStart + runtime.Definition.StageDurationSeconds,
	})

	task.delay(runtime.Definition.StageDurationSeconds, function()
		if encounter == runtime
			and runtime.LifecycleToken == token
			and runtime.Status == "ACTIVE"
			and runtime.Stage == stage
			and runtime.StageOpen
		then
			failEncounter(runtime, "MISSED_WINDOW")
		end
	end)
end

-- Prompt activation begins the activity but never grants the reward. The server
-- reserves the one encounter before Stage 1 so two players cannot share progress.
local function tryStartEncounter(player: Player, runtime: EncounterRuntime)
	if player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not isPlayerInRange(player, runtime)
	then
		return
	end

	if runtime.Status ~= "AVAILABLE" then
		local remote = activeSalvageState
		if remote then
			remote:FireClient(player, {
				Kind = "BUSY",
				EncounterId = runtime.Definition.EncounterId,
			})
		end
		return
	end

	runtime.LifecycleToken += 1
	runtime.Participant = player
	runtime.Stage = 0
	runtime.StageOpen = false
	setVisualState(runtime, "ACTIVE")
	beginStage(runtime, runtime.LifecycleToken, 1)
end

local function passesInputThrottle(player: Player, minimumInterval: number): boolean
	local now = os.clock()
	local lastInput = lastInputTimes[player]
	if lastInput and now - lastInput < minimumInterval then
		return false
	end

	lastInputTimes[player] = now
	return true
end

-- The client sends only the bounded encounter ID. Stage, timing, participant,
-- reward, and success are all re-derived from private server state.
local function handleExtractionInput(player: Player, ...: any)
	if select("#", ...) ~= 1 then
		return
	end

	local encounterId = select(1, ...)
	if typeof(encounterId) ~= "string" or #encounterId == 0 or #encounterId > MAX_ENCOUNTER_ID_LENGTH then
		return
	end

	local runtime = encounter
	if not runtime or encounterId ~= runtime.Definition.EncounterId then
		return
	end
	if not passesInputThrottle(player, runtime.Definition.InputMinimumIntervalSeconds) then
		return
	end
	if player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or runtime.Status ~= "ACTIVE"
		or runtime.Participant ~= player
		or not runtime.StageOpen
	then
		return
	end
	if not isPlayerInRange(player, runtime) then
		failEncounter(runtime, "OUT_OF_RANGE")
		return
	end

	local now = Workspace:GetServerTimeNow()
	if now < runtime.WindowStartTime then
		failEncounter(runtime, "TOO_EARLY")
		return
	end
	if now > runtime.WindowEndTime then
		failEncounter(runtime, "TOO_LATE")
		return
	end

	-- Close the stage before any event or delay so repeated packets cannot count
	-- twice for the same timing window.
	runtime.StageOpen = false
	local completedStage = runtime.Stage
	fireParticipant(runtime, {
		Kind = "STAGE_SUCCESS",
		EncounterId = runtime.Definition.EncounterId,
		Stage = completedStage,
	})

	if completedStage >= runtime.Definition.StageCount then
		completeEncounter(runtime)
		return
	end

	local token = runtime.LifecycleToken
	task.delay(runtime.Definition.InterstageDelaySeconds, function()
		beginStage(runtime, token, completedStage + 1)
	end)
end

-- Profile loss and disconnect invalidate delayed stage callbacks and release the
-- shared encounter immediately without granting a pending reward.
local function releaseParticipant(player: Player)
	local runtime = encounter
	if not runtime or runtime.Participant ~= player then
		lastInputTimes[player] = nil
		return
	end

	runtime.LifecycleToken += 1
	runtime.Participant = nil
	runtime.Stage = 0
	runtime.StageOpen = false
	setVisualState(runtime, "AVAILABLE")
	lastInputTimes[player] = nil
	print(string.format("[ODDWORKS][ActiveSalvage] Released %s after participant cleanup.", runtime.Definition.EncounterId))
end

local function discoverEncounter(): EncounterRuntime
	local definition = ActiveSalvageConfig.GetEncounter(EXPECTED_ENCOUNTER_ID) :: EncounterDefinition?
	if not definition then
		error("[ODDWORKS][ActiveSalvage] Missing JammedSalvageWreck configuration.")
	end
	validateDefinition(definition)

	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local salvageField = requireChildOfClass(world, "SalvageField", "BasePart")
	local model = requireChildOfClass(salvageField, definition.EncounterId, "Model") :: Model
	local interactionPart = requireChildOfClass(model, "InteractionPart", "BasePart") :: BasePart
	local prompt = requireChildOfClass(interactionPart, "Prompt", "ProximityPrompt") :: ProximityPrompt
	local signal = model:FindFirstChild("SignalLight")
	local signalLight = if signal and signal:IsA("BasePart") then signal else nil

	local runtime: EncounterRuntime = {
		Definition = definition,
		Model = model,
		InteractionPart = interactionPart,
		Prompt = prompt,
		SignalLight = signalLight,
		Status = "AVAILABLE",
		Participant = nil,
		Stage = 0,
		StageOpen = false,
		WindowStartTime = 0,
		WindowEndTime = 0,
		LifecycleToken = 0,
	}
	setVisualState(runtime, "AVAILABLE")
	prompt.Triggered:Connect(function(player: Player)
		tryStartEncounter(player, runtime)
	end)
	return runtime
end

function ActiveSalvageEncounterService.Start()
	if started then
		return
	end
	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local inputRequestRemote = requireChildOfClass(networkFolder, "ExtractionInputRequest", "RemoteEvent") :: RemoteEvent
	extractionInputRequest = inputRequestRemote
	activeSalvageState = requireChildOfClass(networkFolder, "ActiveSalvageState", "RemoteEvent") :: RemoteEvent
	encounter = discoverEncounter()

	inputRequestRemote.OnServerEvent:Connect(handleExtractionInput)
	ModularPrototypeStateService.ObserveStateRemoved(releaseParticipant)
	Players.PlayerRemoving:Connect(releaseParticipant)

	print("[ODDWORKS][ActiveSalvage] JammedSalvageWreck ready: 3 stages, 1.2-second success windows.")
end

return ActiveSalvageEncounterService
