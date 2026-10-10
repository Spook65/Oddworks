--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type AssemblerRecord = {
	PlotId: string,
	Plot: BasePart,
	Assembler: BasePart,
	Prompt: ProximityPrompt,
}

local EXPECTED_PLOT_IDS = {
	"Plot01",
	"Plot02",
}
local ASSEMBLER_NAME = "PrototypeAssembler"
local PROMPT_NAME = "Prompt"
local MAX_VALID_DISTANCE = 12
local OPEN_INTERVAL_SECONDS = 0.5
local ASSEMBLY_INTERVAL_SECONDS = 1
local MAX_ID_LENGTH = 32
local MAX_RARITY_LENGTH = 16

local PrototypeAssemblyService = {}

local assemblersByPlotId: { [string]: AssemblerRecord } = {}
local lastOpenTimes: { [Player]: number } = {}
local lastAssemblyTimes: { [Player]: number } = {}
local assemblerOpen: RemoteEvent? = nil
local assemblyResult: RemoteEvent? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][PrototypeAssembly] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][PrototypeAssembly] %s.%s must be a %s, but found %s.",
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

local function discoverAssemblers(): { AssemblerRecord }
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local workshopPlots = requireChildOfClass(world, "WorkshopPlots", "Folder")
	local records: { AssemblerRecord } = {}

	for _, plotId in ipairs(EXPECTED_PLOT_IDS) do
		local plot = requireChildOfClass(workshopPlots, plotId, "BasePart") :: BasePart
		local assembler = requireChildOfClass(plot, ASSEMBLER_NAME, "BasePart") :: BasePart
		local prompt = requireChildOfClass(assembler, PROMPT_NAME, "ProximityPrompt") :: ProximityPrompt
		local record = {
			PlotId = plotId,
			Plot = plot,
			Assembler = assembler,
			Prompt = prompt,
		}
		assemblersByPlotId[plotId] = record
		table.insert(records, record)
	end

	return records
end

local function passesThrottle(times: { [Player]: number }, player: Player, interval: number): boolean
	local now = os.clock()
	local lastAttempt = times[player]
	if lastAttempt and now - lastAttempt < interval then
		return false
	end
	times[player] = now
	return true
end

local function isBoundedString(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

local function hasExactKeys(value: any, expectedKeys: { [string]: boolean }): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local expectedCount = 0
	for _ in pairs(expectedKeys) do
		expectedCount += 1
	end

	local seenCount = 0
	for key in pairs(value) do
		if typeof(key) ~= "string" or not expectedKeys[key] then
			return false
		end
		seenCount += 1
		if seenCount > expectedCount then
			return false
		end
	end
	return seenCount == expectedCount
end

-- Shape validation is intentionally duplicated at the network edge; the state
-- service revalidates configuration and ownership before committing anything.
local function hasValidRequestShape(request: any): boolean
	if not hasExactKeys(request, { FrameId = true, Head = true, Arm = true, Legs = true })
		or not isBoundedString(request.FrameId, MAX_ID_LENGTH)
	then
		return false
	end

	for _, role in ipairs({ "Head", "Arm", "Legs" }) do
		local selection = request[role]
		if not hasExactKeys(selection, { ComponentId = true, Rarity = true })
			or not isBoundedString(selection.ComponentId, MAX_ID_LENGTH)
			or not isBoundedString(selection.Rarity, MAX_RARITY_LENGTH)
		then
			return false
		end
	end
	return true
end

local function isPlayerNearAssembler(player: Player, assembler: BasePart): boolean
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end
	return (rootPart.Position - assembler.Position).Magnitude <= MAX_VALID_DISTANCE
end

local function getAuthorizedAssembler(player: Player): AssemblerRecord?
	if player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
	then
		return nil
	end

	local assignedPlotId = WorkshopService.GetAssignedPlotId(player)
	local assignedPlot = WorkshopService.GetAssignedPlot(player)
	local productionSnapshot = PlayerStateService.GetSnapshot(player)
	local record = if assignedPlotId then assemblersByPlotId[assignedPlotId] else nil
	if not record
		or assignedPlot ~= record.Plot
		or not productionSnapshot
		or productionSnapshot.AssignedPlotId ~= record.PlotId
		or record.Assembler.Parent ~= record.Plot
		or record.Prompt.Parent ~= record.Assembler
		or not isPlayerNearAssembler(player, record.Assembler)
	then
		return nil
	end
	return record
end

local function sendResult(player: Player, resultCode: string, mode: string?)
	local remote = assemblyResult
	if remote and player.Parent == Players then
		remote:FireClient(player, resultCode, mode)
	end
end

local function handlePromptTriggered(player: Player, record: AssemblerRecord)
	if not passesThrottle(lastOpenTimes, player, OPEN_INTERVAL_SECONDS) then
		return
	end

	local authorizedRecord = getAuthorizedAssembler(player)
	if authorizedRecord ~= record then
		warn(string.format("[ODDWORKS][PrototypeAssembly] Rejected wrong-context assembler use by %s at %s.", player.Name, record.PlotId))
		return
	end

	local remote = assemblerOpen
	if remote then
		remote:FireClient(player)
	end
end

local function handleAssemblyRequest(player: Player, ...: any)
	local argumentCount = select("#", ...)
	if player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
	then
		sendResult(player, "NOT_READY")
		return
	end
	if not passesThrottle(lastAssemblyTimes, player, ASSEMBLY_INTERVAL_SECONDS) then
		sendResult(player, "RATE_LIMITED")
		return
	end
	if argumentCount ~= 1 then
		sendResult(player, "INVALID_REQUEST")
		return
	end
	local request = select(1, ...)
	if not hasValidRequestShape(request) then
		sendResult(player, "INVALID_REQUEST")
		return
	end
	if not getAuthorizedAssembler(player) then
		sendResult(player, "OUT_OF_RANGE")
		return
	end

	local resultCode, wasRebuild = ModularPrototypeStateService.AssemblePrototypeConstruct(player, request)
	local mode: string? = nil
	if resultCode == "ASSEMBLY_SUCCESS" then
		mode = if wasRebuild then "REBUILT" else "ASSEMBLED"
	end
	sendResult(player, resultCode, mode)
	if resultCode == "ASSEMBLY_SUCCESS" then
		print(string.format("[ODDWORKS][PrototypeAssembly] %s %s SmallBiped_v1.", player.Name, string.lower(mode or "updated")))
	end
end

function PrototypeAssemblyService.Start()
	if started then
		return
	end
	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	assemblerOpen = requireChildOfClass(networkFolder, "AssemblerOpen", "RemoteEvent") :: RemoteEvent
	assemblyResult = requireChildOfClass(networkFolder, "AssemblyResult", "RemoteEvent") :: RemoteEvent
	local requestRemote = requireChildOfClass(networkFolder, "AssembleConstructRequest", "RemoteEvent") :: RemoteEvent
	requestRemote.OnServerEvent:Connect(handleAssemblyRequest)

	local records = discoverAssemblers()
	for _, record in ipairs(records) do
		local assemblerRecord = record
		assemblerRecord.Prompt.Triggered:Connect(function(player: Player)
			handlePromptTriggered(player, assemblerRecord)
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastOpenTimes[player] = nil
		lastAssemblyTimes[player] = nil
	end)

	print(string.format("[ODDWORKS][PrototypeAssembly] Service started with %d workshop assemblers.", #records))
end

return PrototypeAssemblyService
