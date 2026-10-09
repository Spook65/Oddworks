--!strict

local Services = script.Parent
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))

local ConstructCapabilityResolver = {}

local SIGNAL_SCANNER_COMPONENT_ID = "SignalScanner"
local SPRING_LEGS_COMPONENT_ID = "SpringLegs"

local function getInstalledComponentId(player: Player, slot: string): string?
	local snapshot = ModularPrototypeStateService.GetSnapshot(player)
	if not snapshot or typeof(snapshot.PrototypeConstruct) ~= "table" then
		return nil
	end

	local construct = snapshot.PrototypeConstruct :: any
	local selection = construct[slot]
	if typeof(selection) ~= "table" or typeof(selection.ComponentId) ~= "string" then
		return nil
	end
	return selection.ComponentId
end

-- Capabilities are projections of the current authoritative Construct. This
-- module owns no state, cleanup, replication, or persistence of its own.
function ConstructCapabilityResolver.CanDetectStrangeSignals(player: Player): boolean
	return getInstalledComponentId(player, "Head") == SIGNAL_SCANNER_COMPONENT_ID
end

function ConstructCapabilityResolver.HasSpringLegsChaseCapability(player: Player): boolean
	return getInstalledComponentId(player, "Legs") == SPRING_LEGS_COMPONENT_ID
end

return ConstructCapabilityResolver
