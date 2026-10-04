--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][OuterYardSalvage] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local Components = require(Config:WaitForChild("Components"))
local OuterYardSalvageConfig = require(Config:WaitForChild("OuterYardSalvageConfig"))

type OpportunityDefinition = OuterYardSalvageConfig.OpportunityDefinition
type OpportunityRuntime = {
	Definition: OpportunityDefinition,
	Container: BasePart,
	Part: BasePart,
	Prompt: ProximityPrompt,
}

local OuterYardSalvageService = {}

local EXPECTED_OPPORTUNITY_COUNT = 3
local ATTEMPT_INTERVAL_SECONDS = 0.25

local registeredOpportunities: { [string]: OpportunityRuntime } = {}
local claimedByPlayer: { [Player]: { [string]: boolean } } = {}
local lastAttemptTimes: { [Player]: number } = {}
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][OuterYardSalvage] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][OuterYardSalvage] %s.%s must be a %s, but found %s.",
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

local function isPositiveInteger(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value > 0 and math.floor(value) == value
end

local function validateDefinition(definition: OpportunityDefinition)
	if #definition.OpportunityId == 0
		or #definition.OpportunityId > 48
		or #definition.WorldObjectName == 0
		or #definition.WorldObjectName > 64
		or not Components.GetDefinition(definition.ComponentId)
		or not Components.IsValidRarity(definition.Rarity)
		or not isPositiveInteger(definition.Quantity)
		or definition.MaxValidDistance <= 0
	then
		error(string.format("[ODDWORKS][OuterYardSalvage] Invalid opportunity definition: %s", definition.OpportunityId))
	end
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function passesAttemptThrottle(player: Player): boolean
	local now = os.clock()
	local lastAttempt = lastAttemptTimes[player]
	if lastAttempt and now - lastAttempt < ATTEMPT_INTERVAL_SECONDS then
		return false
	end

	lastAttemptTimes[player] = now
	return true
end

local function clearPlayer(player: Player)
	claimedByPlayer[player] = nil
	lastAttemptTimes[player] = nil
end

local function handleTriggered(player: Player, runtime: OpportunityRuntime)
	if player.Parent ~= Players or not passesAttemptThrottle(player) then
		return
	end
	if not PlayerStateService.HasState(player) or not ModularPrototypeStateService.HasState(player) then
		return
	end
	if registeredOpportunities[runtime.Definition.OpportunityId] ~= runtime
		or runtime.Part.Parent ~= runtime.Container
		or runtime.Prompt.Parent ~= runtime.Part
	then
		return
	end

	local claims = claimedByPlayer[player]
	if claims and claims[runtime.Definition.OpportunityId] then
		return
	end

	local root = getCharacterRoot(player)
	if not root or (root.Position - runtime.Part.Position).Magnitude > runtime.Definition.MaxValidDistance then
		return
	end

	if not claims then
		claims = {}
		claimedByPlayer[player] = claims
	end

	-- Reserve before mutation so reentrant prompt signals cannot duplicate a
	-- session claim. A failed validated mutation releases only this reservation.
	claims[runtime.Definition.OpportunityId] = true
	local didAward = ModularPrototypeStateService.AddUnbankedComponent(
		player,
		runtime.Definition.ComponentId,
		runtime.Definition.Rarity,
		runtime.Definition.Quantity
	)
	if not didAward then
		claims[runtime.Definition.OpportunityId] = nil
		warn(
			string.format(
				"[ODDWORKS][OuterYardSalvage] Failed to award configured reward for %s at %s.",
				player.Name,
				runtime.Definition.OpportunityId
			)
		)
		return
	end

	print(
		string.format(
			"[ODDWORKS][OuterYardSalvage] %s recovered +%d %s [%s] into UnbankedComponents.",
			player.Name,
			runtime.Definition.Quantity,
			runtime.Definition.ComponentId,
			runtime.Definition.Rarity
		)
	)
end

local function discoverOpportunities(): { [string]: OpportunityRuntime }
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local salvageField = requireChildOfClass(world, "SalvageField", "BasePart")
	local definitions = OuterYardSalvageConfig.GetAllOpportunities()
	if #definitions ~= EXPECTED_OPPORTUNITY_COUNT then
		error(string.format("[ODDWORKS][OuterYardSalvage] Expected exactly %d opportunities.", EXPECTED_OPPORTUNITY_COUNT))
	end

	local discovered: { [string]: OpportunityRuntime } = {}
	for _, definition in ipairs(definitions) do
		validateDefinition(definition)
		if discovered[definition.OpportunityId] then
			error(string.format("[ODDWORKS][OuterYardSalvage] Duplicate opportunity ID: %s", definition.OpportunityId))
		end

		local part = requireChildOfClass(salvageField, definition.WorldObjectName, "BasePart") :: BasePart
		local prompt = requireChildOfClass(part, "Prompt", "ProximityPrompt") :: ProximityPrompt
		local runtime: OpportunityRuntime = {
			Definition = definition,
			Container = salvageField,
			Part = part,
			Prompt = prompt,
		}
		discovered[definition.OpportunityId] = runtime
		prompt.Triggered:Connect(function(player: Player)
			handleTriggered(player, runtime)
		end)
	end

	return discovered
end

function OuterYardSalvageService.Start()
	if started then
		return
	end
	started = true

	registeredOpportunities = discoverOpportunities()
	ModularPrototypeStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)

	print(string.format("[ODDWORKS][OuterYardSalvage] Service started with %d per-player opportunities.", EXPECTED_OPPORTUNITY_COUNT))
end

return OuterYardSalvageService
