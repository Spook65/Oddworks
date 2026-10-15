--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local OddityContainmentController = {}

local panel: Frame? = nil
local statusLabel: TextLabel? = nil
local gateALabel: TextLabel? = nil
local gateBLabel: TextLabel? = nil
local presentationToken = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][OddityContainmentController] %s.%s must be a %s, but found %s.",
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

local function createText(parent: Instance, name: string, position: UDim2, size: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(235, 239, 232)
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function createPresentation()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSOddityContainmentGui"
	screenGui.DisplayOrder = 13
	screenGui.ResetOnSpawn = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local activityPanel = Instance.new("Frame")
	activityPanel.Name = "ContainmentPanel"
	activityPanel.AnchorPoint = Vector2.new(1, 0)
	activityPanel.Position = UDim2.new(1, -22, 0, 22)
	activityPanel.Size = UDim2.fromOffset(280, 138)
	activityPanel.BackgroundColor3 = Color3.fromRGB(24, 35, 36)
	activityPanel.BackgroundTransparency = 0.08
	activityPanel.BorderSizePixel = 0
	activityPanel.Visible = false
	activityPanel.Parent = screenGui
	panel = activityPanel

	local title = createText(activityPanel, "Title", UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 28), 18)
	title.Text = "ODDITY CONTAINMENT"
	title.TextColor3 = Color3.fromRGB(102, 238, 221)

	local status = createText(activityPanel, "Status", UDim2.fromOffset(16, 40), UDim2.new(1, -32, 0, 38), 15)
	status.Text = "CONTAINMENT ACTIVE"
	statusLabel = status

	local gateA = createText(activityPanel, "GateA", UDim2.fromOffset(16, 82), UDim2.new(0.5, -20, 0, 38), 14)
	gateA.Text = "GATE A\nOPEN"
	gateALabel = gateA

	local gateB = createText(activityPanel, "GateB", UDim2.new(0.5, 4, 0, 82), UDim2.new(0.5, -20, 0, 38), 14)
	gateB.Text = "GATE B\nOPEN"
	gateBLabel = gateB
end

local function setGateLabel(label: TextLabel?, gateName: string, isOpen: boolean)
	if not label then
		return
	end
	label.Text = string.format("%s\n%s", gateName, if isOpen then "OPEN" else "CLOSED")
	label.TextColor3 = if isOpen then Color3.fromRGB(111, 255, 173) else Color3.fromRGB(255, 126, 91)
end

local function showActive(gateAOpen: boolean, gateBOpen: boolean)
	presentationToken += 1
	if panel then
		panel.BackgroundTransparency = 0.08
		panel.Visible = true
	end
	if statusLabel then
		statusLabel.Text = "CONTAINMENT ACTIVE\nShape Sparkmite's route with the gates"
		statusLabel.TextColor3 = Color3.fromRGB(235, 239, 232)
	end
	setGateLabel(gateALabel, "GATE A", gateAOpen)
	setGateLabel(gateBLabel, "GATE B", gateBOpen)
end

local function showResult(text: string, color: Color3, duration: number)
	local activityPanel = panel
	local status = statusLabel
	if not activityPanel or not status then
		return
	end
	presentationToken += 1
	local token = presentationToken
	activityPanel.BackgroundTransparency = 0.08
	activityPanel.Visible = true
	status.Text = text
	status.TextColor3 = color
	if gateALabel then
		gateALabel.Text = ""
	end
	if gateBLabel then
		gateBLabel.Text = ""
	end

	task.delay(duration, function()
		if presentationToken ~= token or not panel then
			return
		end
		local tween = TweenService:Create(panel, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			if presentationToken == token and panel then
				panel.Visible = false
			end
		end)
	end)
end

local function hasExactKeys(payload: { [any]: any }, expected: { [string]: boolean }): boolean
	local expectedCount = 0
	for _ in pairs(expected) do
		expectedCount += 1
	end
	local seenCount = 0
	for key in pairs(payload) do
		if typeof(key) ~= "string" or not expected[key] then
			return false
		end
		seenCount += 1
	end
	return seenCount == expectedCount
end

local function handleState(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
		return
	end
	local kind = payload.Kind
	if kind == "ACTIVE" or kind == "GATE_STATE" then
		if not hasExactKeys(payload, { Kind = true, GateAOpen = true, GateBOpen = true })
			or typeof(payload.GateAOpen) ~= "boolean"
			or typeof(payload.GateBOpen) ~= "boolean"
		then
			return
		end
		showActive(payload.GateAOpen, payload.GateBOpen)
	elseif kind == "CONTAINED" then
		if not hasExactKeys(payload, { Kind = true, ComponentId = true, Rarity = true, Count = true })
			or payload.ComponentId ~= "ServoArm"
			or payload.Rarity ~= "Rare"
			or payload.Count ~= 1
		then
			return
		end
		showResult("SPARKMITE CONTAINED\nServo Arm [Rare] banked", Color3.fromRGB(111, 255, 173), 4)
	elseif kind == "ESCAPED" then
		if hasExactKeys(payload, { Kind = true }) then
			showResult("SPARKMITE ESCAPED\nContainment resetting", Color3.fromRGB(255, 126, 91), 2.5)
		end
	elseif kind == "REWARD_FAILED" then
		if hasExactKeys(payload, { Kind = true }) then
			showResult("REWARD COULD NOT BE BANKED\nContainment resetting", Color3.fromRGB(255, 190, 73), 2.5)
		end
	elseif kind == "COMPLETED" then
		if hasExactKeys(payload, { Kind = true }) then
			showResult("SESSION REWARD COMPLETE\nServo Arm [Rare] already banked", Color3.fromRGB(111, 255, 173), 2.5)
		end
	elseif kind == "CANCELLED" and hasExactKeys(payload, { Kind = true }) then
		presentationToken += 1
		if panel then
			panel.Visible = false
		end
	end
end

function OddityContainmentController.Start()
	if started then
		return
	end
	started = true
	createPresentation()

	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local remote = requireChildOfClass(network, "OddityContainmentState", "RemoteEvent") :: RemoteEvent
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		presentationToken += 1
		if panel then
			panel.Visible = false
		end
	end)
	remote.OnClientEvent:Connect(handleState)
end

return OddityContainmentController
