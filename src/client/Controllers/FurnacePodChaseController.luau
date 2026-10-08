--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FurnacePodChaseController = {}

local banner: TextLabel? = nil
local dangerOverlay: Frame? = nil
local explanationBackdrop: Frame? = nil
local confirmationRemote: RemoteEvent? = nil
local objectiveTarget: Part? = nil
local objectiveOrigin: Attachment? = nil
local objectiveBeam: Beam? = nil
local presentationToken = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][FurnacePodChaseController] %s.%s must be a %s, but found %s.",
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

local function createPresentation()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSFurnacePodChaseGui"
	screenGui.DisplayOrder = 14
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local overlay = Instance.new("Frame")
	overlay.Name = "DangerOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(190, 35, 22)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = screenGui
	dangerOverlay = overlay

	local label = Instance.new("TextLabel")
	label.Name = "ChaseBanner"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.07, 0)
	label.Size = UDim2.new(0.8, 0, 0, 96)
	label.BackgroundColor3 = Color3.fromRGB(34, 28, 24)
	label.BackgroundTransparency = 0.08
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 190, 57)
	label.TextScaled = true
	label.Visible = false
	label.Parent = screenGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(720, 96)
	sizeConstraint.MinSize = Vector2.new(300, 96)
	sizeConstraint.Parent = label
	banner = label

	local backdrop = Instance.new("Frame")
	backdrop.Name = "FirstTheftExplanation"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(9, 10, 11)
	backdrop.BackgroundTransparency = 0.22
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = screenGui
	explanationBackdrop = backdrop

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.82, 0, 0, 390)
	panel.BackgroundColor3 = Color3.fromRGB(30, 31, 32)
	panel.BorderSizePixel = 0
	panel.ZIndex = 21
	panel.Parent = backdrop

	local panelConstraint = Instance.new("UISizeConstraint")
	panelConstraint.MaxSize = Vector2.new(620, 390)
	panelConstraint.MinSize = Vector2.new(310, 390)
	panelConstraint.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(24, 20)
	title.Size = UDim2.new(1, -48, 0, 52)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "STEAL THE FURNACE POD?"
	title.TextColor3 = Color3.fromRGB(255, 181, 55)
	title.TextScaled = true
	title.ZIndex = 22
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Name = "Rules"
	body.Position = UDim2.fromOffset(28, 88)
	body.Size = UDim2.new(1, -56, 0, 205)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.RichText = true
	body.Text = table.concat({
		"<b>OBJECTIVE</b>  Steal the Pod and return it to your workshop.",
		"",
		"<b>DANGER</b>  Stealing wakes the Scrap Warden.",
		"",
		"<b>FAILURE</b>  If caught, you lose only this Pod attempt.",
		"",
		"<b>SAFE</b>  Banked inventory, Constructs, and other progress stay safe.",
	}, "\n")
	body.TextColor3 = Color3.fromRGB(238, 239, 233)
	body.TextSize = 18
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 22
	body.Parent = panel

	local stealButton = Instance.new("TextButton")
	stealButton.Name = "ConfirmSteal"
	stealButton.Position = UDim2.new(0.5, 8, 1, -72)
	stealButton.Size = UDim2.new(0.5, -32, 0, 48)
	stealButton.BackgroundColor3 = Color3.fromRGB(214, 91, 42)
	stealButton.BorderSizePixel = 0
	stealButton.Font = Enum.Font.GothamBold
	stealButton.Text = "STEAL POD"
	stealButton.TextColor3 = Color3.fromRGB(255, 255, 246)
	stealButton.TextSize = 18
	stealButton.ZIndex = 22
	stealButton.Parent = panel

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.Position = UDim2.new(0, 24, 1, -72)
	cancelButton.Size = UDim2.new(0.5, -32, 0, 48)
	cancelButton.BackgroundColor3 = Color3.fromRGB(68, 71, 72)
	cancelButton.BorderSizePixel = 0
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.Text = "NOT YET"
	cancelButton.TextColor3 = Color3.fromRGB(235, 235, 229)
	cancelButton.TextSize = 18
	cancelButton.ZIndex = 22
	cancelButton.Parent = panel

	stealButton.Activated:Connect(function()
		backdrop.Visible = false
		local remote = confirmationRemote
		if remote then
			remote:FireServer("STEAL")
		end
	end)
	cancelButton.Activated:Connect(function()
		backdrop.Visible = false
		local remote = confirmationRemote
		if remote then
			remote:FireServer("NOT_YET")
		end
	end)
