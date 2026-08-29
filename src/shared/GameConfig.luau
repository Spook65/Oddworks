local GameConfig = {}

GameConfig.RemotesFolderName = "OddworksRemotes"
GameConfig.CoreGoal = 4

GameConfig.SpawnCFrame = CFrame.new(0, 5, -38)

GameConfig.Keycard = {
	position = Vector3.new(-16, 2.5, -28),
}

GameConfig.Doors = {
	{
		name = "Access Door",
		position = Vector3.new(0, 7, 10),
		size = Vector3.new(14, 14, 1.2),
		requiresKeycard = true,
		requiredCores = 0,
		color = Color3.fromRGB(41, 128, 185),
		lockedMessage = "Find the keycard before opening the access door.",
		promptText = "Use Keycard",
	},
	{
		name = "Vault Door",
		position = Vector3.new(0, 7, 90),
		size = Vector3.new(14, 14, 1.2),
		requiresKeycard = false,
		requiredCores = 4,
		color = Color3.fromRGB(194, 124, 36),
		lockedMessage = "The vault needs more energy cores.",
		promptText = "Open Vault",
	},
}

GameConfig.Cores = {
	{ id = "core-a", name = "Energy Core A", position = Vector3.new(-20, 3, 34) },
	{ id = "core-b", name = "Energy Core B", position = Vector3.new(18, 3, 40) },
	{ id = "core-c", name = "Energy Core C", position = Vector3.new(-12, 3, 58) },
	{ id = "core-d", name = "Energy Core D", position = Vector3.new(21, 3, 66) },
	{ id = "core-e", name = "Energy Core E", position = Vector3.new(-19, 3, 78) },
	{ id = "core-f", name = "Energy Core F", position = Vector3.new(4, 3, 72) },
}

return GameConfig
