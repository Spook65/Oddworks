--!strict

export type OddlingDefinition = {
	SpeciesId: string,
	HypePerInterval: number,
	HypeIntervalSeconds: number,
}

local Oddlings = {}

-- Production rates stay server-only because clients may display Hype, but they
-- must never decide how quickly an Oddling creates authoritative progression.
local definitions: { [string]: OddlingDefinition } = {
	Toastmarshal = {
		SpeciesId = "Toastmarshal",
		HypePerInterval = 1,
		HypeIntervalSeconds = 10,
	},
}

-- Returns a defensive copy so callers cannot edit the authoritative production
-- definition after looking it up.
function Oddlings.GetDefinition(speciesId: string): OddlingDefinition?
	local definition = definitions[speciesId]
	if not definition then
		return nil
	end

	return {
		SpeciesId = definition.SpeciesId,
		HypePerInterval = definition.HypePerInterval,
		HypeIntervalSeconds = definition.HypeIntervalSeconds,
	}
end

return Oddlings
