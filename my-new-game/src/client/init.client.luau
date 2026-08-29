local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local remotes = ReplicatedStorage:WaitForChild(GameConfig.RemotesFolderName)
local stateRemote = remotes:WaitForChild("StateUpdate")
local noticeRemote = remotes:WaitForChild("Notice")
local stateRequestRemote = remotes:WaitForChild("StateRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "OddworksHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "StatusPanel"
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.fromOffset(18, 18)
panel.Size = UDim2.new(0.86, 0, 0, 112)
panel.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui

local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(340, 112)
panelSize.MinSize = Vector2.new(280, 112)
panelSize.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(82, 98, 118)
stroke.Thickness = 1
stroke.Transparency = 0.25
stroke.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = panel

local function makeLabel(name: string, position: UDim2, size: UDim2, font: Enum.Font, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.Parent = panel
	return label
end

local title = makeLabel("Title", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 24), Enum.Font.GothamBold, 18, Color3.fromRGB(255, 255, 255))
title.Text = "ODDWORKS PROTOTYPE"

local objective = makeLabel("Objective", UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 24), Enum.Font.GothamMedium, 15, Color3.fromRGB(216, 229, 238))
objective.Text = "Objective: Loading"

local cores = makeLabel("Cores", UDim2.fromOffset(0, 60), UDim2.new(0.5, -8, 0, 24), Enum.Font.GothamBold, 15, Color3.fromRGB(252, 220, 88))
cores.Text = "Cores 0/" .. GameConfig.CoreGoal

local keycard = makeLabel("Keycard", UDim2.new(0.5, 8, 0, 60), UDim2.new(0.5, -8, 0, 24), Enum.Font.GothamBold, 15, Color3.fromRGB(118, 226, 172))
keycard.Text = "Keycard Missing"

local notice = Instance.new("TextLabel")
notice.Name = "Notice"
notice.AnchorPoint = Vector2.new(0.5, 1)
notice.Position = UDim2.new(0.5, 0, 1, -42)
notice.Size = UDim2.new(0.86, 0, 0, 48)
notice.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
notice.BackgroundTransparency = 1
notice.BorderSizePixel = 0
notice.Font = Enum.Font.GothamBold
notice.Text = ""
notice.TextColor3 = Color3.fromRGB(255, 255, 255)
notice.TextSize = 18
notice.TextTransparency = 1
notice.TextWrapped = true
notice.Parent = gui

local noticeSize = Instance.new("UISizeConstraint")
noticeSize.MaxSize = Vector2.new(520, 48)
noticeSize.MinSize = Vector2.new(280, 48)
noticeSize.Parent = notice

local noticeCorner = Instance.new("UICorner")
noticeCorner.CornerRadius = UDim.new(0, 8)
noticeCorner.Parent = notice

local noticeStroke = Instance.new("UIStroke")
noticeStroke.Color = Color3.fromRGB(255, 255, 255)
noticeStroke.Thickness = 1
noticeStroke.Transparency = 1
noticeStroke.Parent = notice

local function renderState(state)
	local currentCores = state.cores or 0
	local requiredCores = state.requiredCores or GameConfig.CoreGoal

	objective.Text = "Objective: " .. (state.objective or "Loading")
	cores.Text = string.format("Cores %d/%d", currentCores, requiredCores)
	keycard.Text = if state.hasKeycard then "Keycard Ready" else "Keycard Missing"
	keycard.TextColor3 = if state.hasKeycard then Color3.fromRGB(118, 226, 172) else Color3.fromRGB(236, 142, 116)

	if state.completed then
		objective.TextColor3 = Color3.fromRGB(118, 226, 172)
	else
		objective.TextColor3 = Color3.fromRGB(216, 229, 238)
	end
end

local activeNoticeTween: Tween?
local function showNotice(message: string)
	if activeNoticeTween then
		activeNoticeTween:Cancel()
	end

	notice.Text = message
	notice.BackgroundTransparency = 0.12
	notice.TextTransparency = 0
	noticeStroke.Transparency = 0.65

	task.delay(2.4, function()
		activeNoticeTween = TweenService:Create(notice, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		local strokeTween = TweenService:Create(noticeStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		})
		activeNoticeTween:Play()
		strokeTween:Play()
	end)
end

stateRemote.OnClientEvent:Connect(renderState)
noticeRemote.OnClientEvent:Connect(showNotice)
stateRequestRemote:FireServer()
