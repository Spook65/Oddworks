--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))

type PlotRecord = {
	Id: string,
	Instance: BasePart,
}

local EXPECTED_PLOT_IDS = {
	"Plot01",
	"Plot02",
}

local PLAYER_STATE_WAIT_SECONDS = 5

local WorkshopService = {}

-- WorkshopService is the server authority for live plot occupancy.
-- These maps stay private so clients and unrelated modules cannot claim or rewrite ownership.
local validPlots: { PlotRecord } = {}
local plotOccupants: { [string]: Player } = {}
local playerPlotIds: { [Player]: string } = {}
local started = false

-- Verifies a required persistent world object without creating replacements at runtime.
-- Pass 2 assigns ownership only; the Rojo/Studio map remains the source of truth for geometry.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][WorkshopService] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end

	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][WorkshopService] %s.%s must be a %s, but found %s.",
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

-- Discovers only the current vertical-slice plots and sorts them by stable name.
-- Deterministic ordering makes Play tests predictable and avoids depending on GetChildren() order.
local function discoverValidPlots(): { PlotRecord }
	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local workshopPlots = requireChildOfClass(world, "WorkshopPlots", "Folder")

	local discoveredPlots: { PlotRecord } = {}

	for _, plotId in ipairs(EXPECTED_PLOT_IDS) do
		local plotInstance = requireChildOfClass(workshopPlots, plotId, "BasePart")
		table.insert(discoveredPlots, {
			Id = plotId,
			Instance = plotInstance :: BasePart,
		})
	end

	table.sort(discoveredPlots, function(left: PlotRecord, right: PlotRecord): boolean
		return left.Id < right.Id
	end)

	return discoveredPlots
end

-- Finds the first unoccupied plot from the deterministic plot list.
-- Returning nil is valid when the server has more players than available bootstrap plots.
local function findFirstAvailablePlot(): PlotRecord?
	for _, plot in ipairs(validPlots) do
		if plotOccupants[plot.Id] == nil then
			return plot
		end
	end

	return nil
end

-- Assigns one server-selected plot to a player that has PlayerState.
-- The client never supplies a plot ID; assignment is derived only from server-owned occupancy.
local function assignPlayer(player: Player): boolean
	if playerPlotIds[player] ~= nil then
		return true
	end

	if not PlayerStateService.HasState(player) then
		warn(string.format("[ODDWORKS][WorkshopService] Cannot assign %s yet; PlayerState is missing.", player.Name))
		return false
	end

	local availablePlot = findFirstAvailablePlot()
	if not availablePlot then
		warn(string.format("[ODDWORKS][WorkshopService] No available workshop plot for %s.", player.Name))
		return false
	end

	plotOccupants[availablePlot.Id] = player
	playerPlotIds[player] = availablePlot.Id

	local didRecordPlot = PlayerStateService.AssignPlot(player, availablePlot.Id)
	if not didRecordPlot then
		plotOccupants[availablePlot.Id] = nil
		playerPlotIds[player] = nil
		warn(string.format("[ODDWORKS][WorkshopService] Could not record plot assignment for %s.", player.Name))
		return false
	end

	print(string.format("[ODDWORKS][WorkshopService] Assigned %s -> %s", player.Name, availablePlot.Id))
	return true
end

-- Waits briefly for PlayerStateService when join events arrive in an unexpected order.
-- This avoids split authority without letting WorkshopService create or mutate PlayerState directly.
local function assignPlayerWhenStateReady(player: Player)
	if PlayerStateService.HasState(player) then
		assignPlayer(player)
		return
	end

	task.spawn(function()
		local startTime = os.clock()

		while player.Parent == Players and not PlayerStateService.HasState(player) do
			if os.clock() - startTime >= PLAYER_STATE_WAIT_SECONDS then
				warn(string.format("[ODDWORKS][WorkshopService] Timed out waiting for PlayerState for %s.", player.Name))
				return
			end

			task.wait(0.1)
		end

		if player.Parent == Players then
			assignPlayer(player)
		end
	end)
end

-- Releases only the departing player's plot and leaves every other assignment intact.
-- PlayerState may already be gone during PlayerRemoving, so internal occupancy cleanup is the priority.
local function releasePlayer(player: Player): boolean
	local plotId = playerPlotIds[player]
	if not plotId then
		return false
	end

	if plotOccupants[plotId] == player then
		plotOccupants[plotId] = nil
	end

	playerPlotIds[player] = nil
	PlayerStateService.ClearAssignedPlot(player, plotId)

	print(string.format("[ODDWORKS][WorkshopService] Released %s", plotId))
	return true
end

-- Starts plot discovery and player lifecycle hooks once.
-- PlayerStateService must start first so WorkshopService can record AssignedPlotId through its narrow API.
function WorkshopService.Start()
	if started then
		return
	end

	started = true
	validPlots = discoverValidPlots()

	Players.PlayerAdded:Connect(assignPlayerWhenStateReady)
	Players.PlayerRemoving:Connect(releasePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		assignPlayerWhenStateReady(player)
	end

	print(string.format("[ODDWORKS][WorkshopService] Service started with %d plots.", #validPlots))
end

-- Reports whether the server has assigned a workshop plot to this Player.
function WorkshopService.HasPlot(player: Player): boolean
	return playerPlotIds[player] ~= nil
end

-- Returns the assigned plot ID as an immutable string value, not the private occupancy tables.
function WorkshopService.GetAssignedPlotId(player: Player): string?
	return playerPlotIds[player]
end

return WorkshopService
