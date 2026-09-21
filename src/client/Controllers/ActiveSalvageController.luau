--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

type UnbankedEntry = {
	ComponentId: string,
	DisplayName: string,
	Rarity: string,
	Count: number,
}

type StagePresentation = {
	EncounterId: string,
	Stage: number,
	StageCount: number,
	StageStartedAt: number,
	WindowStartAt: number,
	WindowEndAt: number,
	StageEndsAt: number,
}

local ActiveSalvageController = {}

local INITIAL_REQUEST_RETRY_SECONDS = 1.2
local INITIAL_REQUEST_ATTEMPTS = 5
local LOCAL_INPUT_INTERVAL_SECONDS = 0.15
local MAX_UNBANKED_ENTRIES = 54

local extractionInputRequest: RemoteEvent? = nil
local currentStage: StagePresentation? = nil
local hasReceivedSnapshot = false
local lastLocalInputTime = 0
local panelToken = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][ActiveSalvageController] %s.%s must be a %s, but found %s.",
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

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isBoundedString(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

local function isPositiveInteger(value: any): boolean
	return isFiniteNumber(value) and value > 0 and math.floor(value) == value
end

local function isValidRarity(value: any): boolean
	return value == "Common" or value == "Rare" or value == "Legendary"
end

-- Client validation protects this temporary UI from malformed packets. It does
-- not make the display copy authoritative or create any inventory mutation path.
local function readUnbankedSnapshot(payload: any): { UnbankedEntry }?
	if typeof(payload) ~= "table" or typeof(payload.UnbankedComponents) ~= "table" then
		return nil
	end
	for key in pairs(payload) do
		if key ~= "UnbankedComponents" then
			return nil
		end
	end

	local source = payload.UnbankedComponents
	if #source > MAX_UNBANKED_ENTRIES then
		return nil
	end

	local entries: { UnbankedEntry } = {}
	for index, entry in ipairs(source) do
		if index > MAX_UNBANKED_ENTRIES
			or typeof(entry) ~= "table"
			or not isBoundedString(entry.ComponentId, 48)
			or not isBoundedString(entry.DisplayName, 64)
			or not isValidRarity(entry.Rarity)
			or not isPositiveInteger(entry.Count)
			or entry.Count > 999
		then
			return nil
		end

		table.insert(entries, {
			ComponentId = entry.ComponentId,
			DisplayName = entry.DisplayName,
			Rarity = entry.Rarity,
			Count = entry.Count,
		})
	end
	return entries
end

local function readStage(payload: any): StagePresentation?
	if typeof(payload) ~= "table"
		or payload.Kind ~= "STAGE"
		or not isBoundedString(payload.EncounterId, 40)
		or not isPositiveInteger(payload.Stage)
		or not isPositiveInteger(payload.StageCount)
		or payload.Stage > payload.StageCount
		or not isFiniteNumber(payload.StageStartedAt)
		or not isFiniteNumber(payload.WindowStartAt)
		or not isFiniteNumber(payload.WindowEndAt)
		or not isFiniteNumber(payload.StageEndsAt)
		or payload.StageStartedAt >= payload.WindowStartAt
		or payload.WindowStartAt >= payload.WindowEndAt
		or payload.WindowEndAt >= payload.StageEndsAt
	then
		return nil
	end

	return {
		EncounterId = payload.EncounterId,
		Stage = payload.Stage,
		StageCount = payload.StageCount,
		StageStartedAt = payload.StageStartedAt,
		WindowStartAt = payload.WindowStartAt,
		WindowEndAt = payload.WindowEndAt,
		StageEndsAt = payload.StageEndsAt,
	}
end

local function createPrototypeUi(): (TextLabel, Frame, TextLabel, Frame, Frame, TextButton)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSActiveSalvageGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 5
	screenGui.Parent = playerGui

	local haulLabel = Instance.new("TextLabel")
	haulLabel.Name = "UnbankedHaulLabel"
	haulLabel.AnchorPoint = Vector2.new(1, 0)
	haulLabel.Position = UDim2.new(1, -16, 0, 16)
	haulLabel.Size = UDim2.fromOffset(320, 250)
	haulLabel.BackgroundColor3 = Color3.fromRGB(29, 32, 30)
	haulLabel.BackgroundTransparency = 0.08
	haulLabel.BorderSizePixel = 0
	haulLabel.Font = Enum.Font.Gotham
	haulLabel.Text = "UNBANKED HAUL\nLoading..."
	haulLabel.TextColor3 = Color3.fromRGB(245, 238, 214)
	haulLabel.TextSize = 16
	haulLabel.TextWrapped = true
	haulLabel.TextXAlignment = Enum.TextXAlignment.Left
	haulLabel.TextYAlignment = Enum.TextYAlignment.Top
	haulLabel.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "ExtractionPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -28)
	panel.Size = UDim2.fromOffset(430, 150)
	panel.BackgroundColor3 = Color3.fromRGB(24, 29, 31)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Position = UDim2.fromOffset(20, 12)
	statusLabel.Size = UDim2.fromOffset(390, 34)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(248, 241, 218)
	statusLabel.TextSize = 18
	statusLabel.Parent = panel

	local timingTrack = Instance.new("Frame")
	timingTrack.Name = "TimingTrack"
	timingTrack.Position = UDim2.fromOffset(35, 54)
	timingTrack.Size = UDim2.fromOffset(360, 22)
	timingTrack.BackgroundColor3 = Color3.fromRGB(67, 72, 74)
	timingTrack.BorderSizePixel = 0
	timingTrack.ClipsDescendants = true
	timingTrack.Parent = panel

	local successWindow = Instance.new("Frame")
	successWindow.Name = "SuccessWindow"
	successWindow.BackgroundColor3 = Color3.fromRGB(83, 188, 115)
	successWindow.BorderSizePixel = 0
	successWindow.Parent = timingTrack

	local indicator = Instance.new("Frame")
	indicator.Name = "TimingIndicator"
	indicator.AnchorPoint = Vector2.new(0.5, 0)
	indicator.Size = UDim2.new(0, 5, 1, 0)
	indicator.BackgroundColor3 = Color3.fromRGB(255, 224, 91)
	indicator.BorderSizePixel = 0
	indicator.Parent = timingTrack

	local pullButton = Instance.new("TextButton")
	pullButton.Name = "PullButton"
	pullButton.AnchorPoint = Vector2.new(0.5, 0)
	pullButton.Position = UDim2.new(0.5, 0, 0, 89)
	pullButton.Size = UDim2.fromOffset(210, 42)
	pullButton.BackgroundColor3 = Color3.fromRGB(177, 80, 55)
	pullButton.BorderSizePixel = 0
	pullButton.Font = Enum.Font.GothamBold
	pullButton.Text = "PULL  [F]"
	pullButton.TextColor3 = Color3.fromRGB(255, 247, 225)
	pullButton.TextSize = 18
	pullButton.Parent = panel

	return haulLabel, panel, statusLabel, successWindow, indicator, pullButton
end

local function renderUnbanked(haulLabel: TextLabel, entries: { UnbankedEntry })
	local lines = { "UNBANKED HAUL" }
	if #entries == 0 then
		table.insert(lines, "Empty")
	else
		local visibleCount = math.min(#entries, 11)
		for index = 1, visibleCount do
			local entry = entries[index]
			table.insert(lines, string.format("%s [%s] x%d", entry.DisplayName, entry.Rarity, entry.Count))
		end
		if #entries > visibleCount then
			table.insert(lines, string.format("...and %d more", #entries - visibleCount))
		end
	end
	haulLabel.Text = table.concat(lines, "\n")
end

local function showTemporaryMessage(panel: Frame, statusLabel: TextLabel, message: string, seconds: number)
	panelToken += 1
	local token = panelToken
	currentStage = nil
	panel.Visible = true
	statusLabel.Text = message
	task.delay(seconds, function()
		if panelToken == token and not currentStage then
			panel.Visible = false
		end
	end)
end

local function sendExtractionInput()
	local stage = currentStage
	local remote = extractionInputRequest
	if not stage or not remote then
		return
	end

	local now = os.clock()
	if now - lastLocalInputTime < LOCAL_INPUT_INTERVAL_SECONDS then
		return
	end
	lastLocalInputTime = now
	-- No timestamp, success flag, stage, rarity, or reward crosses this boundary.
	remote:FireServer(stage.EncounterId)
end

local function requestInitialState(stateRequest: RemoteEvent)
	task.spawn(function()
		for _ = 1, INITIAL_REQUEST_ATTEMPTS do
			if hasReceivedSnapshot then
				return
			end
			stateRequest:FireServer()
			task.wait(INITIAL_REQUEST_RETRY_SECONDS)
		end
	end)
end

function ActiveSalvageController.Start()
	if started then
		return
	end
	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local modularStateRequest = requireChildOfClass(networkFolder, "ModularStateRequest", "RemoteEvent") :: RemoteEvent
	local modularStateSnapshot = requireChildOfClass(networkFolder, "ModularStateSnapshot", "RemoteEvent") :: RemoteEvent
	extractionInputRequest = requireChildOfClass(networkFolder, "ExtractionInputRequest", "RemoteEvent") :: RemoteEvent
	local activeState = requireChildOfClass(networkFolder, "ActiveSalvageState", "RemoteEvent") :: RemoteEvent
	local haulLabel, panel, statusLabel, successWindow, indicator, pullButton = createPrototypeUi()

	modularStateSnapshot.OnClientEvent:Connect(function(payload: any)
		local entries = readUnbankedSnapshot(payload)
		if not entries then
			warn("[ODDWORKS][ActiveSalvageController] Ignored invalid ModularStateSnapshot payload.")
			return
		end
		renderUnbanked(haulLabel, entries)
		hasReceivedSnapshot = true
	end)

	activeState.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or not isBoundedString(payload.Kind, 32) then
			return
		end

		if payload.Kind == "STAGE" then
			local stage = readStage(payload)
			if not stage then
				return
			end

			panelToken += 1
			currentStage = stage
			panel.Visible = true
			statusLabel.Text = string.format("EXTRACTION  %d / %d", stage.Stage, stage.StageCount)
			local duration = stage.StageEndsAt - stage.StageStartedAt
			local windowStartScale = (stage.WindowStartAt - stage.StageStartedAt) / duration
			local windowSizeScale = (stage.WindowEndAt - stage.WindowStartAt) / duration
			successWindow.Position = UDim2.fromScale(windowStartScale, 0)
			successWindow.Size = UDim2.fromScale(windowSizeScale, 1)
			indicator.Position = UDim2.fromScale(0, 0)
		elseif payload.Kind == "STAGE_SUCCESS" then
			currentStage = nil
			statusLabel.Text = "PULL LOCKED"
		elseif payload.Kind == "FAILED" then
			local failureMessages: { [string]: string } = {
				TOO_EARLY = "Too early - wreck reset",
				TOO_LATE = "Too late - wreck reset",
				MISSED_WINDOW = "Missed pull - wreck reset",
				OUT_OF_RANGE = "Extraction cancelled - too far away",
				UNBANKED_CAP_REACHED = "Unbanked component bucket is full",
			}
			local message = if typeof(payload.Code) == "string" then failureMessages[payload.Code] else nil
			showTemporaryMessage(panel, statusLabel, message or "Extraction failed - retry shortly", 2)
		elseif payload.Kind == "COMPLETED" then
			local reward = payload.Reward
			if typeof(reward) ~= "table"
				or not isBoundedString(reward.DisplayName, 64)
				or not isValidRarity(reward.Rarity)
				or not isPositiveInteger(reward.Quantity)
			then
				return
			end
			showTemporaryMessage(
				panel,
				statusLabel,
				string.format("EXTRACTED: %s [%s] x%d", reward.DisplayName, reward.Rarity, reward.Quantity),
				3
			)
		elseif payload.Kind == "BUSY" then
			showTemporaryMessage(panel, statusLabel, "Wreck is being extracted by another player", 1.5)
		end
	end)

	pullButton.Activated:Connect(sendExtractionInput)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- F avoids competing with Roblox's normal Space-to-jump control. The
		-- on-screen button remains available for pointer and touch input.
		if not gameProcessed and input.KeyCode == Enum.KeyCode.F then
			sendExtractionInput()
		end
	end)

	-- GetServerTimeNow is shared only for visual alignment. The server independently
	-- evaluates its own clock when deciding whether the pull succeeds.
	RunService.RenderStepped:Connect(function()
		local stage = currentStage
		if not stage then
			return
		end
		local progress = math.clamp(
			(Workspace:GetServerTimeNow() - stage.StageStartedAt) / (stage.StageEndsAt - stage.StageStartedAt),
			0,
			1
		)
		indicator.Position = UDim2.fromScale(progress, 0)
	end)

	-- Both listeners are connected before the client asks for its initial display copy.
	requestInitialState(modularStateRequest)
end

return ActiveSalvageController
