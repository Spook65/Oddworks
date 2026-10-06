--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SignalDiscoveryController = {}

local OPPORTUNITY_ID = "KilnbackSignal"
local SIGNATURE_ID = "Kilnback"
local SCANNER_COMPONENT_ID = "SignalScanner"
local INITIAL_REQUEST_ATTEMPTS = 4
local INITIAL_REQUEST_RETRY_SECONDS = 1.1

local capabilityActive = false
local discovered = false
local receivedModularState = false
local receivedDiscoveryState = false
local cueGui: BillboardGui? = nil
local cueLight: PointLight? = nil
local prompt: ProximityPrompt? = nil
local sealDoor: BasePart? = nil
local revealBanner: TextLabel? = nil
local bannerToken = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][SignalDiscoveryController] %s.%s must be a %s, but found %s.",
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

local function isBoundedString(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

local function readCapability(payload: any): boolean?
	if typeof(payload) ~= "table" or typeof(payload.UnbankedComponents) ~= "table" or typeof(payload.BankedComponents) ~= "table" then
		return nil
	end
	local construct = payload.PrototypeConstruct
	if construct == nil then
		return false
	end
	if typeof(construct) ~= "table" or construct.FrameId ~= "SmallBiped_v1" or typeof(construct.Head) ~= "table" then
		return nil
	end
	if not isBoundedString(construct.Head.ComponentId, 48) then
		return nil
	end
	return construct.Head.ComponentId == SCANNER_COMPONENT_ID
end

local function updatePresentation()
	local shouldShowSignal = capabilityActive and not discovered
	if cueGui then
		cueGui.Enabled = shouldShowSignal
	end
	if cueLight then
		cueLight.Enabled = shouldShowSignal
	end
	if prompt then
		prompt.Enabled = shouldShowSignal
	end
	if sealDoor then
		sealDoor.LocalTransparencyModifier = if discovered then 0.72 else 0
	end
end

local function showRevealBanner()
	local label = revealBanner
	if not label then
		return
	end
	bannerToken += 1
	local token = bannerToken
	label.Text = "SIGNATURE DISCOVERED\nKILNBACK"
	label.Visible = true
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.08
	task.delay(3.5, function()
		if bannerToken ~= token or not label then
			return
		end
		local tween = TweenService:Create(label, TweenInfo.new(0.45), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if bannerToken == token then
				label.Visible = false
			end
		end)
	end)
end

local function createPresentation(cueAnchor: BasePart, investigationPrompt: ProximityPrompt, door: BasePart)
	prompt = investigationPrompt
	sealDoor = door

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LocalStrangeSignalCue"
	billboard.Adornee = cueAnchor
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.MaxDistance = 120
	billboard.Size = UDim2.fromOffset(260, 82)
	billboard.StudsOffset = Vector3.new(0, 1.3, 0)
	billboard.Parent = cueAnchor
	cueGui = billboard

	local label = Instance.new("TextLabel")
	label.Name = "SignalLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 33, 31)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = "STRANGE SIGNAL\nSCANNER LOCK"
	label.TextColor3 = Color3.fromRGB(103, 255, 188)
	label.TextScaled = true
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(236, 182, 67)
	stroke.Thickness = 2
	stroke.Parent = label

	local light = Instance.new("PointLight")
	light.Name = "LocalSignalLight"
	light.Brightness = 3
	light.Color = Color3.fromRGB(103, 255, 188)
	light.Enabled = false
	light.Range = 16
	light.Parent = cueAnchor
	cueLight = light

	TweenService:Create(
		label,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.42 }
	):Play()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSSignatureDiscoveryGui"
	screenGui.DisplayOrder = 12
	screenGui.ResetOnSpawn = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local banner = Instance.new("TextLabel")
	banner.Name = "RevealBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0.1, 0)
	banner.Size = UDim2.new(0.8, 0, 0, 100)
	banner.BackgroundColor3 = Color3.fromRGB(31, 26, 22)
	banner.BackgroundTransparency = 0.08
	banner.BorderSizePixel = 0
	banner.Font = Enum.Font.GothamBlack
	banner.TextColor3 = Color3.fromRGB(255, 188, 70)
	banner.TextScaled = true
	banner.Visible = false
	banner.Parent = screenGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(680, 100)
	sizeConstraint.MinSize = Vector2.new(300, 100)
	sizeConstraint.Parent = banner
	revealBanner = banner
	updatePresentation()
end

local function readDiscoveryState(payload: any): (boolean?, string?)
	if typeof(payload) ~= "table"
		or (payload.Kind ~= "STATE" and payload.Kind ~= "REVEALED")
		or payload.OpportunityId ~= OPPORTUNITY_ID
		or payload.SignatureId ~= SIGNATURE_ID
		or typeof(payload.Discovered) ~= "boolean"
	then
		return nil, nil
	end
	for key in pairs(payload) do
		if key ~= "Kind" and key ~= "OpportunityId" and key ~= "SignatureId" and key ~= "Discovered" then
			return nil, nil
		end
	end
	return payload.Discovered, payload.Kind
end

function SignalDiscoveryController.Start()
	if started then
		return
	end
	started = true

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local modularStateRequest = requireChildOfClass(network, "ModularStateRequest", "RemoteEvent") :: RemoteEvent
	local modularStateSnapshot = requireChildOfClass(network, "ModularStateSnapshot", "RemoteEvent") :: RemoteEvent
	local discoveryStateRequest = requireChildOfClass(
		network,
		"SignatureDiscoveryStateRequest",
		"RemoteEvent"
	) :: RemoteEvent
	local discoveryState = requireChildOfClass(network, "SignatureDiscoveryState", "RemoteEvent") :: RemoteEvent

	local world = requireChildOfClass(Workspace, "ODDWORKSWorld", "Folder")
	local opportunity = requireChildOfClass(world, "HiddenSignalOpportunity", "Model")
	local cueAnchor = requireChildOfClass(opportunity, "SignalCueAnchor", "BasePart") :: BasePart
	local interactionPart = requireChildOfClass(opportunity, "InvestigationConsole", "BasePart")
	local investigationPrompt = requireChildOfClass(interactionPart, "Prompt", "ProximityPrompt") :: ProximityPrompt
	local door = requireChildOfClass(opportunity, "SealDoor", "BasePart") :: BasePart
	createPresentation(cueAnchor, investigationPrompt, door)

	modularStateSnapshot.OnClientEvent:Connect(function(payload: any)
		local capability = readCapability(payload)
		if capability == nil then
			return
		end
		capabilityActive = capability
		receivedModularState = true
		updatePresentation()
	end)

	discoveryState.OnClientEvent:Connect(function(payload: any)
		local state, kind = readDiscoveryState(payload)
		if state == nil then
			return
		end
		local newlyRevealed = kind == "REVEALED" and state and not discovered
		discovered = state
		receivedDiscoveryState = true
		updatePresentation()
		if newlyRevealed then
			showRevealBanner()
		end
	end)

	task.spawn(function()
		for _ = 1, INITIAL_REQUEST_ATTEMPTS do
			if not receivedModularState then
				modularStateRequest:FireServer()
			end
			if not receivedDiscoveryState then
				discoveryStateRequest:FireServer()
			end
			if receivedModularState and receivedDiscoveryState then
				return
			end
			task.wait(INITIAL_REQUEST_RETRY_SECONDS)
		end
	end)
end

return SignalDiscoveryController
