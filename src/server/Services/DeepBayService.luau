--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][DeepBay] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local OuterYardSalvageService = require(Services:WaitForChild("OuterYardSalvageService"))
local Components = require(Config:WaitForChild("Components"))
local DeepBayConfig = require(Config:WaitForChild("DeepBayConfig"))

type SweeperPhase = "WARNING" | "SWEEP" | "SAFE"
type DeepBayDefinition = DeepBayConfig.DeepBayDefinition
type DeepBayRuntime = {
	Definition: DeepBayDefinition,
	Model: Model,
	HazardVolume: BasePart,
	PhaseIndicator: BasePart,
	PhaseLabel: TextLabel,
	EntranceIndicator: BasePart,
	SafeReturnMarker: BasePart,
	ScannerCache: BasePart,
	ScannerClaimVolume: BasePart,
	ScannerPrompt: ProximityPrompt,
	Phase: SweeperPhase,
}

local DeepBayService = {}

local scannerClaims: { [Player]: boolean } = {}
local lastScannerAttemptTimes: { [Player]: number } = {}
local runtime: DeepBayRuntime? = nil
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:FindFirstChild(childName)
	if not child then
		error(string.format("[ODDWORKS][DeepBay] Missing required object: %s.%s", parent:GetFullName(), childName), 2)
	end
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][DeepBay] %s.%s must be a %s, but found %s.",
				parent:GetFullName(),
				childName,
				expectedClassName,
				child.ClassName
			),
			2
		)
	end
	return child
end

local function isPositiveFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value > 0
end

local function isPositiveInteger(value: number): boolean
	return isPositiveFinite(value) and math.floor(value) == value
end

local function validateDefinition(definition: DeepBayDefinition)
	if not isPositiveFinite(definition.WarningSeconds)
		or not isPositiveFinite(definition.SweepSeconds)
		or not isPositiveFinite(definition.SafeSeconds)
		or not isPositiveFinite(definition.HazardPollSeconds)
		or not isPositiveFinite(definition.ScannerAttemptIntervalSeconds)
		or not isPositiveFinite(definition.ScannerMaxValidDistance)
		or not isPositiveInteger(definition.ScannerQuantity)
		or not Components.GetDefinition(definition.ScannerComponentId)
		or not Components.IsValidRarity(definition.ScannerRarity)
	then
		error("[ODDWORKS][DeepBay] Deep Bay configuration is invalid.")
	end
end

local function createBillboard(part: BasePart, name: string, initialText: string): TextLabel
	local previous = part:FindFirstChild(name)
	if previous then
		previous:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 110
	billboard.Size = UDim2.fromOffset(260, 64)
	billboard.StudsOffset = Vector3.new(0, 1.6, 0)
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundColor3 = Color3.fromRGB(24, 27, 31)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Size = UDim2.fromScale(1, 1)
	label.Text = initialText
	label.TextColor3 = Color3.fromRGB(245, 245, 235)
	label.TextScaled = true
	label.Parent = billboard
	return label
end

local function setPhase(deepBay: DeepBayRuntime, phase: SweeperPhase)
	deepBay.Phase = phase
	deepBay.PhaseLabel.Text = phase

	if phase == "WARNING" then
		deepBay.HazardVolume.Color = Color3.fromRGB(255, 191, 64)
		deepBay.HazardVolume.Transparency = 0.55
		deepBay.PhaseIndicator.Color = Color3.fromRGB(255, 191, 64)
		deepBay.PhaseLabel.TextColor3 = Color3.fromRGB(255, 225, 125)
	elseif phase == "SWEEP" then
		deepBay.HazardVolume.Color = Color3.fromRGB(235, 68, 59)
		deepBay.HazardVolume.Transparency = 0.15
		deepBay.PhaseIndicator.Color = Color3.fromRGB(235, 68, 59)
		deepBay.PhaseLabel.TextColor3 = Color3.fromRGB(255, 130, 120)
	else
		deepBay.HazardVolume.Color = Color3.fromRGB(72, 214, 137)
		deepBay.HazardVolume.Transparency = 0.82
		deepBay.PhaseIndicator.Color = Color3.fromRGB(72, 214, 137)
		deepBay.PhaseLabel.TextColor3 = Color3.fromRGB(130, 255, 180)
	end
end

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character or character.Parent ~= Workspace then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isInsideVolume(root: BasePart, volume: BasePart): boolean
	local localPosition = volume.CFrame:PointToObjectSpace(root.Position)
	local halfSize = volume.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function returnToSafeStart(player: Player, deepBay: DeepBayRuntime)
	local character = player.Character
	if player.Parent ~= Players or not character or character.Parent ~= Workspace then
		return
	end

	character:PivotTo(deepBay.SafeReturnMarker.CFrame * CFrame.new(0, 3, 0))
end

local function handleSweeperHit(player: Player, deepBay: DeepBayRuntime)
	if player.Parent ~= Players
		or not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not OuterYardSalvageService.HasClaimedAllStarterOpportunities(player)
	then
		return
	end

	local resultCode, discardedCount = ModularPrototypeStateService.DiscardAllUnbanked(player)
	if resultCode == "INVALID_STATE" then
		return
	end

	returnToSafeStart(player, deepBay)
	print(
		string.format(
			"[ODDWORKS][DeepBay] Magnetic Sweeper caught %s; discarded %d Unbanked component(s) (%s).",
			player.Name,
			discardedCount,
			resultCode
		)
	)
end

