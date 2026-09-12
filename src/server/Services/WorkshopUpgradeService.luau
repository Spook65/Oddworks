--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][WorkshopUpgradeService] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

local workshopLevelsModule = Config:WaitForChild("WorkshopLevels")
if not workshopLevelsModule:IsA("ModuleScript") then
	error("[ODDWORKS][WorkshopUpgradeService] Server.Config.WorkshopLevels must be a ModuleScript.")
end

local WorkshopLevels = require(workshopLevelsModule)

type WorkshopLevelDefinition = {
	Level: number,
	DisplayCapacity: number,
	UpgradeCost: number?,
	NextLevel: number?,
}

type UpgradeStation = {
	PlotId: string,
	Plot: BasePart,
	Station: BasePart,
	Prompt: ProximityPrompt,
}

local EXPECTED_PLOT_IDS = {
	"Plot01",
	"Plot02",
}
local STATION_NAME = "WorkshopUpgradeStation"
local PROMPT_NAME = "Prompt"
local MAX_VALID_DISTANCE = 12
local UPGRADE_ATTEMPT_INTERVAL_SECONDS = 0.75

local WorkshopUpgradeService = {}

-- Station records and request timing remain server-private. A client can trigger
-- a nearby prompt, but it cannot choose the plot, cost, or target level.
local stationsByPlotId: { [string]: UpgradeStation } = {}
local lastAttemptTimes: { [Player]: number } = {}
local lastKnownPlotIds: { [Player]: string } = {}
local started = false

-- Verifies persistent world objects instead of creating substitute stations at runtime.
-- Rojo-authored geometry remains visible and inspectable in Edit mode.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(
			string.format(
				"[ODDWORKS][WorkshopUpgradeService] Missing required object: %s.%s",
				parent:GetFullName(),
				childName
			),
			2
		)
	end

	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][WorkshopUpgradeService] %s.%s must be a %s, but found %s.",
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

-- Discovers the two authored stations in stable plot order and disables them
-- until an authoritative plot owner and level are known.
local function discoverStations(): { UpgradeStation }
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local workshopPlots = requireChildOfClass(world, "WorkshopPlots", "Folder")
	local stations: { UpgradeStation } = {}

	for _, plotId in ipairs(EXPECTED_PLOT_IDS) do
		local plot = requireChildOfClass(workshopPlots, plotId, "BasePart") :: BasePart
		local station = requireChildOfClass(plot, STATION_NAME, "BasePart") :: BasePart
		local prompt = requireChildOfClass(station, PROMPT_NAME, "ProximityPrompt") :: ProximityPrompt
		prompt.Enabled = false

		local record = {
			PlotId = plotId,
			Plot = plot,
			Station = station,
			Prompt = prompt,
		}
		stationsByPlotId[plotId] = record
		table.insert(stations, record)
	end

	return stations
end

-- Applies prompt presentation from server state. The visible cost is helpful UI,
-- while the later transaction still resolves its price from server configuration.
local function updatePromptForPlayer(player: Player)
	local plotId = WorkshopService.GetAssignedPlotId(player)
	if not plotId then
		return
	end

	lastKnownPlotIds[player] = plotId
	local record = stationsByPlotId[plotId]
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not record or not snapshot or snapshot.AssignedPlotId ~= plotId then
		return
	end

	local definition = WorkshopLevels.GetDefinition(snapshot.WorkshopLevel) :: WorkshopLevelDefinition?
	if definition and definition.NextLevel and definition.UpgradeCost then
		record.Prompt.ActionText = "Upgrade Workshop"
		record.Prompt.ObjectText = string.format("%d Hype", definition.UpgradeCost)
		record.Prompt.Enabled = true
	else
		record.Prompt.Enabled = false
	end
end

-- Throttles prompt attempts before validation work so repeated exploit or accidental
-- activation cannot create noisy state-changing requests.
local function passesAttemptThrottle(player: Player): boolean
	local now = os.clock()
	local lastAttemptTime = lastAttemptTimes[player]
	if lastAttemptTime and now - lastAttemptTime < UPGRADE_ATTEMPT_INTERVAL_SECONDS then
		return false
	end

	lastAttemptTimes[player] = now
	return true
end

-- Independently checks character distance because prompt visibility is presentation,
-- not proof that the triggering player is still in an authorized context.
local function isPlayerNearStation(player: Player, station: BasePart): boolean
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	return (rootPart.Position - station.Position).Magnitude <= MAX_VALID_DISTANCE
end

