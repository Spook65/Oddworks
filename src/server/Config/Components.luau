--!strict

export type ComponentSlot = "Head" | "Arm" | "Legs"
export type ComponentRarity = "Common" | "Rare" | "Legendary"

export type ComponentDefinition = {
	ComponentId: string,
	DisplayName: string,
	Slot: ComponentSlot,
	CompatibleFrames: { [string]: boolean },
}

local Components = {}

local definitions: { [string]: ComponentDefinition } = {
	ClownMask = {
		ComponentId = "ClownMask",
		DisplayName = "Clown Mask",
		Slot = "Head",
		CompatibleFrames = { SmallBiped_v1 = true },
	},
	SignalScanner = {
		ComponentId = "SignalScanner",
		DisplayName = "Signal Scanner",
		Slot = "Head",
		CompatibleFrames = { SmallBiped_v1 = true },
	},
	RustClaw = {
		ComponentId = "RustClaw",
		DisplayName = "Rust Claw",
		Slot = "Arm",
		CompatibleFrames = { SmallBiped_v1 = true },
	},
	ServoArm = {
		ComponentId = "ServoArm",
		DisplayName = "Servo Arm",
		Slot = "Arm",
		CompatibleFrames = { SmallBiped_v1 = true },
	},
	StitchedBoots = {
		ComponentId = "StitchedBoots",
		DisplayName = "Stitched Boots",
		Slot = "Legs",
		CompatibleFrames = { SmallBiped_v1 = true },
	},
	SpringLegs = {
		ComponentId = "SpringLegs",
		DisplayName = "Spring Legs",
		Slot = "Legs",
		CompatibleFrames = { SmallBiped_v1 = true },
	},
}

local validRarities: { [string]: boolean } = {
	Common = true,
	Rare = true,
	Legendary = true,
}

-- Definitions are copied at the server-config boundary so callers cannot
-- change component identity or slot compatibility after validating an ID.
local function copyDefinition(definition: ComponentDefinition): ComponentDefinition
	return {
		ComponentId = definition.ComponentId,
		DisplayName = definition.DisplayName,
		Slot = definition.Slot,
		CompatibleFrames = table.clone(definition.CompatibleFrames),
	}
end

function Components.GetDefinition(componentId: string): ComponentDefinition?
	local definition = definitions[componentId]
	if not definition then
		return nil
	end

	return copyDefinition(definition)
end

-- Stable ordering keeps snapshots and future assembler presentation deterministic.
function Components.GetAllDefinitions(): { ComponentDefinition }
	local result: { ComponentDefinition } = {}
	for _, definition in pairs(definitions) do
		table.insert(result, copyDefinition(definition))
	end

	table.sort(result, function(left: ComponentDefinition, right: ComponentDefinition): boolean
		return left.ComponentId < right.ComponentId
	end)
	return result
end

function Components.IsValidRarity(rarity: string): boolean
	return validRarities[rarity] == true
end

function Components.IsCompatibleWithFrame(componentId: string, frameId: string): boolean
	local definition = definitions[componentId]
	return definition ~= nil and definition.CompatibleFrames[frameId] == true
end

return Components
