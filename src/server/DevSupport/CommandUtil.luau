--!strict

local DevSupport = script.Parent
local ServerRoot = assert(DevSupport.Parent, "[ODDWORKS][DEV] DevSupport folder must have a parent.")
local Services = ServerRoot:WaitForChild("Services")
local Config = ServerRoot:WaitForChild("Config")

local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local OddlingDisplayService = require(Services:WaitForChild("OddlingDisplayService"))
local Oddlings = require(Config:WaitForChild("Oddlings"))
local Recipes = require(Config:WaitForChild("Recipes"))
local WorkshopLevels = require(Config:WaitForChild("WorkshopLevels"))

local CommandUtil = {}

-- Studio commands remain bounded even though they are development-only. Keeping
-- caps together prevents one command from silently drifting to a riskier limit.
local MUTATION_CAPS = table.freeze({
	ScrapPerInvocation = 1_000_000,
	HypePerInvocation = 1_000_000,
	OddlingsPerInvocation = 100,
})

-- Revalidates numeric arguments at the production API boundary because Cmdr's
-- parser improves UX but is not the authority for state mutation correctness.
local function isPositiveFiniteInteger(value: number): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
		and math.floor(value) == value
end

-- Produces stable map output so repeated inspections are easy to compare.
local function formatNumberMap(values: { [string]: number }): string
	local keys: { string } = {}
	for key in pairs(values) do
		table.insert(keys, key)
	end
	table.sort(keys)

	if #keys == 0 then
		return "<none>"
	end

	local entries: { string } = {}
	for _, key in ipairs(keys) do
		table.insert(entries, string.format("%s=%d", key, values[key]))
	end
	return table.concat(entries, ", ")
end

-- Formats enabled recipe IDs without returning the mutable snapshot table.
local function formatEnabledSet(values: { [string]: boolean }): string
	local keys: { string } = {}
	for key, enabled in pairs(values) do
		if enabled then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return if #keys > 0 then table.concat(keys, ", ") else "<none>"
end

-- Logs only high-level mutation metadata so setup actions are auditable without
-- dumping complete player state into server Output.
function CommandUtil.LogMutation(context: any, commandName: string, target: Player, mutation: string)
	local executor = context.Executor :: Player
	print(
		string.format(
			"[ODDWORKS][DEV][%s] %s (%d) -> %s (%d): %s",
			commandName,
			executor.Name,
			executor.UserId,
			target.Name,
			target.UserId,
			mutation
		)
	)
end

-- Returns a read-only textual view built from PlayerStateService's defensive snapshot.
function CommandUtil.DescribeState(player: Player): string
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot then
		return string.format("No authoritative ODDWORKS state exists for %s.", player.Name)
	end

	local revealedRecipes: { [string]: boolean } = {}
	for _, recipe in ipairs(Recipes.GetAllRecipes()) do
		if snapshot.WorkshopLevel >= recipe.RequiredWorkshopLevel then
			revealedRecipes[recipe.RecipeId] = true
		end
	end

	return string.format(
		"%s | Scrap=%d | Hype=%d | WorkshopLevel=%d | Plot=%s | Owned={%s} | Unlocked={%s} | Revealed={%s}",
		player.Name,
		snapshot.Scrap,
		snapshot.Hype,
		snapshot.WorkshopLevel,
		snapshot.AssignedPlotId or "<none>",
		formatNumberMap(snapshot.OwnedOddlings),
		formatEnabledSet(snapshot.UnlockedRecipes),
		formatEnabledSet(revealedRecipes)
	)
end

-- Uses the existing narrow Scrap mutation API; the command never touches private state.
function CommandUtil.GiveScrap(context: any, player: Player, amount: number): string
	if not isPositiveFiniteInteger(amount) or amount > MUTATION_CAPS.ScrapPerInvocation then
		return string.format("Scrap grant rejected: amount must be between 1 and %d.", MUTATION_CAPS.ScrapPerInvocation)
	end

	if not PlayerStateService.AddScrap(player, amount) then
		return "Scrap grant rejected: target player state is unavailable."
	end

	CommandUtil.LogMutation(context, "ow-give-scrap", player, string.format("+%d Scrap", amount))
	return string.format("Granted %d Scrap to %s.", amount, player.Name)
