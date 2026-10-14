--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RecoveryFeelEffects = require(script.Parent.RecoveryFeelEffects)

local KineticPodRecoveryController = {}

type KineticGuidanceMode = "EDGE" | "WORLD" | "NEAR"

local KINETIC_OBJECTIVE_TEXT = "RECOVER THE KINETIC POD"
local KINETIC_NEAR_ENTER_DISTANCE = 10
local KINETIC_NEAR_EXIT_DISTANCE = 13
local KINETIC_MARKER_MAX_DISTANCE = 500

local banner: TextLabel? = nil
local objectiveTarget: Part? = nil
local objectiveBillboard: BillboardGui? = nil
local objectiveLabel: TextLabel? = nil
local objectiveEdge: Frame? = nil
local objectiveEdgeArrow: TextLabel? = nil
local objectiveEdgeText: TextLabel? = nil
local objectiveConnection: RBXScriptConnection? = nil
local objectiveDestination: Vector3? = nil
local objectiveText = ""
local objectiveIsFreshKinetic = false
local kineticGuidanceMode: KineticGuidanceMode? = nil
local savedProgressDestination: Vector3? = nil
local savedProgressText: string? = nil
local ftueRequestRemote: RemoteEvent? = nil
local presentationToken = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][KineticPodRecoveryController] %s.%s must be a %s, but found %s.",
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
	screenGui.Name = "ODDWORKSKineticRecoveryGui"
	screenGui.DisplayOrder = 13
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "RecoveryBanner"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.07, 0)
	label.Size = UDim2.new(0.72, 0, 0, 88)
	label.BackgroundColor3 = Color3.fromRGB(25, 42, 46)
	label.BackgroundTransparency = 0.08
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(108, 232, 255)
	label.TextScaled = true
	label.TextWrapped = true
	label.Visible = false
	label.Parent = screenGui
	banner = label

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(620, 88)
	sizeConstraint.MinSize = Vector2.new(300, 88)
	sizeConstraint.Parent = label

	local edge = Instance.new("Frame")
	edge.Name = "KineticObjectiveEdge"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Size = UDim2.fromOffset(220, 42)
	edge.BackgroundColor3 = Color3.fromRGB(21, 42, 47)
	edge.BackgroundTransparency = 0.08
	edge.BorderSizePixel = 0
	edge.Visible = false
	edge.ZIndex = 14
	edge.Parent = screenGui
	objectiveEdge = edge

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Direction"
	arrow.Position = UDim2.fromOffset(5, 6)
	arrow.Size = UDim2.fromOffset(30, 30)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = ">"
	arrow.TextColor3 = Color3.fromRGB(108, 232, 255)
	arrow.TextSize = 24
	arrow.ZIndex = 15
	arrow.Parent = edge
	objectiveEdgeArrow = arrow

	local text = Instance.new("TextLabel")
	text.Name = "Objective"
	text.Position = UDim2.fromOffset(39, 0)
	text.Size = UDim2.new(1, -45, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(225, 251, 255)
	text.TextSize = 13
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.ZIndex = 15
	text.Parent = edge
	objectiveEdgeText = text
end

local function clearObjective()
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
	objectiveText = ""
	objectiveIsFreshKinetic = false
	kineticGuidanceMode = nil
	if objectiveEdge then
		objectiveEdge.Visible = false
	end
end

local function isInsideViewportInset(viewportPoint: Vector3, viewportSize: Vector2, horizontal: number, top: number, bottom: number): boolean
	return viewportPoint.Z > 0
		and viewportPoint.X >= horizontal
		and viewportPoint.X <= viewportSize.X - horizontal
		and viewportPoint.Y >= top
		and viewportPoint.Y <= viewportSize.Y - bottom
end

local function updateObjective()
	local destination = objectiveDestination
	local edge = objectiveEdge
	local arrow = objectiveEdgeArrow
	local edgeText = objectiveEdgeText
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not destination or not edge or not arrow or not edgeText or not camera or not root or not root:IsA("BasePart") then
		if edge then
			edge.Visible = false
		end
		if objectiveBillboard then
			objectiveBillboard.Enabled = false
		end
		return
	end

	local distance = (root.Position - destination).Magnitude
	local displayText = string.format("%s\n%dm", objectiveText, math.floor(distance + 0.5))
	if objectiveLabel then
		objectiveLabel.Text = displayText
	end
	local viewportPoint, onScreen = camera:WorldToViewportPoint(destination)
	local viewportSize = camera.ViewportSize
	if objectiveIsFreshKinetic then
		local mode = kineticGuidanceMode
		if mode == "NEAR" then
			if distance >= KINETIC_NEAR_EXIT_DISTANCE then
				mode = nil
			end
		elseif distance <= KINETIC_NEAR_ENTER_DISTANCE then
			mode = "NEAR"
		end

		if mode ~= "NEAR" then
			local firmlyOnScreen = onScreen and isInsideViewportInset(viewportPoint, viewportSize, 120, 110, 80)
			local remainsOnScreen = isInsideViewportInset(viewportPoint, viewportSize, 45, 55, 35)
			if mode == "WORLD" then
				mode = if remainsOnScreen then "WORLD" else "EDGE"
			elseif mode == "EDGE" then
				mode = if firmlyOnScreen then "WORLD" else "EDGE"
			else
				mode = if firmlyOnScreen then "WORLD" else "EDGE"
			end
		end

		kineticGuidanceMode = mode
		if objectiveBillboard then
			objectiveBillboard.Enabled = mode == "WORLD"
		end
		edge.Visible = mode == "EDGE"
		if mode ~= "EDGE" then
			return
		end
	elseif objectiveBillboard then
		objectiveBillboard.Enabled = distance > 9
	end

	local comfortablyVisible = onScreen
		and viewportPoint.Z > 0
		and viewportPoint.X >= 90
		and viewportPoint.X <= viewportSize.X - 90
		and viewportPoint.Y >= 100
		and viewportPoint.Y <= viewportSize.Y - 70
	if not objectiveIsFreshKinetic and comfortablyVisible then
		edge.Visible = false
		return
	end

	local center = viewportSize * 0.5
	local direction = Vector2.new(viewportPoint.X, viewportPoint.Y) - center
	if viewportPoint.Z <= 0 then
		direction = -direction
	end
	if direction.Magnitude < 0.001 then
		direction = Vector2.new(1, 0)
	end
	local unit = direction.Unit
	local scale = math.min(
		math.max(center.X - 130, 1) / math.max(math.abs(unit.X), 0.001),
		math.max(center.Y - 115, 1) / math.max(math.abs(unit.Y), 0.001)
	)
	local position = center + unit * scale
	position = Vector2.new(
		math.clamp(position.X, 117, viewportSize.X - 117),
		math.clamp(position.Y, 105, viewportSize.Y - 55)
	)
	edge.Position = UDim2.fromOffset(position.X, position.Y)
	arrow.Rotation = math.deg(math.atan2(unit.Y, unit.X))
	edgeText.Text = displayText
	edge.Visible = true
end

local function showObjective(destination: Vector3, text: string)
	clearObjective()
	local isFreshKinetic = text == KINETIC_OBJECTIVE_TEXT
	objectiveIsFreshKinetic = isFreshKinetic
	local target = Instance.new("Part")
	target.Name = "LocalKineticObjective"
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Size = Vector3.new(0.2, 0.2, 0.2)
	target.Transparency = 1
	target.Position = destination + Vector3.new(0, if isFreshKinetic then 7.5 else 2.8, 0)
	target.Parent = Workspace
	objectiveTarget = target
	local objectiveColor = if string.find(text, "FURNACE", 1, true)
		then Color3.fromRGB(255, 183, 62)
		elseif text == "RETURN TO WORKSHOP"
		then Color3.fromRGB(117, 255, 178)
		elseif string.find(text, "SPRINGLEGS", 1, true)
		then Color3.fromRGB(117, 255, 178)
		else Color3.fromRGB(108, 232, 255)
	local light = Instance.new("PointLight")
	light.Name = "ObjectivePulse"
	light.Color = objectiveColor
	light.Brightness = 0.8
	light.Range = 13
	light.Shadows = false
	light.Parent = target
	TweenService:Create(
		light,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Brightness = 2.2 }
	):Play()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "KineticObjectiveLabel"
	billboard.Adornee = target
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = if isFreshKinetic then KINETIC_MARKER_MAX_DISTANCE else 140
	billboard.Size = UDim2.fromOffset(185, 48)
	billboard.Parent = target
	objectiveBillboard = billboard

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(21, 42, 47)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = objectiveColor
	label.TextSize = 13
	label.TextWrapped = true
	label.Parent = billboard
	objectiveLabel = label
	objectiveDestination = destination
	objectiveText = text
	if objectiveEdgeArrow then
		objectiveEdgeArrow.TextColor3 = objectiveColor
	end
	if objectiveEdgeText then
		objectiveEdgeText.TextColor3 = objectiveColor
	end
	objectiveConnection = RunService.RenderStepped:Connect(updateObjective)
	updateObjective()
