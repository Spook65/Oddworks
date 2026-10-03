--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type IntakeRecord = {
	PlotId: string,
	Plot: BasePart,
	Intake: BasePart,
	Prompt: ProximityPrompt,
}

local EXPECTED_PLOT_IDS = {
	"Plot01",
	"Plot02",
}
local INTAKE_NAME = "SalvageIntake"
local PROMPT_NAME = "Prompt"
local MAX_VALID_DISTANCE = 12
local BANK_ATTEMPT_INTERVAL_SECONDS = 0.5

local WorkshopBankingService = {}

local lastAttemptTimes: { [Player]: number } = {}
local bankResult: RemoteEvent? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][WorkshopBanking] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][WorkshopBanking] %s.%s must be a %s, but found %s.",
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

local function discoverIntakes(): { IntakeRecord }
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local workshopPlots = requireChildOfClass(world, "WorkshopPlots", "Folder")
	local records: { IntakeRecord } = {}

	for _, plotId in ipairs(EXPECTED_PLOT_IDS) do
		local plot = requireChildOfClass(workshopPlots, plotId, "BasePart") :: BasePart
		local intake = requireChildOfClass(plot, INTAKE_NAME, "BasePart") :: BasePart
		local prompt = requireChildOfClass(intake, PROMPT_NAME, "ProximityPrompt") :: ProximityPrompt
		table.insert(records, {
			PlotId = plotId,
			Plot = plot,
			Intake = intake,
			Prompt = prompt,
		})
	end

	return records
end

local function sendResult(player: Player, resultCode: string, transferredCount: number?)
	local remote = bankResult
	if remote and player.Parent == Players then
		remote:FireClient(player, resultCode, transferredCount)
	end
end

local function passesAttemptThrottle(player: Player): boolean
	local now = os.clock()
	local lastAttempt = lastAttemptTimes[player]
	if lastAttempt and now - lastAttempt < BANK_ATTEMPT_INTERVAL_SECONDS then
		return false
	end

	lastAttemptTimes[player] = now
	return true
end

local function isPlayerNearIntake(player: Player, intake: BasePart): boolean
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	return (rootPart.Position - intake.Position).Magnitude <= MAX_VALID_DISTANCE
end

-- Prompt activation is only an interaction signal. The service reconstructs
-- assignment and proximity from server-owned state before moving any inventory.
local function handleIntakeTriggered(player: Player, record: IntakeRecord)
	if player.Parent ~= Players or not passesAttemptThrottle(player) then
		return
	end

	if not PlayerStateService.HasState(player) or not ModularPrototypeStateService.HasState(player) then
		sendResult(player, "BANK_REJECTED")
		return
	end

	local assignedPlot = WorkshopService.GetAssignedPlot(player)
	local assignedPlotId = WorkshopService.GetAssignedPlotId(player)
	local productionSnapshot = PlayerStateService.GetSnapshot(player)
	if assignedPlot ~= record.Plot
		or assignedPlotId ~= record.PlotId
		or not productionSnapshot
		or productionSnapshot.AssignedPlotId ~= record.PlotId
	then
		warn(string.format("[ODDWORKS][WorkshopBanking] Rejected wrong-plot intake use by %s at %s.", player.Name, record.PlotId))
		sendResult(player, "BANK_REJECTED")
		return
	end

	if record.Intake.Parent ~= record.Plot or record.Prompt.Parent ~= record.Intake then
		warn(string.format("[ODDWORKS][WorkshopBanking] Rejected invalid intake hierarchy for %s.", record.PlotId))
		sendResult(player, "BANK_REJECTED")
		return
	end

	if not isPlayerNearIntake(player, record.Intake) then
		sendResult(player, "BANK_REJECTED")
		return
	end

	local resultCode, transferredCount = ModularPrototypeStateService.BankAllUnbanked(player)
	sendResult(player, resultCode, transferredCount)
	if resultCode == "BANK_SUCCESS" then
		print(
			string.format(
				"[ODDWORKS][WorkshopBanking] %s banked %d session-only component(s) at %s.",
				player.Name,
				transferredCount,
				record.PlotId
			)
		)
	elseif resultCode == "BANK_OVERFLOW" then
		warn(string.format("[ODDWORKS][WorkshopBanking] Rejected atomic bank overflow for %s.", player.Name))
	end
end

function WorkshopBankingService.Start()
	if started then
		return
	end
	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	bankResult = requireChildOfClass(networkFolder, "BankResult", "RemoteEvent") :: RemoteEvent

	local records = discoverIntakes()
	for _, record in ipairs(records) do
		local intakeRecord = record
		intakeRecord.Prompt.Triggered:Connect(function(player: Player)
			handleIntakeTriggered(player, intakeRecord)
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttemptTimes[player] = nil
	end)

	print(string.format("[ODDWORKS][WorkshopBanking] Service started with %d plot intakes.", #records))
end

return WorkshopBankingService
