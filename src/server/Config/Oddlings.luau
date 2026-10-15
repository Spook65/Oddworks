--!strict

export type OddlingDefinition = {
	SpeciesId: string,
	TemplateFolderName: string,
	TemplateName: string,
	RootPartName: string,
	AnchorAllParts: boolean,
	IdleAnimationAssetId: string?,
	HypePerInterval: number,
	HypeIntervalSeconds: number,
	IndexVisible: boolean,
	IndexOrder: number,
	IndexNumber: number,
	DisplayName: string,
	Classification: string,
	FlavorText: string,
	RecoverySource: string,
	SecurityTier: string,
	IndexAccentColor: Color3,
}

local Oddlings = {}

-- Production rates stay server-only because clients may display Hype, but they
-- must never decide how quickly an Oddling creates authoritative progression.
local definitions: { [string]: OddlingDefinition } = {
	Toastmarshal = {
		SpeciesId = "Toastmarshal",
		TemplateFolderName = "Oddlings",
		TemplateName = "Toastmarshal_Common",
		RootPartName = "RootPart",
		AnchorAllParts = false,
		IdleAnimationAssetId = "rbxassetid://105040634265875",
		HypePerInterval = 1,
		HypeIntervalSeconds = 10,
		IndexVisible = false,
		IndexOrder = 30,
		IndexNumber = 101,
		DisplayName = "Toastmarshal",
		Classification = "HEARTH ODDLING",
		FlavorText = "Keeps its plating warm enough to toast whatever it finds nearby.",
		RecoverySource = "Workshop Crafting",
		SecurityTier = "WORKSHOP",
		IndexAccentColor = Color3.fromRGB(233, 181, 89),
	},
	-- Conejurer uses a deliberately static prototype. Its provisional production
	-- rate validates multi-species gameplay without implying final art or balance.
	Conejurer = {
		SpeciesId = "Conejurer",
		TemplateFolderName = "Oddlings",
		TemplateName = "Conejurer_Prototype",
		RootPartName = "HumanoidRootPart",
		AnchorAllParts = true,
		IdleAnimationAssetId = nil,
		HypePerInterval = 2,
		HypeIntervalSeconds = 10,
		IndexVisible = false,
		IndexOrder = 40,
		IndexNumber = 102,
		DisplayName = "Conejurer",
		Classification = "WORKSHOP ODDLING",
		FlavorText = "Stacks discarded safety cones into surprisingly deliberate arrangements.",
		RecoverySource = "Workshop Crafting",
		SecurityTier = "WORKSHOP",
		IndexAccentColor = Color3.fromRGB(154, 216, 169),
	},
	Voltlet = {
		SpeciesId = "Voltlet",
		TemplateFolderName = "Oddlings",
		TemplateName = "Voltlet_Prototype",
		RootPartName = "RootPart",
		AnchorAllParts = true,
		IdleAnimationAssetId = nil,
		HypePerInterval = 1,
		HypeIntervalSeconds = 10,
		IndexVisible = true,
		IndexOrder = 10,
		IndexNumber = 1,
		DisplayName = "Voltlet",
		Classification = "KINETIC ODDLING",
		FlavorText = "Stores excess kinetic charge in its coil, then vents it in nervous bursts.",
		RecoverySource = "Kinetic Pod",
		SecurityTier = "LOW",
		IndexAccentColor = Color3.fromRGB(58, 225, 255),
	},
	Kilnback = {
		SpeciesId = "Kilnback",
		TemplateFolderName = "Signatures",
		TemplateName = "Kilnback_Prototype",
		RootPartName = "RootPart",
		AnchorAllParts = true,
		IdleAnimationAssetId = nil,
		HypePerInterval = 3,
		HypeIntervalSeconds = 10,
		IndexVisible = true,
		IndexOrder = 20,
		IndexNumber = 2,
		DisplayName = "Kilnback",
		Classification = "FURNACE ODDLING",
		FlavorText = "Banks furnace heat beneath layered plating and sheds it in slow, glowing waves.",
		RecoverySource = "Furnace Pod",
		SecurityTier = "HIGH",
		IndexAccentColor = Color3.fromRGB(255, 128, 35),
	},
}

-- Copies one definition so callers cannot mutate template, animation, or economy authority.
local function copyDefinition(definition: OddlingDefinition): OddlingDefinition
	return {
		SpeciesId = definition.SpeciesId,
		TemplateFolderName = definition.TemplateFolderName,
		TemplateName = definition.TemplateName,
		RootPartName = definition.RootPartName,
		AnchorAllParts = definition.AnchorAllParts,
		IdleAnimationAssetId = definition.IdleAnimationAssetId,
		HypePerInterval = definition.HypePerInterval,
		HypeIntervalSeconds = definition.HypeIntervalSeconds,
		IndexVisible = definition.IndexVisible,
		IndexOrder = definition.IndexOrder,
		IndexNumber = definition.IndexNumber,
		DisplayName = definition.DisplayName,
		Classification = definition.Classification,
		FlavorText = definition.FlavorText,
		RecoverySource = definition.RecoverySource,
		SecurityTier = definition.SecurityTier,
		IndexAccentColor = definition.IndexAccentColor,
	}
end

-- Returns a defensive copy so callers cannot edit the authoritative production
-- definition after looking it up.
function Oddlings.GetDefinition(speciesId: string): OddlingDefinition?
	local definition = definitions[speciesId]
	if not definition then
		return nil
	end

	return copyDefinition(definition)
end

-- Returns definitions in stable species order for deterministic display allocation and production.
function Oddlings.GetAllDefinitions(): { OddlingDefinition }
	local result: { OddlingDefinition } = {}
	for _, definition in pairs(definitions) do
		table.insert(result, copyDefinition(definition))
	end

	table.sort(result, function(left: OddlingDefinition, right: OddlingDefinition): boolean
		return left.SpeciesId < right.SpeciesId
	end)
	return result
end

return Oddlings