local function runSweepWindow(deepBay: DeepBayRuntime)
	local hitThisSweep: { [Player]: boolean } = {}
	local deadline = os.clock() + deepBay.Definition.SweepSeconds

	while started and runtime == deepBay and os.clock() < deadline do
		for _, player in ipairs(Players:GetPlayers()) do
			if not hitThisSweep[player] and OuterYardSalvageService.HasClaimedAllStarterOpportunities(player) then
				local root = getCharacterRoot(player)
				if root and isInsideVolume(root, deepBay.HazardVolume) then
					hitThisSweep[player] = true
					handleSweeperHit(player, deepBay)
				end
			end
		end
		task.wait(deepBay.Definition.HazardPollSeconds)
	end
end

local function runSweeper(deepBay: DeepBayRuntime)
	while started and runtime == deepBay do
		setPhase(deepBay, "WARNING")
		task.wait(deepBay.Definition.WarningSeconds)
		if not started or runtime ~= deepBay then
			break
		end

		setPhase(deepBay, "SWEEP")
		runSweepWindow(deepBay)
		if not started or runtime ~= deepBay then
			break
		end

		setPhase(deepBay, "SAFE")
		task.wait(deepBay.Definition.SafeSeconds)
	end
end

local function passesScannerThrottle(player: Player, definition: DeepBayDefinition): boolean
	local now = os.clock()
	local lastAttempt = lastScannerAttemptTimes[player]
	if lastAttempt and now - lastAttempt < definition.ScannerAttemptIntervalSeconds then
		return false
	end

	lastScannerAttemptTimes[player] = now
	return true
end

local function handleScannerTriggered(player: Player, deepBay: DeepBayRuntime)
	if player.Parent ~= Players or not passesScannerThrottle(player, deepBay.Definition) then
		return
	end
	if not PlayerStateService.HasState(player)
		or not ModularPrototypeStateService.HasState(player)
		or not OuterYardSalvageService.HasClaimedAllStarterOpportunities(player)
		or scannerClaims[player]
	then
		return
	end
	if runtime ~= deepBay
		or deepBay.Model.Parent == nil
		or deepBay.ScannerCache.Parent ~= deepBay.Model
		or deepBay.ScannerClaimVolume.Parent ~= deepBay.Model
		or deepBay.ScannerPrompt.Parent ~= deepBay.ScannerCache
	then
		return
	end

	local root = getCharacterRoot(player)
	if not root
		or (root.Position - deepBay.ScannerCache.Position).Magnitude > deepBay.Definition.ScannerMaxValidDistance
		or not isInsideVolume(root, deepBay.ScannerClaimVolume)
	then
		return
	end

	-- Reserve before mutation; a failed inventory mutation releases the claim.
	scannerClaims[player] = true
	local didAward = ModularPrototypeStateService.AddUnbankedComponent(
		player,
		deepBay.Definition.ScannerComponentId,
		deepBay.Definition.ScannerRarity,
		deepBay.Definition.ScannerQuantity
	)
	if not didAward then
		scannerClaims[player] = nil
		warn(string.format("[ODDWORKS][DeepBay] Failed to award the Rare SignalScanner for %s.", player.Name))
		return
	end

	print(string.format("[ODDWORKS][DeepBay] %s recovered +1 SignalScanner [Rare] into UnbankedComponents.", player.Name))
end

local function clearPlayer(player: Player)
	scannerClaims[player] = nil
	lastScannerAttemptTimes[player] = nil
end

local function discoverDeepBay(): DeepBayRuntime
	local definition = DeepBayConfig.GetDefinition()
	validateDefinition(definition)

	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local model = requireChildOfClass(world, definition.WorldModelName, "Model") :: Model
	local hazardVolume = requireChildOfClass(model, definition.HazardVolumeName, "BasePart") :: BasePart
	local phaseIndicator = requireChildOfClass(model, definition.PhaseIndicatorName, "BasePart") :: BasePart
	local entranceIndicator = requireChildOfClass(model, definition.EntranceIndicatorName, "BasePart") :: BasePart
	local safeReturnMarker = requireChildOfClass(model, definition.SafeReturnMarkerName, "BasePart") :: BasePart
	local scannerCache = requireChildOfClass(model, definition.ScannerCacheName, "BasePart") :: BasePart
	local scannerClaimVolume = requireChildOfClass(model, definition.ScannerClaimVolumeName, "BasePart") :: BasePart
	local scannerPrompt = requireChildOfClass(scannerCache, "Prompt", "ProximityPrompt") :: ProximityPrompt

	createBillboard(entranceIndicator, "DeepBayLabel", "DEEP BAY\nBANK OR PUSH")
	local phaseLabel = createBillboard(phaseIndicator, "SweeperPhaseLabel", "WARNING")

	return {
		Definition = definition,
		Model = model,
		HazardVolume = hazardVolume,
		PhaseIndicator = phaseIndicator,
		PhaseLabel = phaseLabel,
		EntranceIndicator = entranceIndicator,
		SafeReturnMarker = safeReturnMarker,
		ScannerCache = scannerCache,
		ScannerClaimVolume = scannerClaimVolume,
		ScannerPrompt = scannerPrompt,
		Phase = "WARNING",
	}
end

function DeepBayService.Start()
	if started then
		return
	end
	started = true

	local deepBay = discoverDeepBay()
	runtime = deepBay
	deepBay.ScannerPrompt.Triggered:Connect(function(player: Player)
		handleScannerTriggered(player, deepBay)
	end)
	ModularPrototypeStateService.ObserveStateRemoved(clearPlayer)
	Players.PlayerRemoving:Connect(clearPlayer)

	task.spawn(runSweeper, deepBay)
	print("[ODDWORKS][DeepBay] Bank-or-push route started with a server-owned Magnetic Sweeper.")
end

return DeepBayService
