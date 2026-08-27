local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

type PlayerData = {
	cores: number,
	hasKeycard: boolean,
	completed: boolean,
	checkpoint: CFrame,
	checkpointReached: boolean,
	collectedCores: { [string]: boolean },
}

local remotesFolder = ReplicatedStorage:FindFirstChild(GameConfig.RemotesFolderName)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = GameConfig.RemotesFolderName
	remotesFolder.Parent = ReplicatedStorage
end

local function getRemoteEvent(name: string): RemoteEvent
	local remote = remotesFolder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = name
	newRemote.Parent = remotesFolder
	return newRemote
end

local stateRemote = getRemoteEvent("StateUpdate")
local noticeRemote = getRemoteEvent("Notice")

local playerData: { [Player]: PlayerData } = {}
local generatedWorld = Workspace:FindFirstChild("OddworksArena")
if generatedWorld then
	generatedWorld:Destroy()
end

Workspace.FallenPartsDestroyHeight = -100

local arena = Instance.new("Folder")
arena.Name = "OddworksArena"
arena.Parent = Workspace

local function createPart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent or arena
	return part
end

local function notify(player: Player, message: string)
	noticeRemote:FireClient(player, message)
end

local function objectiveFor(data: PlayerData): string
	if data.completed then
		return "Run complete"
	end

	if not data.hasKeycard then
		return "Find the keycard"
	end

	if data.cores < GameConfig.CoreGoal then
		return string.format("Collect energy cores: %d/%d", data.cores, GameConfig.CoreGoal)
	end

	return "Open the vault door"
end

local function pushState(player: Player)
	local data = playerData[player]
	if not data then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coresValue = leaderstats:FindFirstChild("Cores")
		if coresValue and coresValue:IsA("IntValue") then
			coresValue.Value = data.cores
		end
	end

	stateRemote:FireClient(player, {
		cores = data.cores,
		requiredCores = GameConfig.CoreGoal,
		hasKeycard = data.hasKeycard,
		completed = data.completed,
		objective = objectiveFor(data),
	})
end

local function getPlayerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function buildArena()
	Lighting.ClockTime = 15
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.25

	createPart("Start Floor", Vector3.new(58, 1, 50), CFrame.new(0, 0, -20), Color3.fromRGB(58, 63, 72), Enum.Material.Concrete)
	createPart("Training Floor", Vector3.new(58, 1, 80), CFrame.new(0, 0, 50), Color3.fromRGB(52, 72, 66), Enum.Material.Concrete)
	createPart("Vault Floor", Vector3.new(44, 1, 50), CFrame.new(0, 0, 125), Color3.fromRGB(65, 61, 78), Enum.Material.Concrete)

	createPart("Start Back Wall", Vector3.new(58, 12, 2), CFrame.new(0, 6, -46), Color3.fromRGB(31, 35, 42), Enum.Material.Metal)
	createPart("Start Left Wall", Vector3.new(2, 12, 50), CFrame.new(-30, 6, -20), Color3.fromRGB(31, 35, 42), Enum.Material.Metal)
	createPart("Start Right Wall", Vector3.new(2, 12, 50), CFrame.new(30, 6, -20), Color3.fromRGB(31, 35, 42), Enum.Material.Metal)

	createPart("Training Left Wall", Vector3.new(2, 12, 82), CFrame.new(-30, 6, 50), Color3.fromRGB(30, 49, 46), Enum.Material.Metal)
	createPart("Training Right Wall", Vector3.new(2, 12, 82), CFrame.new(30, 6, 50), Color3.fromRGB(30, 49, 46), Enum.Material.Metal)
	createPart("Training Ceiling Rail", Vector3.new(56, 1, 2), CFrame.new(0, 13, 50), Color3.fromRGB(84, 98, 92), Enum.Material.Metal)

	createPart("Vault Left Wall", Vector3.new(2, 12, 50), CFrame.new(-23, 6, 125), Color3.fromRGB(42, 38, 54), Enum.Material.Metal)
	createPart("Vault Right Wall", Vector3.new(2, 12, 50), CFrame.new(23, 6, 125), Color3.fromRGB(42, 38, 54), Enum.Material.Metal)
	createPart("Vault Back Wall", Vector3.new(44, 12, 2), CFrame.new(0, 6, 151), Color3.fromRGB(42, 38, 54), Enum.Material.Metal)

	for _, z in ipairs({ 10, 90 }) do
		createPart("Door Frame Left", Vector3.new(3, 16, 3), CFrame.new(-9.5, 8, z), Color3.fromRGB(24, 28, 34), Enum.Material.Metal)
		createPart("Door Frame Right", Vector3.new(3, 16, 3), CFrame.new(9.5, 8, z), Color3.fromRGB(24, 28, 34), Enum.Material.Metal)
		createPart("Door Frame Top", Vector3.new(22, 3, 3), CFrame.new(0, 15, z), Color3.fromRGB(24, 28, 34), Enum.Material.Metal)
		createPart("Door Wall Left", Vector3.new(18, 12, 2), CFrame.new(-20, 6, z), Color3.fromRGB(31, 35, 42), Enum.Material.Metal)
		createPart("Door Wall Right", Vector3.new(18, 12, 2), CFrame.new(20, 6, z), Color3.fromRGB(31, 35, 42), Enum.Material.Metal)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(GameConfig.SpawnCFrame.Position - Vector3.new(0, 4.4, 0))
	spawn.Color = Color3.fromRGB(70, 150, 90)
	spawn.Material = Enum.Material.Neon
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = arena
end

