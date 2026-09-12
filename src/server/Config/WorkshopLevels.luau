--!strict

export type WorkshopLevelDefinition = {
	Level: number,
	DisplayCapacity: number,
	UpgradeCost: number?,
	NextLevel: number?,
}

local WorkshopLevels = {}

-- Capacity and upgrade prices stay in one server-only table so clients cannot
-- choose either value and services do not drift onto different balance rules.
local definitions: { [number]: WorkshopLevelDefinition } = {
	[1] = {
		Level = 1,
		DisplayCapacity = 2,
		UpgradeCost = 10,
		NextLevel = 2,
	},
	[2] = {
		Level = 2,
		DisplayCapacity = 4,
		UpgradeCost = nil,
		NextLevel = nil,
	},
}

-- Returns a defensive copy so callers cannot edit authoritative capacity or
-- price configuration after resolving the current workshop level.
function WorkshopLevels.GetDefinition(level: number): WorkshopLevelDefinition?
	local definition = definitions[level]
	if not definition then
		return nil
	end

	return {
		Level = definition.Level,
		DisplayCapacity = definition.DisplayCapacity,
		UpgradeCost = definition.UpgradeCost,
		NextLevel = definition.NextLevel,
	}
end

return WorkshopLevels
