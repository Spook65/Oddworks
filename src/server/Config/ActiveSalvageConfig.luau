--!strict

export type WeightedComponent = {
	ComponentId: string,
	Weight: number,
}

export type WeightedRarity = {
	Rarity: string,
	Weight: number,
}

export type EncounterDefinition = {
	EncounterId: string,
	StageCount: number,
	StageDurationSeconds: number,
	WindowStartSeconds: number,
	WindowEndSeconds: number,
	InterstageDelaySeconds: number,
	FailureResetSeconds: number,
	SuccessCooldownSeconds: number,
	MaxValidDistance: number,
	InputMinimumIntervalSeconds: number,
	RewardQuantity: number,
	ComponentWeights: { WeightedComponent },
	RarityWeights: { WeightedRarity },
}

local ActiveSalvageConfig = {}

local JAMMED_WRECK_ID = "JammedSalvageWreck"

-- Timing is deliberately forgiving: the 1.2-second success window is much
-- wider than ordinary Roblox latency, while the server still owns the clock.
local definition: EncounterDefinition = {
	EncounterId = JAMMED_WRECK_ID,
	StageCount = 3,
	StageDurationSeconds = 2.4,
	WindowStartSeconds = 0.7,
	WindowEndSeconds = 1.9,
	InterstageDelaySeconds = 0.45,
	FailureResetSeconds = 2,
	SuccessCooldownSeconds = 3,
	MaxValidDistance = 12,
	InputMinimumIntervalSeconds = 0.25,
	RewardQuantity = 1,
	ComponentWeights = {
		{ ComponentId = "ClownMask", Weight = 1 },
		{ ComponentId = "SignalScanner", Weight = 1 },
		{ ComponentId = "RustClaw", Weight = 1 },
		{ ComponentId = "ServoArm", Weight = 1 },
		{ ComponentId = "StitchedBoots", Weight = 1 },
		{ ComponentId = "SpringLegs", Weight = 1 },
	},
	RarityWeights = {
		{ Rarity = "Common", Weight = 80 },
		{ Rarity = "Rare", Weight = 18 },
		{ Rarity = "Legendary", Weight = 2 },
	},
}

-- The service receives a fresh nested copy so reward/timing authority cannot
-- be mutated by another server module after startup.
function ActiveSalvageConfig.GetEncounter(encounterId: string): EncounterDefinition?
	if encounterId ~= JAMMED_WRECK_ID then
		return nil
	end

	local componentWeights: { WeightedComponent } = {}
	for _, entry in ipairs(definition.ComponentWeights) do
		table.insert(componentWeights, {
			ComponentId = entry.ComponentId,
			Weight = entry.Weight,
		})
	end

	local rarityWeights: { WeightedRarity } = {}
	for _, entry in ipairs(definition.RarityWeights) do
		table.insert(rarityWeights, {
			Rarity = entry.Rarity,
			Weight = entry.Weight,
		})
	end

	return {
		EncounterId = definition.EncounterId,
		StageCount = definition.StageCount,
		StageDurationSeconds = definition.StageDurationSeconds,
		WindowStartSeconds = definition.WindowStartSeconds,
		WindowEndSeconds = definition.WindowEndSeconds,
		InterstageDelaySeconds = definition.InterstageDelaySeconds,
		FailureResetSeconds = definition.FailureResetSeconds,
		SuccessCooldownSeconds = definition.SuccessCooldownSeconds,
		MaxValidDistance = definition.MaxValidDistance,
		InputMinimumIntervalSeconds = definition.InputMinimumIntervalSeconds,
		RewardQuantity = definition.RewardQuantity,
		ComponentWeights = componentWeights,
		RarityWeights = rarityWeights,
	}
end

return ActiveSalvageConfig
