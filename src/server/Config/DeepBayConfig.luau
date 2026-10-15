--!strict

export type DeepBayDefinition = {
	WorldModelName: string,
	HazardVolumeName: string,
	PhaseIndicatorName: string,
	EntranceIndicatorName: string,
	SafeReturnMarkerName: string,
	ScannerCacheName: string,
	ScannerClaimVolumeName: string,
	WarningSeconds: number,
	SweepSeconds: number,
	SafeSeconds: number,
	HazardPollSeconds: number,
	ScannerAttemptIntervalSeconds: number,
	ScannerMaxValidDistance: number,
	ScannerComponentId: string,
	ScannerRarity: string,
	ScannerQuantity: number,
}

local DeepBayConfig = {}

local definition: DeepBayDefinition = {
	WorldModelName = "DeepBay",
	HazardVolumeName = "MagneticSweeperVolume",
	PhaseIndicatorName = "SweeperPhaseIndicator",
	EntranceIndicatorName = "EntranceIndicator",
	SafeReturnMarkerName = "SafeReturnMarker",
	ScannerCacheName = "SignalScannerCache",
	ScannerClaimVolumeName = "SignalScannerClaimVolume",
	WarningSeconds = 3,
	SweepSeconds = 2.5,
	SafeSeconds = 4,
	HazardPollSeconds = 0.1,
	ScannerAttemptIntervalSeconds = 0.25,
	ScannerMaxValidDistance = 7,
	ScannerComponentId = "SignalScanner",
	ScannerRarity = "Rare",
	ScannerQuantity = 1,
}

function DeepBayConfig.GetDefinition(): DeepBayDefinition
	return table.clone(definition)
end

return DeepBayConfig
