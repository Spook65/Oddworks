--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FurnacePodChaseController = {}

local banner: TextLabel? = nil
local abilityToast: TextLabel? = nil
local dangerOverlay: Frame? = nil
local explanationBackdrop: Frame? = nil
local confirmationRemote: RemoteEvent? = nil
local objectiveTarget: Part? = nil
local objectiveBillboard: BillboardGui? = nil
local objectiveLabel: TextLabel? = nil
local objectiveEdge: Frame? = nil
local objectiveEdgeArrow: TextLabel? = nil
local objectiveEdgeText: TextLabel? = nil
local objectiveConnection: RBXScriptConnection? = nil
local objectiveDestination: Vector3? = nil
local presentationToken = 0
local abilityPresentationToken = 0
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

	local abilityLabel = Instance.new("TextLabel")
	abilityLabel.Name = "SpringLegsToast"
	abilityLabel.AnchorPoint = Vector2.new(0.5, 0)
	abilityLabel.Position = UDim2.new(0.5, 0, 0.07, 104)
	abilityLabel.Size = UDim2.new(0.65, 0, 0, 58)
	abilityLabel.BackgroundColor3 = Color3.fromRGB(30, 77, 66)
	abilityLabel.BackgroundTransparency = 0.08
	abilityLabel.BorderSizePixel = 0
	abilityLabel.Font = Enum.Font.GothamBold
	abilityLabel.Text = "SPRINGLEGS ACTIVE\nEnhanced movement during escape"
	abilityLabel.TextColor3 = Color3.fromRGB(137, 255, 198)
	abilityLabel.TextScaled = true
	abilityLabel.Visible = false
	abilityLabel.Parent = screenGui

	local abilitySizeConstraint = Instance.new("UISizeConstraint")
	abilitySizeConstraint.MaxSize = Vector2.new(460, 58)
	abilitySizeConstraint.MinSize = Vector2.new(280, 58)
	abilitySizeConstraint.Parent = abilityLabel
	abilityToast = abilityLabel

	local edge = Instance.new("Frame")
	edge.Name = "WorkshopEdgeObjective"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Size = UDim2.fromOffset(210, 38)
	edge.BackgroundColor3 = Color3.fromRGB(24, 39, 32)
	edge.BackgroundTransparency = 0.08
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 14
	edge.Parent = screenGui
	objectiveEdge = edge

	local edgeArrow = Instance.new("TextLabel")
	edgeArrow.Name = "Direction"
	edgeArrow.Position = UDim2.fromOffset(5, 4)
	edgeArrow.Size = UDim2.fromOffset(30, 30)
	edgeArrow.BackgroundTransparency = 1
	edgeArrow.Font = Enum.Font.GothamBlack
	edgeArrow.Text = ">"
	edgeArrow.TextColor3 = Color3.fromRGB(111, 255, 173)
	edgeArrow.TextSize = 24
	edgeArrow.ZIndex = 15
	edgeArrow.Parent = edge
	objectiveEdgeArrow = edgeArrow

	local edgeText = Instance.new("TextLabel")
	edgeText.Name = "Objective"
	edgeText.Position = UDim2.fromOffset(39, 0)
	edgeText.Size = UDim2.new(1, -45, 1, 0)
	edgeText.BackgroundTransparency = 1
	edgeText.Font = Enum.Font.GothamBold
	edgeText.Text = "RETURN TO WORKSHOP"
	edgeText.TextColor3 = Color3.fromRGB(225, 255, 235)
	edgeText.TextSize = 13
	edgeText.TextXAlignment = Enum.TextXAlignment.Left
	edgeText.ZIndex = 15
	edgeText.Parent = edge
	objectiveEdgeText = edgeText

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

local function showSpringLegsActive()
	local label = abilityToast
	if not label then
		return
	end
	abilityPresentationToken += 1
	local token = abilityPresentationToken
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.08
	label.Visible = true
	task.delay(2.8, function()
		if token ~= abilityPresentationToken or not label then
			return
		end
		local tween = TweenService:Create(label, TweenInfo.new(0.3), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if abilityPresentationToken == token then
				label.Visible = false
			end
		end)
	end)
end

local function hideSpringLegsActive()
	abilityPresentationToken += 1
	if abilityToast then
		abilityToast.Visible = false
	end
end

