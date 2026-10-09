--!strict

export type FurnacePodChaseDefinition = {
	WorldModelName: string,
	InteractionPartName: string,
	WardenSpawnMarkerName: string,
	RouteModelName: string,
	WorkshopAreaMarkerName: string,
	SafeRouteMarkerName: string,
	ShortcutMarkerName: string,
	FurnaceSiteMarkerName: string,
	SecureZoneName: string,
	MaxStealDistance: number,
	AttemptIntervalSeconds: number,
	ConfirmationIntervalSeconds: number,
	ConfirmationLifetimeSeconds: number,
	HeadStartSeconds: number,
	SpringLegsSpeedMultiplier: number,
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
	RouteModelName = "FurnaceRoutePrototype",
	WorkshopAreaMarkerName = "WorkshopAreaMarker",
	SafeRouteMarkerName = "SafeRouteMarker",
	ShortcutMarkerName = "ShortcutMarker",
	FurnaceSiteMarkerName = "FurnaceSiteMarker",
	SecureZoneName = "FurnacePodSecureZone",
	MaxStealDistance = 9,
	AttemptIntervalSeconds = 0.75,
	ConfirmationIntervalSeconds = 0.25,
	ConfirmationLifetimeSeconds = 30,
	HeadStartSeconds = 2.5,
	SpringLegsSpeedMultiplier = 1.20,
	PollSeconds = 0.1,
	CatchRadius = 3.75,
	StageOneSeconds = 2,
	StageTwoSeconds = 5,
	StageSpeeds = { 10.5, 14.5, 18.0 },
	ResetSeconds = 2,
	RevealDelaySeconds = 2,
}

function FurnacePodChaseConfig.GetDefinition(): FurnacePodChaseDefinition
	local copy = table.clone(definition)
	copy.StageSpeeds = table.clone(definition.StageSpeeds)
	return copy
end

return FurnacePodChaseConfig
