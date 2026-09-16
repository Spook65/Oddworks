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

local PRODUCTION_POLL_SECONDS = 1

local HypeService = {}

-- Timers are scoped by player and species so different Oddling definitions can
-- use different intervals without creating one loop per display model.
local nextProductionTimes: { [Player]: { [string]: number } } = {}
local productionDefinitions: { OddlingDefinition } = {}
local started = false

-- Rejects malformed server configuration before it can produce invalid currency.
-- Hype remains integer-valued even though Luau numbers can represent fractions.
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

-- Builds one deterministic list of configured producers. Invalid definitions
-- stop startup rather than silently changing the server-owned economy.
local function loadProductionDefinitions(): { OddlingDefinition }
	local definitions: { OddlingDefinition } = {}

	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		if not isValidDefinition(definition) then
			error(string.format("[ODDWORKS][HypeService] %s has an invalid production definition.", definition.SpeciesId))
		end

		table.insert(definitions, definition)
	end

	return definitions
end

-- Evaluates one player from server-created display counts at the current tick.
-- Zero displayed models produce nothing even when authoritative ownership is higher.
local function evaluatePlayer(player: Player, now: number)
	if not PlayerStateService.HasState(player) then
		nextProductionTimes[player] = nil
		return
	end

	local displayedCounts = OddlingDisplayService.GetDisplayedCounts(player)
	local playerTimers = nextProductionTimes[player]
	if not playerTimers then
		playerTimers = {}
		nextProductionTimes[player] = playerTimers
	end

	local totalAward = 0
	local contributions: { string } = {}

	for _, definition in ipairs(productionDefinitions) do
		local speciesId = definition.SpeciesId
		local displayedCount = displayedCounts[speciesId] or 0

		if displayedCount <= 0 then
			-- Returning to zero resets the interval, preventing an instant award
			-- when a display later reappears after plot loss or reconciliation.
			playerTimers[speciesId] = nil
		else
			local nextProductionTime = playerTimers[speciesId]
			if not nextProductionTime then
				playerTimers[speciesId] = now + definition.HypeIntervalSeconds
			elseif now >= nextProductionTime then
				local award = displayedCount * definition.HypePerInterval
				totalAward += award
				table.insert(contributions, string.format("%s:%d", speciesId, displayedCount))

				-- Scheduling from this evaluation avoids catch-up bursts after stalls.
				playerTimers[speciesId] = now + definition.HypeIntervalSeconds
			end
		end
	end

	if totalAward <= 0 then
		return
	end

	if PlayerStateService.AddHype(player, totalAward) then
		print(
			string.format(
				"[ODDWORKS][HypeService] %s +%d Hype from displayed Oddlings (%s).",
				player.Name,
				totalAward,
				table.concat(contributions, ", ")
			)
		)
	else
		warn(string.format("[ODDWORKS][HypeService] Failed to award Hype to %s.", player.Name))
	end
end

-- One bounded server loop evaluates every active player and species. Timing and
-- display counts never cross the client/server trust boundary.
local function runProductionLoop()
	task.spawn(function()
		while true do
			task.wait(PRODUCTION_POLL_SECONDS)
			local now = os.clock()

			for _, player in ipairs(Players:GetPlayers()) do
				evaluatePlayer(player, now)
			end
		end
	end)
end

-- Starts after PlayerStateService and OddlingDisplayService. Cleanup prevents
-- stale Player references from surviving beyond the live server session.
function HypeService.Start()
	if started then
		return
	end

	productionDefinitions = loadProductionDefinitions()
	started = true

	Players.PlayerRemoving:Connect(function(player: Player)
		nextProductionTimes[player] = nil
	end)

	runProductionLoop()
	print(string.format("[ODDWORKS][HypeService] Service started with %d producing species.", #productionDefinitions))
end

return HypeService
