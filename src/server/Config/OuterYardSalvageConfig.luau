--!strict

export type OpportunityDefinition = {
	OpportunityId: string,
	WorldObjectName: string,
	ComponentId: string,
	Rarity: string,
	Quantity: number,
	MaxValidDistance: number,
}

local OuterYardSalvageConfig = {}

local definitions: { OpportunityDefinition } = {
	{
		OpportunityId = "OuterYardClownMask",
		WorldObjectName = "OuterYardClownMaskCache",
		ComponentId = "ClownMask",
		Rarity = "Common",
		Quantity = 1,
		MaxValidDistance = 12,
	},
	{
		OpportunityId = "OuterYardRustClaw",
		WorldObjectName = "OuterYardRustClawCache",
		ComponentId = "RustClaw",
		Rarity = "Common",
		Quantity = 1,
		MaxValidDistance = 12,
	},
	{
		OpportunityId = "OuterYardStitchedBoots",
		WorldObjectName = "OuterYardStitchedBootsCache",
		ComponentId = "StitchedBoots",
		Rarity = "Common",
		Quantity = 1,
		MaxValidDistance = 12,
	},
}

local function copyDefinition(definition: OpportunityDefinition): OpportunityDefinition
	return table.clone(definition)
end

function OuterYardSalvageConfig.GetAllOpportunities(): { OpportunityDefinition }
	local copies: { OpportunityDefinition } = {}
	for _, definition in ipairs(definitions) do
		table.insert(copies, copyDefinition(definition))
	end
	return copies
end

return OuterYardSalvageConfig