end

local function showMessage(text: string, color: Color3, duration: number)
	local label = banner
	if not label then
		return
	end
	presentationToken += 1
	local token = presentationToken
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.08
	label.Visible = true
	if duration <= 0 then
		return
	end
	task.delay(duration, function()
		if presentationToken ~= token or not banner then
			return
		end
		local tween = TweenService:Create(banner, TweenInfo.new(0.3), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if presentationToken == token and banner then
				banner.Visible = false
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

local function readPayload(payload: any): { [string]: any }?
	if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
		return nil
	end
	local kind = payload.Kind
	if kind == "ACTIVATING" then
		if typeof(payload.HeadStartSeconds) ~= "number"
			or payload.HeadStartSeconds < 1
			or payload.HeadStartSeconds > 5
			or not isFiniteVector3(payload.DestinationPosition)
			or typeof(payload.SpringLegsActive) ~= "boolean"
		then
			return nil
		end
	elseif kind == "CHASE_STARTED" or kind == "STAGE" then
		if typeof(payload.Stage) ~= "number" or payload.Stage % 1 ~= 0 or payload.Stage < 1 or payload.Stage > 3 then
			return nil
		end
	elseif kind == "SECURED" then
		if payload.OddlingId ~= "Voltlet"
			or typeof(payload.OwnedCount) ~= "number"
			or payload.OwnedCount < 1
			or payload.OwnedCount % 1 ~= 0
			or typeof(payload.SpringLegsBonusGranted) ~= "boolean"
			or payload.ComponentId ~= "SpringLegs"
			or payload.Rarity ~= "Common"
			or payload.Count ~= 1
			or typeof(payload.FTUEManaged) ~= "boolean"
			or (payload.NextStep ~= "EQUIP" and payload.NextStep ~= "FURNACE")
			or not isFiniteVector3(payload.DestinationPosition)
		then
			return nil
		end
	elseif kind == "EQUIP_GUIDANCE" or kind == "ADVANCED_AVAILABLE" then
		if not isFiniteVector3(payload.DestinationPosition) then
			return nil
		end
	elseif kind ~= "CAUGHT" and kind ~= "CANCELLED" and kind ~= "REWARD_FAILED" then
		return nil
	end
	return payload
end

local function rememberProgress(destination: Vector3, text: string)
	savedProgressDestination = destination
	savedProgressText = text
	showObjective(destination, text)
end

local function handleKineticState(payload: any)
	local validated = readPayload(payload)
	if not validated then
		return
	end
	local kind = validated.Kind
	if kind == "ACTIVATING" then
		savedProgressDestination = nil
		savedProgressText = nil
		RecoveryFeelEffects.Theft(Color3.fromRGB(58, 225, 255))
		showObjective(validated.DestinationPosition, "RETURN TO WORKSHOP")
		showMessage(
			string.format("KINETIC POD STOLEN\nSCOUT WARDEN WAKING  |  %.1fs HEAD START", validated.HeadStartSeconds),
			Color3.fromRGB(108, 232, 255),
			0
		)
	elseif kind == "CHASE_STARTED" or kind == "STAGE" then
		if kind == "CHASE_STARTED" then
			RecoveryFeelEffects.StartThreat(
				"KineticPodRecovery",
				"ScoutWarden",
				Color3.fromRGB(255, 128, 72),
				validated.Stage
			)
		else
			RecoveryFeelEffects.SetThreatStage(validated.Stage)
		end
		showMessage(
			string.format("SCOUT WARDEN ACTIVE\nRETURN HOME  |  THREAT %d", validated.Stage),
			Color3.fromRGB(108, 232, 255),
			0
		)
	elseif kind == "CAUGHT" then
		clearObjective()
		RecoveryFeelEffects.Caught()
		showMessage("POD LOST\nTHE SCOUT WARDEN CAUGHT YOU\nTRY AGAIN", Color3.fromRGB(255, 104, 82), 2.4)
	elseif kind == "CANCELLED" then
		clearObjective()
		RecoveryFeelEffects.Clear()
		showMessage("KINETIC RECOVERY CANCELLED", Color3.fromRGB(224, 155, 122), 1.8)
	elseif kind == "REWARD_FAILED" then
		clearObjective()
		RecoveryFeelEffects.Clear()
		showMessage("RECOVERY COULD NOT COMPLETE\nTRY AGAIN", Color3.fromRGB(255, 104, 82), 2.4)
	elseif kind == "SECURED" then
		clearObjective()
		RecoveryFeelEffects.Secured()
		if validated.FTUEManaged then
			showMessage("POD SECURED", Color3.fromRGB(117, 255, 178), 1.1)
			local token = presentationToken
			task.delay(1.2, function()
				if presentationToken == token then
					RecoveryFeelEffects.Revealed(Color3.fromRGB(58, 225, 255), false)
					showMessage("VOLTLET RECOVERED", Color3.fromRGB(108, 232, 255), 1.8)
				end
			end)
			return
		end
		showMessage("POD SECURED", Color3.fromRGB(117, 255, 178), 1.1)
		local rewardText = string.format("VOLTLET DISCOVERED  |  OWNED x%d", validated.OwnedCount)
		if validated.SpringLegsBonusGranted then
			rewardText ..= "\nFIRST RECOVERY BONUS: SPRINGLEGS"
		end
		local text = if validated.NextStep == "FURNACE" then "FURNACE POD - HIGH SECURITY" else "EQUIP SPRINGLEGS AT ASSEMBLER"
		local token = presentationToken
		task.delay(1.2, function()
			if presentationToken ~= token then
				return
			end
			RecoveryFeelEffects.Revealed(Color3.fromRGB(58, 225, 255), false)
			showMessage(rewardText, Color3.fromRGB(108, 232, 255), 2.8)
			local rewardToken = presentationToken
			task.delay(2.9, function()
				if presentationToken ~= rewardToken then
					return
				end
				rememberProgress(validated.DestinationPosition, text)
				if validated.NextStep == "FURNACE" then
					showMessage("ADVANCED RECOVERY AVAILABLE\nFURNACE POD - HIGH SECURITY\nREWARD: SIGNATURE ODDITY", Color3.fromRGB(255, 183, 62), 4)
				elseif validated.SpringLegsBonusGranted then
					showMessage("SPRINGLEGS AVAILABLE - NOT INSTALLED\nSELECT SPRINGLEGS, THEN REBUILD", Color3.fromRGB(117, 255, 178), 4)
				end
			end)
		end)
	elseif kind == "EQUIP_GUIDANCE" then
		rememberProgress(validated.DestinationPosition, "EQUIP SPRINGLEGS AT ASSEMBLER")
		showMessage("SPRINGLEGS AVAILABLE - NOT INSTALLED\nSELECT SPRINGLEGS, THEN REBUILD", Color3.fromRGB(117, 255, 178), 3)
	elseif kind == "ADVANCED_AVAILABLE" then
		rememberProgress(validated.DestinationPosition, "FURNACE POD - HIGH SECURITY")
		showMessage("SPRINGLEGS INSTALLED\nADVANCED RECOVERY: FURNACE POD", Color3.fromRGB(255, 183, 62), 3.5)
	end
end

local function readFTUEPayload(payload: any): { [string]: any }?
	if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
		return nil
	end
	local kind = payload.Kind
	if kind == "KINETIC_OBJECTIVE" or kind == "SPRINGLEGS_GUIDANCE" or kind == "ADVANCED_GUIDANCE" then
		if not isFiniteVector3(payload.DestinationPosition) then
			return nil
		end
	elseif kind == "FIRST_HYPE" then
		if typeof(payload.Amount) ~= "number"
			or payload.Amount % 1 ~= 0
			or payload.Amount < 1
			or payload.Amount > 1000000
		then
			return nil
		end
	elseif kind ~= "SPRINGLEGS_INSTALLED" then
		return nil
	end
	return payload
end

local function handleFTUEState(payload: any)
	local validated = readFTUEPayload(payload)
	if not validated then
		return
	end
	local kind = validated.Kind
	if kind == "KINETIC_OBJECTIVE" then
		rememberProgress(validated.DestinationPosition, "RECOVER THE KINETIC POD")
	elseif kind == "FIRST_HYPE" then
		clearObjective()
		showMessage(
			string.format("+%d HYPE\nDISPLAYED ODDLINGS GENERATE HYPE", validated.Amount),
			Color3.fromRGB(255, 220, 91),
			3
		)
	elseif kind == "SPRINGLEGS_GUIDANCE" then
		rememberProgress(validated.DestinationPosition, "INSTALL SPRINGLEGS")
		showMessage(
			"NEW COMPONENT AVAILABLE\nSPRINGLEGS\nINSTALL AT PROTOTYPE ASSEMBLER",
			Color3.fromRGB(117, 255, 178),
			4
		)
	elseif kind == "SPRINGLEGS_INSTALLED" then
		clearObjective()
		showMessage("SPRINGLEGS INSTALLED\nCHASE MOBILITY BOOST", Color3.fromRGB(117, 255, 178), 2.4)
	elseif kind == "ADVANCED_GUIDANCE" then
		rememberProgress(validated.DestinationPosition, "FURNACE POD - HIGH SECURITY")
		showMessage(
			"ADVANCED RECOVERY\nFURNACE POD - HIGH SECURITY\nREWARD: SIGNATURE ODDLING",
			Color3.fromRGB(255, 183, 62),
			4
		)
	end
end

function KineticPodRecoveryController.Start()
	if started then
		return
	end
	started = true
	createPresentation()

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local kineticRemote = requireChildOfClass(network, "KineticPodRecoveryState", "RemoteEvent") :: RemoteEvent
	local furnaceRemote = requireChildOfClass(network, "FurnacePodChaseState", "RemoteEvent") :: RemoteEvent
	local ftueStateRemote = requireChildOfClass(network, "FirstTimeExperienceState", "RemoteEvent") :: RemoteEvent
	ftueRequestRemote = requireChildOfClass(network, "FirstTimeExperienceRequest", "RemoteEvent") :: RemoteEvent
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		presentationToken += 1
		clearObjective()
		RecoveryFeelEffects.Clear()
		if banner then
			banner.Visible = false
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.delay(0.4, function()
			local request = ftueRequestRemote
			if request then
				request:FireServer()
			end
		end)
	end)
	kineticRemote.OnClientEvent:Connect(handleKineticState)
	ftueStateRemote.OnClientEvent:Connect(handleFTUEState)
	furnaceRemote.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
			return
		end
		if payload.Kind == "ACTIVATING" or payload.Kind == "CHASE_STARTED" then
			clearObjective()
		elseif payload.Kind == "CAUGHT" or payload.Kind == "CANCELLED" then
			local destination = savedProgressDestination
			local text = savedProgressText
			if destination and text then
				showObjective(destination, text)
			end
		elseif payload.Kind == "SECURED" or payload.Kind == "REVEALED" then
			savedProgressDestination = nil
			savedProgressText = nil
			clearObjective()
		end
	end)
	local initialRequest = ftueRequestRemote
	if initialRequest then
		initialRequest:FireServer()
	end
end

return KineticPodRecoveryController
