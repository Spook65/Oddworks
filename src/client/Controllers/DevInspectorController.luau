--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevInspectorController = {}

local REMOTE_FOLDER_NAME = "ODDWORKSDevInspector"
local SNAPSHOT_REQUEST_NAME = "SnapshotRequest"
local SNAPSHOT_NAME = "Snapshot"
local SET_SPEED_NAME = "SetWalkSpeedRequest"
local RESET_SPEED_NAME = "ResetWalkSpeedRequest"
local REFRESH_INTERVAL_SECONDS = 1

local panel: Frame? = nil
local diagnosticsLabel: TextLabel? = nil
local feedbackLabel: TextLabel? = nil
local speedInput: TextBox? = nil
local snapshotRequest: RemoteEvent? = nil
local setSpeedRequest: RemoteEvent? = nil
local resetSpeedRequest: RemoteEvent? = nil
local started = false

local function requireRemote(folder: Folder, name: string): RemoteEvent
	local child = folder:WaitForChild(name)
	if not child:IsA("RemoteEvent") then
		error(string.format("[ODDWORKS][DevInspector] %s must be a RemoteEvent.", child:GetFullName()), 2)
	end
	return child
end

local function formatNumber(value: any): string
	return if typeof(value) == "number" and value == value and math.abs(value) < math.huge
		then string.format("%.2f", value)
		else "N/A"
end

local function formatInteger(value: any): string
	return if typeof(value) == "number" and value == value and math.abs(value) < math.huge
		then string.format("%d", value)
		else "N/A"
end

local function formatBoolean(value: any): string
	return if value == true then "YES" elseif value == false then "NO" else "N/A"
end

local function formatString(value: any): string
	return if typeof(value) == "string" and #value <= 512 then value else "N/A"
end

local function renderSnapshot(payload: any)
	local label = diagnosticsLabel
	if not label or typeof(payload) ~= "table" then
		return
	end

	local construct = payload.Construct
	local frameId = "None"
	local headId = "None"
	local armId = "None"
	local legsId = "None"
	if typeof(construct) == "table" then
		frameId = formatString(construct.FrameId)
		headId = formatString(construct.HeadComponentId)
		armId = formatString(construct.ArmComponentId)
		legsId = formatString(construct.LegsComponentId)
	end

	local overrideMarker = if payload.DevWalkSpeedOverride == true then " [DEV OVERRIDE]" else ""
	local wardenStage = if payload.WardenStage == nil then "N/A" else formatInteger(payload.WardenStage)
	label.Text = table.concat({
		string.format("PLAYER  %s (%s)", formatString(payload.PlayerName), formatInteger(payload.UserId)),
		"",
		"CHARACTER",
		string.format("Health: %s / %s", formatNumber(payload.Health), formatNumber(payload.MaxHealth)),
		string.format("WalkSpeed: %s%s", formatNumber(payload.WalkSpeed), overrideMarker),
		string.format("%s: %s", formatString(payload.JumpMode), formatNumber(payload.JumpValue)),
		"",
		"CONSTRUCT",
		string.format("Frame: %s", frameId),
		string.format("Head: %s", headId),
		string.format("Arm: %s", armId),
		string.format("Legs: %s", legsId),
		"",
		"CAPABILITIES (SERVER)",
		string.format("DetectStrangeSignals: %s", formatBoolean(payload.DetectStrangeSignals)),
		string.format("SpringLegsChaseCapability: %s", formatBoolean(payload.SpringLegsChaseCapability)),
		string.format("SpringLegsEffectApplied: %s", formatBoolean(payload.SpringLegsEffectApplied)),
		"",
		"SPRINGLEGS DIAGNOSTICS",
		string.format("Baseline: %s", formatNumber(payload.BaselineWalkSpeed)),
		string.format("Multiplier: %s", formatNumber(payload.ConfiguredSpringLegsMultiplier)),
		string.format("Expected: %s", formatNumber(payload.ExpectedSpringLegsWalkSpeed)),
		string.format("Current: %s", formatNumber(payload.WalkSpeed)),
		string.format("Eligible: %s", formatBoolean(payload.SpringLegsEligible)),
		string.format("Application Record: %s", formatBoolean(payload.SpringLegsApplicationRecord)),
		string.format("Speed Matches Expected: %s", formatBoolean(payload.SpringLegsSpeedMatchesExpected)),
		string.format("Applied: %s", formatBoolean(payload.SpringLegsEffectApplied)),
		string.format("DEV Override: %s", formatBoolean(payload.DevWalkSpeedOverride)),
		string.format("Override Value: %s", formatNumber(payload.DevOverrideWalkSpeed)),
		string.format("Pre-Override Baseline: %s", formatNumber(payload.DevOverrideBaselineWalkSpeed)),
		"",
		"FURNACE POD CHASE",
		string.format("Phase: %s", formatString(payload.ChasePhase)),
		string.format("IsCarrier: %s", formatBoolean(payload.IsCarrier)),
		string.format("WardenStage: %s", wardenStage),
		string.format("AssignedWorkshop: %s", formatString(payload.AssignedPlotId)),
		"",
		"PLAYER STATE",
		string.format("Scrap: %s", formatInteger(payload.Scrap)),
		string.format("Hype: %s", formatInteger(payload.Hype)),
		string.format("WorkshopLevel: %s", formatInteger(payload.WorkshopLevel)),
		string.format("AssignedPlotId: %s", formatString(payload.AssignedPlotId)),
		string.format("Unbanked: %s", formatString(payload.UnbankedSummary)),
		string.format("Banked: %s", formatString(payload.BankedSummary)),
	}, "\n")

	if typeof(payload.ActionMessage) == "string" and #payload.ActionMessage <= 256 and feedbackLabel then
		feedbackLabel.Text = payload.ActionMessage
		feedbackLabel.TextColor3 = if payload.ActionSucceeded == true
			then Color3.fromRGB(127, 231, 158)
			else Color3.fromRGB(249, 151, 119)
	end