end

local function clearObjectiveCue()
	if objectiveBeam then
		objectiveBeam:Destroy()
		objectiveBeam = nil
	end
	if objectiveOrigin then
		objectiveOrigin:Destroy()
		objectiveOrigin = nil
	end
	if objectiveTarget then
		objectiveTarget:Destroy()
		objectiveTarget = nil
	end
end

local function showObjectiveCue(destination: Vector3)
	clearObjectiveCue()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end

	local target = Instance.new("Part")
	target.Name = "LocalWorkshopObjective"
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Size = Vector3.new(0.2, 0.2, 0.2)
	target.Transparency = 1
	target.Position = destination + Vector3.new(0, 3.5, 0)
	target.Parent = Workspace
	objectiveTarget = target

	local destinationAttachment = Instance.new("Attachment")
	destinationAttachment.Name = "Destination"
	destinationAttachment.Parent = target
	local origin = Instance.new("Attachment")
	origin.Name = "WorkshopObjectiveOrigin"
	origin.Parent = root
	objectiveOrigin = origin

	local beam = Instance.new("Beam")
	beam.Name = "WorkshopObjectiveBeam"
	beam.Attachment0 = origin
	beam.Attachment1 = destinationAttachment
	beam.Color = ColorSequence.new(Color3.fromRGB(82, 241, 151))
	beam.FaceCamera = true
	beam.LightEmission = 0.8
	beam.Transparency = NumberSequence.new(0.18)
	beam.Width0 = 0.12
	beam.Width1 = 0.7
	beam.Parent = origin
	objectiveBeam = beam

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorkshopObjectiveLabel"
	billboard.Adornee = target
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 180
	billboard.Size = UDim2.fromOffset(260, 72)
	billboard.Parent = target

	local objectiveLabel = Instance.new("TextLabel")
	objectiveLabel.Size = UDim2.fromScale(1, 1)
	objectiveLabel.BackgroundColor3 = Color3.fromRGB(25, 43, 34)
	objectiveLabel.BackgroundTransparency = 0.12
	objectiveLabel.BorderSizePixel = 0
	objectiveLabel.Font = Enum.Font.GothamBold
	objectiveLabel.Text = "YOUR WORKSHOP\nBRING THE POD HERE"
	objectiveLabel.TextColor3 = Color3.fromRGB(111, 255, 173)
	objectiveLabel.TextScaled = true
	objectiveLabel.Parent = billboard
end

local function showMessage(text: string, color: Color3, duration: number, keepDanger: boolean)
	local label = banner
	local overlay = dangerOverlay
	if not label or not overlay then
		return
	end
	presentationToken += 1
	local token = presentationToken
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.08
	label.Visible = true
	overlay.Visible = keepDanger
	overlay.BackgroundTransparency = if keepDanger then 0.88 else 1

	if duration <= 0 then
		return
	end
	task.delay(duration, function()
		if token ~= presentationToken or not label or not overlay then
			return
		end
		local tween = TweenService:Create(label, TweenInfo.new(0.35), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if presentationToken == token then
				label.Visible = false
				overlay.Visible = false
			end
		end)
	end)
end

local function isFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

