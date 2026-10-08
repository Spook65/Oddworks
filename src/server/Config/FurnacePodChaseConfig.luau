--!strict

export type FurnacePodChaseDefinition = {
	WorldModelName: string,
	InteractionPartName: string,
	WardenSpawnMarkerName: string,
	SecureZoneName: string,
	MaxStealDistance: number,
	AttemptIntervalSeconds: number,
	ConfirmationIntervalSeconds: number,
	ConfirmationLifetimeSeconds: number,
	HeadStartSeconds: number,
	PollSeconds: number,
	CatchRadius: number,
	StageOneSeconds: number,
	StageTwoSeconds: number,
	StageSpeeds: { number },
	ResetSeconds: number,
	RevealDelaySeconds: number,
}

local FurnacePodChaseConfig = {}

local definition: FurnacePodChaseDefinition = {
	WorldModelName = "FurnacePodTarget",
	InteractionPartName = "PodShell",
	WardenSpawnMarkerName = "WardenSpawnMarker",
	SecureZoneName = "FurnacePodSecureZone",
	MaxStealDistance = 9,
	AttemptIntervalSeconds = 0.75,
	ConfirmationIntervalSeconds = 0.25,
	ConfirmationLifetimeSeconds = 30,
	HeadStartSeconds = 2.5,
	PollSeconds = 0.1,
	CatchRadius = 3.75,
	StageOneSeconds = 2,
	StageTwoSeconds = 5,
	StageSpeeds = { 10.5, 15, 19.5 },
	ResetSeconds = 2,
	RevealDelaySeconds = 2,
}

function FurnacePodChaseConfig.GetDefinition(): FurnacePodChaseDefinition
	local copy = table.clone(definition)
	copy.StageSpeeds = table.clone(definition.StageSpeeds)
	return copy
end

return FurnacePodChaseConfig
