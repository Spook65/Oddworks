--!strict

export type OddityContainmentDefinition = {
	WorldModelName: string,
	StartConsoleName: string,
	GateModelNames: { [string]: string },
	WaypointFolderName: string,
	ContainmentVolumeName: string,
	EscapeVolumeName: string,
	MaxStartDistance: number,
	MaxGateDistance: number,
	StartIntervalSeconds: number,
	GateIntervalSeconds: number,
	MovementSpeed: number,
	MovementStepSeconds: number,
	FailureResetSeconds: number,
	SuccessResetSeconds: number,
	RewardComponentId: string,
	RewardRarity: string,
	RewardCount: number,
}

local OddityContainmentConfig = {}

local definition: OddityContainmentDefinition = {
	WorldModelName = "OddityContainmentYard",
	StartConsoleName = "StartConsole",
	GateModelNames = {
		GateA = "GateA",
		GateB = "GateB",
	},
	WaypointFolderName = "Waypoints",
	ContainmentVolumeName = "ContainmentVolume",
	EscapeVolumeName = "EscapeVolume",
	MaxStartDistance = 10,
	MaxGateDistance = 9,
	StartIntervalSeconds = 0.75,
	GateIntervalSeconds = 0.2,
	MovementSpeed = 8,
	MovementStepSeconds = 0.05,
	FailureResetSeconds = 2,
	SuccessResetSeconds = 3,
	RewardComponentId = "ServoArm",
	RewardRarity = "Rare",
	RewardCount = 1,
}

function OddityContainmentConfig.GetDefinition(): OddityContainmentDefinition
	local copy = table.clone(definition)
	copy.GateModelNames = table.clone(definition.GateModelNames)
	return copy
end

return OddityContainmentConfig