local function readPayload(payload: any): (string?, number?, string?, number?, Vector3?)
	if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
		return nil, nil, nil, nil, nil
	end
	local kind = payload.Kind
	if kind == "EXPLANATION" then
		for key in pairs(payload) do
			if key ~= "Kind" then
				return nil, nil, nil, nil, nil
			end
		end
		return kind, nil, nil, nil, nil
	elseif kind == "ACTIVATING" then
		if typeof(payload.HeadStartSeconds) ~= "number"
			or payload.HeadStartSeconds < 1
			or payload.HeadStartSeconds > 5
			or not isFiniteVector3(payload.DestinationPosition)
		then
			return nil, nil, nil, nil, nil
		end
		for key in pairs(payload) do
			if key ~= "Kind" and key ~= "HeadStartSeconds" and key ~= "DestinationPosition" then
				return nil, nil, nil, nil, nil
			end
		end
		return kind, nil, nil, payload.HeadStartSeconds, payload.DestinationPosition
	elseif kind == "CHASE_STARTED" or kind == "STAGE" then
		if typeof(payload.Stage) ~= "number" or payload.Stage % 1 ~= 0 or payload.Stage < 1 or payload.Stage > 3 then
			return nil, nil, nil, nil, nil
		end
		for key in pairs(payload) do
			if key ~= "Kind" and key ~= "Stage" then
				return nil, nil, nil, nil, nil
			end
		end
		return kind, payload.Stage, nil, nil, nil
	elseif kind == "REVEALED" then
		if payload.SignatureId ~= "Kilnback" then
			return nil, nil, nil, nil, nil
		end
		for key in pairs(payload) do
			if key ~= "Kind" and key ~= "SignatureId" then
				return nil, nil, nil, nil, nil
			end
		end
		return kind, nil, payload.SignatureId, nil, nil
	elseif kind == "CAUGHT" or kind == "SECURED" then
		for key in pairs(payload) do
			if key ~= "Kind" then
				return nil, nil, nil, nil, nil
			end
		end
		return kind, nil, nil, nil, nil
	end
	return nil, nil, nil, nil, nil
end

function FurnacePodChaseController.Start()
	if started then
		return
	end
	started = true
	createPresentation()

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local stateRemote = requireChildOfClass(network, "FurnacePodChaseState", "RemoteEvent") :: RemoteEvent
	confirmationRemote = requireChildOfClass(network, "FurnacePodStealConfirm", "RemoteEvent") :: RemoteEvent
	stateRemote.OnClientEvent:Connect(function(payload: any)
		local kind, stage, _, headStartSeconds, destinationPosition = readPayload(payload)
		if not kind then
			return
		end
		if kind == "EXPLANATION" then
			local backdrop = explanationBackdrop
			if backdrop then
				backdrop.Visible = true
			end
		elseif kind == "ACTIVATING" then
			showObjectiveCue(destinationPosition :: Vector3)
			showMessage(
				string.format("POD STOLEN - SCRAP WARDEN WAKING\nRUN HOME  |  %.1fs HEAD START", headStartSeconds :: number),
				Color3.fromRGB(255, 190, 57),
				0,
				true
			)
		elseif kind == "CHASE_STARTED" or kind == "STAGE" then
			showMessage(
				string.format("SCRAP WARDEN ACTIVE\nRETURN TO YOUR WORKSHOP  |  THREAT %d", stage :: number),
				Color3.fromRGB(255, 190, 57),
				0,
				true
			)
		elseif kind == "CAUGHT" then
			clearObjectiveCue()
			showMessage("CAUGHT - FURNACE POD LOST\nBANKED INVENTORY AND BUILDS ARE SAFE", Color3.fromRGB(255, 92, 73), 2.2, false)
		elseif kind == "SECURED" then
			clearObjectiveCue()
			showMessage("POD SECURED\nKILNBACK REVEAL INCOMING", Color3.fromRGB(95, 244, 154), 0, false)
		elseif kind == "REVEALED" then
			clearObjectiveCue()
			showMessage("ODDITY REVEALED\nKILNBACK", Color3.fromRGB(255, 174, 48), 4, false)
		end
	end)
end

return FurnacePodChaseController