local function clearObjectiveCue()
	if objectiveConnection then
		objectiveConnection:Disconnect()
		objectiveConnection = nil
	end
	if objectiveTarget then
		objectiveTarget:Destroy()
		objectiveTarget = nil
	end
	objectiveBillboard = nil
	objectiveLabel = nil
	objectiveDestination = nil
	if objectiveEdge then
		objectiveEdge.Visible = false
	end
end

local function updateObjectiveCue()
	local destination = objectiveDestination
	local edge = objectiveEdge
	local edgeArrow = objectiveEdgeArrow
	local edgeText = objectiveEdgeText
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not destination or not edge or not edgeArrow or not edgeText or not camera or not root or not root:IsA("BasePart") then
		if edge then
			edge.Visible = false
		end
		return
	end

	local distance = (root.Position - destination).Magnitude
	if objectiveLabel then
		objectiveLabel.Text = string.format("RETURN TO WORKSHOP\n%dm", math.floor(distance + 0.5))
	end
	if objectiveBillboard then
		objectiveBillboard.Enabled = distance > 10
	end

	local viewportPoint, onScreen = camera:WorldToViewportPoint(destination)
	local viewportSize = camera.ViewportSize
	local comfortableOnScreen = onScreen
		and viewportPoint.Z > 0
		and viewportPoint.X >= 90
		and viewportPoint.X <= viewportSize.X - 90
		and viewportPoint.Y >= 100
		and viewportPoint.Y <= viewportSize.Y - 70
	if comfortableOnScreen then
		edge.Visible = false
		return
	end

	local center = viewportSize * 0.5
	local screenDirection = Vector2.new(viewportPoint.X, viewportPoint.Y) - center
	if viewportPoint.Z <= 0 then
		screenDirection = -screenDirection
	end
	if screenDirection.Magnitude < 0.001 then
		local cameraDirection = camera.CFrame:VectorToObjectSpace(destination - camera.CFrame.Position)
		screenDirection = Vector2.new(cameraDirection.X, -cameraDirection.Y)
	end
	if screenDirection.Magnitude < 0.001 then
		screenDirection = Vector2.new(1, 0)
	end

	local unitDirection = screenDirection.Unit
	local horizontalRadius = math.max(center.X - 125, 1)
	local verticalRadius = math.max(center.Y - 115, 1)
	local edgeScale = math.min(
		horizontalRadius / math.max(math.abs(unitDirection.X), 0.001),
		verticalRadius / math.max(math.abs(unitDirection.Y), 0.001)
	)
	local edgePosition = center + unitDirection * edgeScale
	edgePosition = Vector2.new(
		math.clamp(edgePosition.X, 112, viewportSize.X - 112),
		math.clamp(edgePosition.Y, 105, viewportSize.Y - 52)
	)
	edge.Position = UDim2.fromOffset(edgePosition.X, edgePosition.Y)
	edgeArrow.Rotation = math.deg(math.atan2(unitDirection.Y, unitDirection.X))
	edgeText.Text = string.format("RETURN TO WORKSHOP\n%dm", math.floor(distance + 0.5))
	edge.Visible = true
end

local function showObjectiveCue(destination: Vector3)
	clearObjectiveCue()

	local target = Instance.new("Part")
	target.Name = "LocalWorkshopObjective"
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Size = Vector3.new(0.2, 0.2, 0.2)
	target.Transparency = 1
	target.Position = destination + Vector3.new(0, 2.8, 0)
	target.Parent = Workspace
	objectiveTarget = target

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorkshopObjectiveLabel"
	billboard.Adornee = target
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 140
	billboard.Size = UDim2.fromOffset(170, 48)
	billboard.Parent = target
	objectiveBillboard = billboard

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(25, 43, 34)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = "RETURN TO WORKSHOP"
	label.TextColor3 = Color3.fromRGB(111, 255, 173)
	label.TextSize = 14
	label.TextWrapped = true
	label.Parent = billboard
	objectiveLabel = label
	objectiveDestination = destination
	objectiveConnection = RunService.RenderStepped:Connect(updateObjectiveCue)
	updateObjectiveCue()
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

local function clearChasePresentation()
	presentationToken += 1
	if banner then
		banner.Visible = false
	end
	if dangerOverlay then
		dangerOverlay.Visible = false
	end
	hideSpringLegsActive()
	clearObjectiveCue()
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