end

-- Uses production Hype validation and notification behavior instead of a dev-only state write.
function CommandUtil.GiveHype(context: any, player: Player, amount: number): string
	if not isPositiveFiniteInteger(amount) or amount > MUTATION_CAPS.HypePerInvocation then
		return string.format("Hype grant rejected: amount must be between 1 and %d.", MUTATION_CAPS.HypePerInvocation)
	end

	if not PlayerStateService.AddHype(player, amount) then
		return "Hype grant rejected: target player state is unavailable."
	end

	CommandUtil.LogMutation(context, "ow-give-hype", player, string.format("+%d Hype", amount))
	return string.format("Granted %d Hype to %s.", amount, player.Name)
end

-- Validates the species against authoritative server config before calling the
-- same ownership API used by production transactions.
function CommandUtil.GiveOddling(context: any, player: Player, speciesId: string, count: number): string
	if not Oddlings.GetDefinition(speciesId) then
		return string.format("Unknown configured Oddling species: %s", speciesId)
	end

	if not isPositiveFiniteInteger(count) or count > MUTATION_CAPS.OddlingsPerInvocation then
		return string.format(
			"Oddling grant rejected: count must be between 1 and %d.",
			MUTATION_CAPS.OddlingsPerInvocation
		)
	end

	if not PlayerStateService.AddOwnedOddling(player, speciesId, count) then
		return "Oddling grant rejected: target player state is unavailable."
	end

	CommandUtil.LogMutation(context, "ow-give-oddling", player, string.format("+%d %s", count, speciesId))
	return string.format("Granted %d %s ownership to %s.", count, speciesId, player.Name)
end

-- Advances only to the next configured level. It intentionally bypasses Hype
-- cost/proximity for setup, so its result cannot prove the real upgrade flow.
function CommandUtil.AdvanceWorkshop(context: any, player: Player): string
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot then
		return string.format("No authoritative ODDWORKS state exists for %s.", player.Name)
	end

	local definition = WorkshopLevels.GetDefinition(snapshot.WorkshopLevel)
	local nextLevel = definition and definition.NextLevel
	if not nextLevel then
		return string.format("%s is already at the highest configured workshop level.", player.Name)
	end

	if not PlayerStateService.AdvanceWorkshopLevel(player, snapshot.WorkshopLevel, nextLevel) then
		return "Workshop advance was rejected by PlayerStateService."
	end

	CommandUtil.LogMutation(
		context,
		"ow-advance-workshop",
		player,
		string.format("WorkshopLevel %d -> %d (DEV BYPASS)", snapshot.WorkshopLevel, nextLevel)
	)
	return string.format(
		"DEV BYPASS - advanced %s to Workshop Level %d; workshop economy was not tested.",
		player.Name,
		nextLevel
	)
end

-- Returns copied display counts plus server-configured capacity; no clone or
-- internal display bookkeeping is exposed to the command caller.
function CommandUtil.DescribeDisplays(player: Player): string
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot then
		return string.format("No authoritative ODDWORKS state exists for %s.", player.Name)
	end

	local levelDefinition = WorkshopLevels.GetDefinition(snapshot.WorkshopLevel)
	local capacity = if levelDefinition then levelDefinition.DisplayCapacity else 0
	local displayedCounts = OddlingDisplayService.GetDisplayedCounts(player)
	local normalizedCounts: { [string]: number } = {}
	local total = 0
	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		local count = displayedCounts[definition.SpeciesId] or 0
		normalizedCounts[definition.SpeciesId] = count
		total += count
	end

	return string.format(
		"%s | Capacity=%d | TotalDisplayed=%d | Displays={%s}",
		player.Name,
		capacity,
		total,
		formatNumberMap(normalizedCounts)
	)
end

-- Queues the display service's ordinary reconciliation path; ownership remains untouched.
function CommandUtil.ReconcileDisplays(context: any, player: Player): string
	if not OddlingDisplayService.Reconcile(player) then
		return string.format("Could not queue display reconciliation for %s.", player.Name)
	end

	CommandUtil.LogMutation(context, "ow-reconcile", player, "queued derived-display reconciliation")
	return string.format("Queued authoritative display reconciliation for %s.", player.Name)
end

return CommandUtil