end

local function requestRefresh()
	local remote = snapshotRequest
	if remote then
		remote:FireServer()
	end
end

local function makeButton(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(55, 63, 61)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(232, 237, 226)
	button.TextSize = 13
	button.Parent = parent
	return button
end

local function createInterface()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSDevInspectorGui"
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local toggle = makeButton(
		screenGui,
		"ToggleButton",
		"DEV",
		UDim2.new(1, -72, 0, 12),
		UDim2.fromOffset(58, 30)
	)
	toggle.BackgroundColor3 = Color3.fromRGB(45, 93, 80)

	local inspectorPanel = Instance.new("Frame")
	inspectorPanel.Name = "InspectorPanel"
	inspectorPanel.AnchorPoint = Vector2.new(1, 0)
	inspectorPanel.Position = UDim2.new(1, -14, 0, 50)
	inspectorPanel.Size = UDim2.fromOffset(430, 590)
	inspectorPanel.BackgroundColor3 = Color3.fromRGB(26, 30, 29)
	inspectorPanel.BackgroundTransparency = 0.02
	inspectorPanel.BorderSizePixel = 0
	inspectorPanel.Visible = false
	inspectorPanel.Parent = screenGui
	panel = inspectorPanel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(14, 8)
	title.Size = UDim2.new(1, -182, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "ODDWORKS DEV INSPECTOR"
	title.TextColor3 = Color3.fromRGB(130, 234, 187)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = inspectorPanel

	local refreshButton = makeButton(
		inspectorPanel,
		"RefreshButton",
		"REFRESH",
		UDim2.new(1, -156, 0, 9),
		UDim2.fromOffset(96, 32)
	)
	local closeButton = makeButton(
		inspectorPanel,
		"CloseButton",
		"X",
		UDim2.new(1, -50, 0, 9),
		UDim2.fromOffset(36, 32)
	)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "DiagnosticsScroll"
	scroll.Position = UDim2.fromOffset(12, 50)
	scroll.Size = UDim2.new(1, -24, 1, -174)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.BackgroundColor3 = Color3.fromRGB(18, 21, 21)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 7
	scroll.Parent = inspectorPanel

	local diagnostics = Instance.new("TextLabel")
	diagnostics.Name = "Diagnostics"
	diagnostics.Position = UDim2.fromOffset(10, 8)
	diagnostics.Size = UDim2.new(1, -26, 0, 0)
	diagnostics.AutomaticSize = Enum.AutomaticSize.Y
	diagnostics.BackgroundTransparency = 1
	diagnostics.Font = Enum.Font.Code
	diagnostics.Text = "Open inspector to request server state."
	diagnostics.TextColor3 = Color3.fromRGB(221, 225, 215)
	diagnostics.TextSize = 14
	diagnostics.TextWrapped = true
	diagnostics.TextXAlignment = Enum.TextXAlignment.Left
	diagnostics.TextYAlignment = Enum.TextYAlignment.Top
	diagnostics.Parent = scroll
	diagnosticsLabel = diagnostics

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "SpeedLabel"
	speedLabel.Position = UDim2.new(0, 12, 1, -114)
	speedLabel.Size = UDim2.fromOffset(110, 32)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Font = Enum.Font.GothamBold
	speedLabel.Text = "WALK SPEED"
	speedLabel.TextColor3 = Color3.fromRGB(197, 202, 190)
	speedLabel.TextSize = 13
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.Parent = inspectorPanel

	local input = Instance.new("TextBox")
	input.Name = "WalkSpeedInput"
	input.Position = UDim2.new(0, 116, 1, -114)
	input.Size = UDim2.fromOffset(66, 32)
	input.BackgroundColor3 = Color3.fromRGB(43, 48, 47)
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = Enum.Font.Code
	input.PlaceholderText = "4-50"
	input.Text = "22"
	input.TextColor3 = Color3.fromRGB(242, 239, 219)
	input.TextSize = 15
	input.Parent = inspectorPanel
	speedInput = input

	local setButton = makeButton(
		inspectorPanel,
		"SetWalkSpeedButton",
		"SET",
		UDim2.new(0, 190, 1, -114),
		UDim2.fromOffset(70, 32)
	)
	local resetButton = makeButton(
		inspectorPanel,
		"ResetWalkSpeedButton",
		"RESET",
		UDim2.new(0, 268, 1, -114),
		UDim2.fromOffset(94, 32)
	)

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.Position = UDim2.new(0, 12, 1, -72)
	feedback.Size = UDim2.new(1, -24, 0, 58)
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.Gotham
	feedback.Text = "Studio only. Local player inspection."
	feedback.TextColor3 = Color3.fromRGB(166, 178, 169)
	feedback.TextSize = 13
	feedback.TextWrapped = true
	feedback.TextXAlignment = Enum.TextXAlignment.Left
	feedback.TextYAlignment = Enum.TextYAlignment.Top
	feedback.Parent = inspectorPanel
	feedbackLabel = feedback

	toggle.Activated:Connect(function()
		inspectorPanel.Visible = not inspectorPanel.Visible
		if inspectorPanel.Visible then
			requestRefresh()
		end
	end)
	closeButton.Activated:Connect(function()
		inspectorPanel.Visible = false
	end)
	refreshButton.Activated:Connect(requestRefresh)
	setButton.Activated:Connect(function()
		local remote = setSpeedRequest
		local textBox = speedInput
		local value = if textBox then tonumber(textBox.Text) else nil
		if not remote or not value then
			feedback.Text = "Enter a numeric WalkSpeed from 4 to 50."
			feedback.TextColor3 = Color3.fromRGB(249, 151, 119)
			return
		end
		remote:FireServer(value)
	end)
	resetButton.Activated:Connect(function()
		local remote = resetSpeedRequest
		if remote then
			remote:FireServer()
		end
	end)
end

function DevInspectorController.Start()
	if started then
		return
	end
	started = true
	if not RunService:IsStudio() then
		return
	end

	local folder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME, 10)
	if not folder or not folder:IsA("Folder") then
		warn("[ODDWORKS][DevInspector] Studio remote folder was not created; inspector disabled.")
		return
	end
	snapshotRequest = requireRemote(folder, SNAPSHOT_REQUEST_NAME)
	local snapshot = requireRemote(folder, SNAPSHOT_NAME)
	setSpeedRequest = requireRemote(folder, SET_SPEED_NAME)
	resetSpeedRequest = requireRemote(folder, RESET_SPEED_NAME)
	createInterface()

	snapshot.OnClientEvent:Connect(renderSnapshot)
	task.spawn(function()
		while started do
			task.wait(REFRESH_INTERVAL_SECONDS)
			if panel and panel.Visible then
				requestRefresh()
			end
		end
	end)
end

return DevInspectorController