local function readPayload(payload: any): (string?, number?, string?, number?, Vector3?, boolean?)
	if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
		return nil, nil, nil, nil, nil, nil
	end
	local kind = payload.Kind
	if kind == "EXPLANATION" then
		for key in pairs(payload) do
			if key ~= "Kind" then
				return nil, nil, nil, nil, nil, nil
			end
		end
		return kind, nil, nil, nil, nil, nil
	elseif kind == "ACTIVATING" then
		if typeof(payload.HeadStartSeconds) ~= "number"
			or payload.HeadStartSeconds < 1
			or payload.HeadStartSeconds > 5
			or not isFiniteVector3(payload.DestinationPosition)
			or typeof(payload.SpringLegsActive) ~= "boolean"
		then
			return nil, nil, nil, nil, nil, nil
		end
		for key in pairs(payload) do
			if key ~= "Kind"
				and key ~= "HeadStartSeconds"
				and key ~= "DestinationPosition"
				and key ~= "SpringLegsActive"
			then
				return nil, nil, nil, nil, nil, nil
			end
		end
		return kind, nil, nil, payload.HeadStartSeconds, payload.DestinationPosition, payload.SpringLegsActive
	elseif kind == "CHASE_STARTED" or kind == "STAGE" then
		if typeof(payload.Stage) ~= "number" or payload.Stage % 1 ~= 0 or payload.Stage < 1 or payload.Stage > 3 then
			return nil, nil, nil, nil, nil, nil
		end
		for key in pairs(payload) do
			if key ~= "Kind" and key ~= "Stage" then
				return nil, nil, nil, nil, nil, nil
			end
		end
		return kind, payload.Stage, nil, nil, nil, nil
	elseif kind == "REVEALED" then
		if payload.SignatureId ~= "Kilnback" then
			return nil, nil, nil, nil, nil, nil
		end
		for key in pairs(payload) do
			if key ~= "Kind" and key ~= "SignatureId" then
				return nil, nil, nil, nil, nil, nil
			end
		end
		return kind, nil, payload.SignatureId, nil, nil, nil
	elseif kind == "CAUGHT" or kind == "SECURED" or kind == "CANCELLED" then
		for key in pairs(payload) do
			if key ~= "Kind" then
				return nil, nil, nil, nil, nil, nil
			end
		end
		return kind, nil, nil, nil, nil, nil
	end
	return nil, nil, nil, nil, nil, nil
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
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		clearChasePresentation()
	end)
	stateRemote.OnClientEvent:Connect(function(payload: any)
		local kind, stage, _, headStartSeconds, destinationPosition, springLegsActive = readPayload(payload)
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
				string.format(
					"POD STOLEN - SCRAP WARDEN WAKING\nRUN HOME  |  %.1fs HEAD START",
					headStartSeconds :: number
				),
				Color3.fromRGB(255, 190, 57),
				0,
				true
			)
			if springLegsActive then
				showSpringLegsActive()
			else
				hideSpringLegsActive()
			end
		elseif kind == "CHASE_STARTED" or kind == "STAGE" then
			if kind == "CHASE_STARTED" then
				hideSpringLegsActive()
			end
			showMessage(
				string.format("SCRAP WARDEN ACTIVE\nRETURN TO YOUR WORKSHOP  |  THREAT %d", stage :: number),
				Color3.fromRGB(255, 190, 57),
				0,
				true
			)
		elseif kind == "CAUGHT" then
			hideSpringLegsActive()
			clearObjectiveCue()
			showMessage("CAUGHT - FURNACE POD LOST\nBANKED INVENTORY AND BUILDS ARE SAFE", Color3.fromRGB(255, 92, 73), 2.2, false)
		elseif kind == "SECURED" then
			hideSpringLegsActive()
			clearObjectiveCue()
			showMessage("POD SECURED\nKILNBACK REVEAL INCOMING", Color3.fromRGB(95, 244, 154), 0, false)
		elseif kind == "REVEALED" then
			hideSpringLegsActive()
			clearObjectiveCue()
			showMessage("ODDITY REVEALED\nKILNBACK", Color3.fromRGB(255, 174, 48), 4, false)
		elseif kind == "CANCELLED" then
			clearChasePresentation()
		end
	end)
end

return FurnacePodChaseController
