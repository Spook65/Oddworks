--!strict

export type OddlingDefinition = {
	SpeciesId: string,
	HypePerInterval: number?,
	HypeIntervalSeconds: number?,
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
	-- Conejurer has authoritative identity now, but no production behavior until
	-- a later pass installs and displays its runtime prototype.
	Conejurer = {
		SpeciesId = "Conejurer",
		HypePerInterval = nil,
		HypeIntervalSeconds = nil,
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
