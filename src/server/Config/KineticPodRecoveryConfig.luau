--!strict

export type KineticPodRecoveryDefinition = {
	WorldModelName: string,
	InteractionPartName: string,
	WardenSpawnMarkerName: string,
	SiteMarkerName: string,
	SecureZoneName: string,
	AssemblerName: string,
	FurnaceWorldModelName: string,
	FurnaceInteractionPartName: string,
	MaxStealDistance: number,
	AttemptIntervalSeconds: number,
	HeadStartSeconds: number,
	SpringLegsSpeedMultiplier: number,
	PollSeconds: number,
	CatchRadius: number,
	StageOneSeconds: number,
	StageTwoSeconds: number,
	StageSpeeds: { number },
	ResetSeconds: number,
	SuccessCooldownSeconds: number,
	RewardSpeciesId: string,
	RewardSpeciesCount: number,
	RewardComponentId: string,
	RewardRarity: string,
	RewardCount: number,
}

local KineticPodRecoveryConfig = {}

local definition: KineticPodRecoveryDefinition = {
	WorldModelName = "KineticPodTarget",
	InteractionPartName = "PodShell",
	WardenSpawnMarkerName = "WardenSpawnMarker",
	SiteMarkerName = "SiteMarker",
	SecureZoneName = "FurnacePodSecureZone",
	AssemblerName = "PrototypeAssembler",
	FurnaceWorldModelName = "FurnacePodTarget",
	FurnaceInteractionPartName = "PodShell",
	MaxStealDistance = 9,
	AttemptIntervalSeconds = 0.75,
	HeadStartSeconds = 2.5,
	SpringLegsSpeedMultiplier = 1.20,
	PollSeconds = 0.1,
	CatchRadius = 3.75,
	StageOneSeconds = 2,
	StageTwoSeconds = 5,
	StageSpeeds = { 8.5, 12.5, 16.5 },
	ResetSeconds = 2,
	SuccessCooldownSeconds = 20,
	RewardSpeciesId = "Voltlet",
	RewardSpeciesCount = 1,
	RewardComponentId = "SpringLegs",
	RewardRarity = "Common",
	RewardCount = 1,
}

function KineticPodRecoveryConfig.GetDefinition(): KineticPodRecoveryDefinition
	local copy = table.clone(definition)
	copy.StageSpeeds = table.clone(definition.StageSpeeds)
	return copy
end

return KineticPodRecoveryConfig
