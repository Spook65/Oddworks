--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RecoveryFeelEffects = {}

local impactOverlay: Frame? = nil
local threatOverlay: Frame? = nil
local threatConnection: RBXScriptConnection? = nil
local threatFolderName: string? = nil
local threatModelName: string? = nil
local threatModel: Model? = nil
local threatColor = Color3.new(1, 1, 1)
local threatStage = 1
local impactToken = 0
local cameraToken = 0
local cameraTween: Tween? = nil
local cameraBaseline: number? = nil
local cameraForEffect: Camera? = nil

local function ensurePresentation()
	if impactOverlay and threatOverlay then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSRecoveryFeelGui"
	screenGui.DisplayOrder = 11
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local threat = Instance.new("Frame")
	threat.Name = "ThreatWash"
	threat.Size = UDim2.fromScale(1, 1)
	threat.BackgroundTransparency = 1
	threat.BorderSizePixel = 0
	threat.Visible = false
	threat.ZIndex = 1
	threat.Parent = screenGui
	threatOverlay = threat

	local impact = Instance.new("Frame")
	impact.Name = "ImpactFlash"
	impact.Size = UDim2.fromScale(1, 1)
	impact.BackgroundTransparency = 1
	impact.BorderSizePixel = 0
	impact.Visible = false
	impact.ZIndex = 2
	impact.Parent = screenGui
	impactOverlay = impact
end

local function restoreCamera()
	cameraToken += 1
	if cameraTween then
		cameraTween:Cancel()
		cameraTween = nil
	end
	local camera = cameraForEffect
	local baseline = cameraBaseline
	if camera and baseline and camera.Parent ~= nil then
		camera.FieldOfView = baseline
	end
	cameraForEffect = nil
	cameraBaseline = nil
end

local function impulseFieldOfView(offset: number)
	restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	cameraToken += 1
	local token = cameraToken
	local baseline = camera.FieldOfView
	cameraForEffect = camera
	cameraBaseline = baseline
	local outward = TweenService:Create(
		camera,
		TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = math.clamp(baseline + offset, 40, 100) }
	)
	cameraTween = outward
	outward:Play()
	outward.Completed:Once(function()
		if cameraToken ~= token or cameraForEffect ~= camera then
			return
		end
		local inward = TweenService:Create(
			camera,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = baseline }
		)
		cameraTween = inward
		inward:Play()
		inward.Completed:Once(function()
			if cameraToken == token then
				cameraTween = nil
				cameraForEffect = nil
				cameraBaseline = nil
			end
		end)
	end)
end

local function flash(color: Color3, peakTransparency: number, holdSeconds: number)
	ensurePresentation()
	local overlay = impactOverlay
	if not overlay then
		return
	end
	impactToken += 1
	local token = impactToken
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 1
	overlay.Visible = true
	local appear = TweenService:Create(
		overlay,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = peakTransparency }
	)
	appear:Play()
	appear.Completed:Once(function()
		task.delay(holdSeconds, function()
			if impactToken ~= token or not impactOverlay then
				return
			end
			local fade = TweenService:Create(
				impactOverlay,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = 1 }
			)
			fade:Play()
			fade.Completed:Once(function()
				if impactToken == token and impactOverlay then
					impactOverlay.Visible = false
				end
			end)
		end)
	end)
end

local function stopThreat()
	if threatConnection then
		threatConnection:Disconnect()
		threatConnection = nil
	end
	threatModel = nil
	threatFolderName = nil
	threatModelName = nil
	if threatOverlay then
		threatOverlay.Visible = false
		threatOverlay.BackgroundTransparency = 1
	end
end

local function resolveThreatModel(): Model?
	local runtimeRoot = Workspace:FindFirstChild("ODDWORKSRuntime")
	local folder = if runtimeRoot and threatFolderName then runtimeRoot:FindFirstChild(threatFolderName) else nil
	local candidate = if folder and threatModelName then folder:FindFirstChild(threatModelName) else nil
	return if candidate and candidate:IsA("Model") then candidate else nil
end

local function updateThreat(deltaTime: number)
	local overlay = threatOverlay
	if not overlay then
		return
	end
	local model = threatModel
	if not model or model.Parent == nil then
		model = resolveThreatModel()
		threatModel = model
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local wardenRoot = if model then model.PrimaryPart else nil
	local proximity = 0
	if root and root:IsA("BasePart") and wardenRoot then
		local distance = (root.Position - wardenRoot.Position).Magnitude
		proximity = 1 - math.clamp((distance - 6) / 54, 0, 1)
	end
	local stagePressure = math.max(0, threatStage - 1) * 0.022
	local targetTransparency = math.clamp(0.97 - proximity * 0.13 - stagePressure, 0.78, 0.97)
	overlay.BackgroundColor3 = threatColor
	overlay.BackgroundTransparency += (targetTransparency - overlay.BackgroundTransparency) * math.min(deltaTime * 7, 1)
	overlay.Visible = true
end

function RecoveryFeelEffects.Theft(color: Color3)
	stopThreat()
	flash(color, 0.76, 0.04)
	impulseFieldOfView(4)
end

function RecoveryFeelEffects.StartThreat(folderName: string, modelName: string, color: Color3, stage: number)
	ensurePresentation()
	stopThreat()
	threatFolderName = folderName
	threatModelName = modelName
	threatColor = color
	threatStage = math.clamp(math.floor(stage), 1, 3)
	threatConnection = RunService.RenderStepped:Connect(updateThreat)
	flash(color, 0.88, 0.02)
end

function RecoveryFeelEffects.SetThreatStage(stage: number)
	local nextStage = math.clamp(math.floor(stage), 1, 3)
	if nextStage > threatStage then
		flash(threatColor, 0.9, 0.02)
	end
	threatStage = nextStage
end

function RecoveryFeelEffects.Caught()
	stopThreat()
	flash(Color3.fromRGB(255, 61, 44), 0.68, 0.08)
	impulseFieldOfView(-3)
end

function RecoveryFeelEffects.Secured()
	stopThreat()
	flash(Color3.fromRGB(88, 255, 157), 0.78, 0.08)
	impulseFieldOfView(3)
end

function RecoveryFeelEffects.ScrapPulseHit()
	flash(Color3.fromRGB(255, 96, 38), 0.84, 0.04)
	impulseFieldOfView(-1.5)
end

function RecoveryFeelEffects.Revealed(color: Color3, major: boolean)
	flash(color, if major then 0.65 else 0.78, if major then 0.16 else 0.08)
	impulseFieldOfView(if major then 5 else 2.5)
end

function RecoveryFeelEffects.Clear()
	stopThreat()
	impactToken += 1
	if impactOverlay then
		impactOverlay.Visible = false
		impactOverlay.BackgroundTransparency = 1
	end
	restoreCamera()
end

return RecoveryFeelEffects