local function buildDoors()
	for _, doorConfig in ipairs(GameConfig.Doors) do
		local door = createPart(
			doorConfig.name,
			doorConfig.size,
			CFrame.new(doorConfig.position),
			doorConfig.color,
			Enum.Material.Metal
		)
		local closedCFrame = door.CFrame
		local openCFrame = closedCFrame * CFrame.new(0, doorConfig.size.Y + 2, 0)
		local isOpen = false
		local moving = false

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = doorConfig.promptText
		prompt.ObjectText = doorConfig.name
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 12
		prompt.Parent = door

		prompt.Triggered:Connect(function(player: Player)
			local data = playerData[player]
			if not data or moving then
				return
			end

			if doorConfig.requiresKeycard and not data.hasKeycard then
				notify(player, doorConfig.lockedMessage)
				return
			end

			if data.cores < doorConfig.requiredCores then
				notify(player, string.format("%s %d/%d", doorConfig.lockedMessage, data.cores, doorConfig.requiredCores))
				return
			end

			moving = true
			isOpen = not isOpen
			door.CanCollide = not isOpen
			prompt.ActionText = if isOpen then "Close" else doorConfig.promptText

			local tween = TweenService:Create(
				door,
				TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = if isOpen then openCFrame else closedCFrame }
			)
			tween:Play()
			tween.Completed:Wait()
			moving = false
		end)
	end
end

local function buildKeycard()
	local keycard = createPart("Keycard", Vector3.new(3.2, 0.2, 2), CFrame.new(GameConfig.Keycard.position), Color3.fromRGB(72, 199, 142), Enum.Material.Neon)
	keycard.CanCollide = false

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"
	prompt.ObjectText = "Keycard"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.Parent = keycard

	prompt.Triggered:Connect(function(player: Player)
		local data = playerData[player]
		if not data then
			return
		end

		if data.hasKeycard then
			notify(player, "You already have the keycard.")
			return
		end

		data.hasKeycard = true
		notify(player, "Keycard acquired.")
		pushState(player)
	end)
end

local function buildCores()
	local coresFolder = Instance.new("Folder")
	coresFolder.Name = "EnergyCores"
	coresFolder.Parent = arena

	local coreParts = {}
	for _, coreConfig in ipairs(GameConfig.Cores) do
		local core = createPart(
			"Energy Core",
			Vector3.new(2.5, 2.5, 2.5),
			CFrame.new(coreConfig.position),
			Color3.fromRGB(252, 220, 88),
			Enum.Material.Neon,
			coresFolder
		)
		core.Shape = Enum.PartType.Ball
		core.CanCollide = false
		core:SetAttribute("CoreId", coreConfig.id)

		local light = Instance.new("PointLight")
		light.Color = core.Color
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = core

		table.insert(coreParts, core)

		core.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromHit(hit)
			if not player then
				return
			end

			local data = playerData[player]
			if not data or data.collectedCores[coreConfig.id] then
				return
			end

			data.collectedCores[coreConfig.id] = true
			data.cores += 1
			notify(player, string.format("Energy core collected: %d/%d", data.cores, GameConfig.CoreGoal))
			pushState(player)
		end)
	end

	RunService.Heartbeat:Connect(function(deltaTime: number)
		for index, core in ipairs(coreParts) do
			core.CFrame *= CFrame.Angles(0, deltaTime * (1.2 + index * 0.05), 0)
		end
	end)
end

