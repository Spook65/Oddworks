--!strict

export type VariantDefinition = {
	VariantId: string,
	DisplayName: string,
	Weight: number,
	RarityLabel: string,
	AccentColor: Color3,
	RevealIntensity: number,
}

local OddlingVariants = {}

local definitions: { [string]: { VariantDefinition } } = {
	Voltlet = {
		{
			VariantId = "Standard",
			DisplayName = "Standard",
			Weight = 75,
			RarityLabel = "STANDARD",
			AccentColor = Color3.fromRGB(58, 225, 255),
			RevealIntensity = 1,
		},
		{
			VariantId = "Charged",
			DisplayName = "Charged",
			Weight = 20,
			RarityLabel = "UNCOMMON",
			AccentColor = Color3.fromRGB(126, 246, 255),
			RevealIntensity = 1.35,
		},
		{
			VariantId = "Overclocked",
			DisplayName = "Overclocked",
			Weight = 5,
			RarityLabel = "RARE",
			AccentColor = Color3.fromRGB(228, 252, 255),
			RevealIntensity = 1.8,
		},
	},
	Kilnback = {
		{
			VariantId = "Standard",
			DisplayName = "Standard",
			Weight = 75,
			RarityLabel = "STANDARD",
			AccentColor = Color3.fromRGB(255, 128, 35),
			RevealIntensity = 1,
		},
		{
			VariantId = "Tempered",
			DisplayName = "Tempered",
			Weight = 20,
			RarityLabel = "UNCOMMON",
			AccentColor = Color3.fromRGB(255, 190, 62),
			RevealIntensity = 1.35,
		},
		{
			VariantId = "Molten",
			DisplayName = "Molten",
			Weight = 5,
			RarityLabel = "RARE",
			AccentColor = Color3.fromRGB(255, 73, 34),
			RevealIntensity = 1.8,
		},
	},
}

local function copyVariant(definition: VariantDefinition): VariantDefinition
	return {
		VariantId = definition.VariantId,
		DisplayName = definition.DisplayName,
		Weight = definition.Weight,
		RarityLabel = definition.RarityLabel,
		AccentColor = definition.AccentColor,
		RevealIntensity = definition.RevealIntensity,
	}
end

function OddlingVariants.GetVariants(speciesId: string): { VariantDefinition }?
	local speciesDefinitions = definitions[speciesId]
	if not speciesDefinitions then
		return nil
	end
	local result: { VariantDefinition } = {}
	for _, definition in ipairs(speciesDefinitions) do
		table.insert(result, copyVariant(definition))
	end
	return result
end

function OddlingVariants.GetConfiguredSpeciesIds(): { string }
	local result: { string } = {}
	for speciesId in pairs(definitions) do
		table.insert(result, speciesId)
	end
	table.sort(result)
	return result
end

return OddlingVariants
