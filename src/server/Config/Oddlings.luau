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