-- Executes the one-time Hype-to-level transaction with an exact refund path.
-- Display changes remain downstream consequences of the PlayerState notification.
local function executeUpgrade(player: Player, definition: WorkshopLevelDefinition): boolean
	local upgradeCost = definition.UpgradeCost
	local nextLevel = definition.NextLevel
	if not upgradeCost or not nextLevel then
		return false
	end

	if not PlayerStateService.CanAffordHype(player, upgradeCost) then
		print(string.format("[ODDWORKS][WorkshopUpgrade] %s needs %d Hype to upgrade.", player.Name, upgradeCost))
		return false
	end

	if not PlayerStateService.SpendHype(player, upgradeCost) then
		return false
	end

	if not PlayerStateService.AdvanceWorkshopLevel(player, definition.Level, nextLevel) then
		local didRefund = PlayerStateService.AddHype(player, upgradeCost)
		if not didRefund then
			warn(string.format("[ODDWORKS][WorkshopUpgrade] Failed to refund Hype to %s after rollback.", player.Name))
		end

		warn(string.format("[ODDWORKS][WorkshopUpgrade] Rolled back failed level advancement for %s.", player.Name))
		return false
	end

	print(
		string.format(
			"[ODDWORKS][WorkshopUpgrade] %s upgraded %s from Level %d to Level %d (-%d Hype).",
			player.Name,
			WorkshopService.GetAssignedPlotId(player) or "unknown plot",
			definition.Level,
			nextLevel,
			upgradeCost
		)
	)
	return true
end

-- Treats Prompt.Triggered as an untrusted request and reconstructs every
-- authorization, proximity, price, and transition input from server state.
local function handleUpgradeTriggered(player: Player, record: UpgradeStation)
	if player.Parent ~= Players or not passesAttemptThrottle(player) then
		return
	end

	if not PlayerStateService.HasState(player) then
		return
	end

	local assignedPlot = WorkshopService.GetAssignedPlot(player)
	local assignedPlotId = WorkshopService.GetAssignedPlotId(player)
	local snapshot = PlayerStateService.GetSnapshot(player)
	if
		assignedPlot ~= record.Plot
		or assignedPlotId ~= record.PlotId
		or not snapshot
		or snapshot.AssignedPlotId ~= record.PlotId
	then
		warn(string.format("[ODDWORKS][WorkshopUpgrade] Rejected wrong-plot interaction from %s at %s.", player.Name, record.PlotId))
		return
	end

	if record.Station.Parent ~= record.Plot or record.Prompt.Parent ~= record.Station then
		warn(string.format("[ODDWORKS][WorkshopUpgrade] Rejected invalid station hierarchy for %s.", record.PlotId))
		return
	end

	if not isPlayerNearStation(player, record.Station) then
		return
	end

	local definition = WorkshopLevels.GetDefinition(snapshot.WorkshopLevel) :: WorkshopLevelDefinition?
	local nextDefinition = if definition and definition.NextLevel
		then WorkshopLevels.GetDefinition(definition.NextLevel) :: WorkshopLevelDefinition?
		else nil
	if not definition or not definition.NextLevel or not definition.UpgradeCost or not nextDefinition then
		record.Prompt.Enabled = false
		print(string.format("[ODDWORKS][WorkshopUpgrade] %s is already at maximum workshop level.", player.Name))
		return
	end

	if executeUpgrade(player, definition) then
		updatePromptForPlayer(player)
	end
end

-- Starts station discovery after PlayerState and WorkshopService are ready.
-- State notifications keep prompt availability aligned with each plot owner's level.
function WorkshopUpgradeService.Start()
	if started then
		return
	end

	started = true
	local stations = discoverStations()
	for _, record in ipairs(stations) do
		local stationRecord = record
		stationRecord.Prompt.Triggered:Connect(function(player: Player)
			handleUpgradeTriggered(player, stationRecord)
		end)
	end

	PlayerStateService.ObserveStateChanged(updatePromptForPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttemptTimes[player] = nil
		local plotId = lastKnownPlotIds[player]
		lastKnownPlotIds[player] = nil
		if plotId and stationsByPlotId[plotId] then
			stationsByPlotId[plotId].Prompt.Enabled = false
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		updatePromptForPlayer(player)
	end

	print(string.format("[ODDWORKS][WorkshopUpgrade] Service started with %d stations.", #stations))
end

return WorkshopUpgradeService