local function buildGuideNpc()
	local model = Instance.new("Model")
	model.Name = "Guide"
	model.Parent = arena

	local rootCFrame = CFrame.new(12, 3, -30)
	local root = createPart("HumanoidRootPart", Vector3.new(2, 2, 1), rootCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	root.CanCollide = false

	local torso = createPart("Torso", Vector3.new(2.4, 3, 1.2), rootCFrame * CFrame.new(0, 0.4, 0), Color3.fromRGB(64, 142, 191), Enum.Material.SmoothPlastic, model)
	local head = createPart("Head", Vector3.new(2, 2, 2), rootCFrame * CFrame.new(0, 3, 0), Color3.fromRGB(235, 198, 150), Enum.Material.SmoothPlastic, model)
	local leftArm = createPart("Left Arm", Vector3.new(0.8, 2.8, 0.8), rootCFrame * CFrame.new(-1.7, 0.3, 0), Color3.fromRGB(64, 142, 191), Enum.Material.SmoothPlastic, model)
	local rightArm = createPart("Right Arm", Vector3.new(0.8, 2.8, 0.8), rootCFrame * CFrame.new(1.7, 0.3, 0), Color3.fromRGB(64, 142, 191), Enum.Material.SmoothPlastic, model)
	local leftLeg = createPart("Left Leg", Vector3.new(0.9, 2.6, 0.9), rootCFrame * CFrame.new(-0.55, -2.3, 0), Color3.fromRGB(38, 44, 58), Enum.Material.SmoothPlastic, model)
	local rightLeg = createPart("Right Leg", Vector3.new(0.9, 2.6, 0.9), rootCFrame * CFrame.new(0.55, -2.3, 0), Color3.fromRGB(38, 44, 58), Enum.Material.SmoothPlastic, model)

	for _, bodyPart in ipairs({ torso, head, leftArm, rightArm, leftLeg, rightLeg }) do
		bodyPart.CanCollide = false
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Guide"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(160, 44)
	billboard.StudsOffset = Vector3.new(0, 2.7, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "Guide"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Guide"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.Parent = torso

	prompt.Triggered:Connect(function(player: Player)
		local data = playerData[player]
		if not data then
			return
		end

		notify(player, "Grab the keycard, collect four energy cores, then open the vault.")
	end)
end

local function buildPatrolHazard()
	local bot = createPart("Patrol Bot", Vector3.new(4, 4, 4), CFrame.new(-22, 3, 56), Color3.fromRGB(221, 72, 72), Enum.Material.Neon)
	bot.Shape = Enum.PartType.Ball
	bot.CanCollide = false

	local light = Instance.new("PointLight")
	light.Color = bot.Color
	light.Range = 18
	light.Brightness = 2
	light.Parent = bot

	local cooldowns: { [Player]: number } = {}
	bot.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end

		local now = os.clock()
		if cooldowns[player] and now - cooldowns[player] < 2 then
			return
		end
		cooldowns[player] = now

		local data = playerData[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if data and root and root:IsA("BasePart") then
			root.CFrame = data.checkpoint
			notify(player, "Patrol hit. Resetting to checkpoint.")
		end
	end)

	task.spawn(function()
		local points = {
			CFrame.new(-22, 3, 56),
			CFrame.new(22, 3, 56),
			CFrame.new(22, 3, 76),
			CFrame.new(-22, 3, 76),
		}
		local index = 1

		while bot.Parent do
			index = (index % #points) + 1
			local tween = TweenService:Create(bot, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				CFrame = points[index],
			})
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

local function buildCheckpointsAndFinish()
	local checkpoint = createPart("Checkpoint", Vector3.new(16, 0.6, 8), CFrame.new(0, 0.75, 22), Color3.fromRGB(86, 174, 132), Enum.Material.Neon)
	checkpoint.CanCollide = false
	checkpoint.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end

		local data = playerData[player]
		if data and not data.checkpointReached then
			data.checkpoint = CFrame.new(0, 5, 22)
			data.checkpointReached = true
			notify(player, "Checkpoint saved.")
		end
	end)

	local finish = createPart("Finish Pad", Vector3.new(18, 0.7, 14), CFrame.new(0, 0.85, 135), Color3.fromRGB(132, 101, 214), Enum.Material.Neon)
	finish.CanCollide = false
	finish.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end

		local data = playerData[player]
		if not data then
			return
		end

		if data.cores < GameConfig.CoreGoal then
			notify(player, string.format("Collect %d more energy cores.", GameConfig.CoreGoal - data.cores))
			return
		end

		if data.completed then
			return
		end

		data.completed = true

		local leaderstats = player:FindFirstChild("leaderstats")
		local wins = leaderstats and leaderstats:FindFirstChild("Wins")
		if wins and wins:IsA("IntValue") then
			wins.Value += 1
		end

		notify(player, "Vault run complete.")
		pushState(player)
	end)
end

local function setupPlayer(player: Player)
	playerData[player] = {
		cores = 0,
		hasKeycard = false,
		completed = false,
		checkpoint = GameConfig.SpawnCFrame,
		checkpointReached = false,
		collectedCores = {},
	}

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cores = Instance.new("IntValue")
	cores.Name = "Cores"
	cores.Value = 0
	cores.Parent = leaderstats

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = 0
	wins.Parent = leaderstats

	player.CharacterAdded:Connect(function(character: Model)
		local data = playerData[player]
		local humanoid = character:WaitForChild("Humanoid", 8)
		local root = character:WaitForChild("HumanoidRootPart", 8)

		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.WalkSpeed = 18
			humanoid.JumpPower = 52
		end

		if data and root and root:IsA("BasePart") then
			task.wait()
			root.CFrame = data.checkpoint
		end
	end)

	pushState(player)
end

buildArena()
buildDoors()
buildKeycard()
buildCores()
buildGuideNpc()
buildPatrolHazard()
buildCheckpointsAndFinish()

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player: Player)
	playerData[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
