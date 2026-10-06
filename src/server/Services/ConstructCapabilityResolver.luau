--!strict

local Services = script.Parent
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))

local ConstructCapabilityResolver = {}

local SIGNAL_SCANNER_COMPONENT_ID = "SignalScanner"

-- Capabilities are projections of the current authoritative Construct. This
-- module owns no state, cleanup, replication, or persistence of its own.
function ConstructCapabilityResolver.CanDetectStrangeSignals(player: Player): boolean
	local snapshot = ModularPrototypeStateService.GetSnapshot(player)
	local construct = if snapshot then snapshot.PrototypeConstruct else nil
	return construct ~= nil and construct.Head.ComponentId == SIGNAL_SCANNER_COMPONENT_ID
end

return ConstructCapabilityResolver
