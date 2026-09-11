--!strict

local Players = game:GetService("Players")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][HypeService] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local OddlingDisplayService = require(Services:WaitForChild("OddlingDisplayService"))

local oddlingsModule = Config:WaitForChild("Oddlings")
if not oddlingsModule:IsA("ModuleScript") then
	error("[ODDWORKS][HypeService] Server.Config.Oddlings must be a ModuleScript.")
end

local Oddlings = require(oddlingsModule)

type OddlingDefinition = {
	SpeciesId: string,
	HypePerInterval: number,
	HypeIntervalSeconds: number,
}

local TOASTMARSHAL_SPECIES_ID = "Toastmarshal"
local PRODUCTION_POLL_SECONDS = 1

local HypeService = {}

-- One server-owned timestamp per producing player prevents newly displayed
-- Oddlings from receiving an instant reward while avoiding one loop per model.
local nextProductionTimes: { [Player]: number } = {}
local started = false

-- Rejects invalid server configuration before it can produce malformed currency.
-- Hype remains integer-valued even though Luau numbers can also represent fractions.
local function isValidDefinition(definition: OddlingDefinition): boolean
	local amount = definition.HypePerInterval
	local interval = definition.HypeIntervalSeconds

	if amount ~= amount or amount == math.huge or amount == -math.huge then
		return false
	end

	if interval ~= interval or interval == math.huge or interval == -math.huge then
		return false
	end

	return amount > 0 and math.floor(amount) == amount and interval > 0
end

-- Evaluates one player's current server-created displays at the production tick.
-- Ownership alone is insufficient because authored display capacity is part of the economy.
local function evaluatePlayer(player: Player, definition: OddlingDefinition, now: number)
	if not PlayerStateService.HasState(player) then
		nextProductionTimes[player] = nil
		return
	end

	local displayedCount = OddlingDisplayService.GetDisplayedCount(player, definition.SpeciesId)
	if displayedCount <= 0 then
		nextProductionTimes[player] = nil
		return
	end

	local nextProductionTime = nextProductionTimes[player]
	if not nextProductionTime then
		-- A full interval begins only after a valid display is first observed.
		nextProductionTimes[player] = now + definition.HypeIntervalSeconds
		return
	end

	if now < nextProductionTime then
		return
	end

	local award = displayedCount * definition.HypePerInterval
	if PlayerStateService.AddHype(player, award) then
		print(
			string.format(
				"[ODDWORKS][HypeService] %s +%d Hype from %d displayed Toastmarshal(s).",
				player.Name,
				award,
				displayedCount
			)
		)
	else
		warn(string.format("[ODDWORKS][HypeService] Failed to award Hype to %s.", player.Name))
	end

	-- Scheduling from the completed evaluation avoids catch-up bursts after a server stall.
	nextProductionTimes[player] = now + definition.HypeIntervalSeconds
end

-- Runs one bounded server loop for all active players.
-- The client supplies neither timing nor counts; both inputs are read from server-owned systems.
local function runProductionLoop(definition: OddlingDefinition)
	task.spawn(function()
		while true do
			task.wait(PRODUCTION_POLL_SECONDS)
			local now = os.clock()

			for _, player in ipairs(Players:GetPlayers()) do
				evaluatePlayer(player, definition, now)
			end
		end
	end)
end

-- Starts production only after PlayerState and OddlingDisplayService are available.
-- PlayerRemoving cleanup prevents stale Player references from remaining in timing state.
function HypeService.Start()
	if started then
		return
	end

	local definition = Oddlings.GetDefinition(TOASTMARSHAL_SPECIES_ID) :: OddlingDefinition?
	if not definition or not isValidDefinition(definition) then
		error("[ODDWORKS][HypeService] Toastmarshal has an invalid production definition.")
	end

	started = true

	Players.PlayerRemoving:Connect(function(player: Player)
		nextProductionTimes[player] = nil
	end)

	runProductionLoop(definition)
	print(
		string.format(
			"[ODDWORKS][HypeService] Service started (%d Hype per %g seconds per displayed Toastmarshal).",
			definition.HypePerInterval,
			definition.HypeIntervalSeconds
		)
	)
end

return HypeService
