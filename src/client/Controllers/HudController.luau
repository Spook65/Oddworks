--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type ClientStateSnapshot = {
	Scrap: number,
	Hype: number,
}

local INITIAL_REQUEST_RETRY_SECONDS = 1.2
local INITIAL_REQUEST_ATTEMPTS = 3

local HudController = {}

-- The client keeps only a display copy. Editing this value or the TextLabel
-- cannot change the authoritative currencies stored on the server.
local displayScrap = 0
local displayHype = 0
local hasReceivedSnapshot = false
local started = false

-- Finds required network remotes that Rojo places in ReplicatedStorage.
-- ReplicatedStorage is visible to both server and client, but remotes still need server validation.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][HudController] %s.%s must be a %s, but found %s.",
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

-- Creates one intentionally plain currency label inside the temporary HUD.
-- Shared styling keeps Scrap and Hype readable without introducing a production UI system.
local function createCurrencyLabel(parent: ScreenGui, name: string, position: UDim2, initialText: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = position
	label.Size = UDim2.fromOffset(124, 42)
	label.BackgroundColor3 = Color3.fromRGB(18, 24, 28)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = initialText
	label.TextColor3 = Color3.fromRGB(245, 238, 214)
	label.TextSize = 20
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

-- Creates the intentionally plain currency HUD for this technical pass.
-- Later UI can replace it; this layer only presents sanitized server state.
local function createCurrencyHud(): (TextLabel, TextLabel)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	local scrapLabel = createCurrencyLabel(screenGui, "ScrapLabel", UDim2.fromOffset(16, 16), "Scrap: ...")
	local hypeLabel = createCurrencyLabel(screenGui, "HypeLabel", UDim2.fromOffset(146, 16), "Hype: ...")

	return scrapLabel, hypeLabel
end

-- Accepts only non-negative integer currency values for stable HUD rendering.
-- Client validation handles malformed packets but never grants authority over server state.
local function isValidCurrency(value: any): boolean
	if typeof(value) ~= "number" then
		return false
	end

	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end

	return value >= 0 and math.floor(value) == value
end

-- Validates the server snapshot shape before rendering.
-- This protects the UI from bad/mismatched packets, but it does not make the client authoritative.
local function readValidSnapshot(payload: any): ClientStateSnapshot?
	if typeof(payload) ~= "table" then
		return nil
	end

	for key in pairs(payload) do
		if key ~= "Scrap" and key ~= "Hype" then
			return nil
		end
	end

	local scrap = payload.Scrap
	local hype = payload.Hype
	if not isValidCurrency(scrap) or not isValidCurrency(hype) then
		return nil
	end

	return {
		Scrap = scrap,
		Hype = hype,
	}
end

-- Renders the latest server-approved display copy into the HUD.
-- The TextLabels are output only; no client function sends currency mutations back.
local function renderSnapshot(scrapLabel: TextLabel, hypeLabel: TextLabel, snapshot: ClientStateSnapshot)
	displayScrap = snapshot.Scrap
	displayHype = snapshot.Hype
	scrapLabel.Text = string.format("Scrap: %d", displayScrap)
	hypeLabel.Text = string.format("Hype: %d", displayHype)
end

-- Requests the initial snapshot after OnClientEvent is already connected.
-- The small retry covers startup timing without turning refresh into an unlimited spam loop.
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

-- Starts the minimal HUD and state listener once.
-- Listener-before-request ordering avoids losing the first server snapshot.
function HudController.Start()
	if started then
		return
	end

	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local stateRequest = requireChildOfClass(networkFolder, "StateRequest", "RemoteEvent") :: RemoteEvent
	local stateSnapshot = requireChildOfClass(networkFolder, "StateSnapshot", "RemoteEvent") :: RemoteEvent
	local scrapLabel, hypeLabel = createCurrencyHud()

	stateSnapshot.OnClientEvent:Connect(function(payload: any)
		local snapshot = readValidSnapshot(payload)
		if not snapshot then
			warn("[ODDWORKS][HudController] Ignored invalid StateSnapshot payload.")
			return
		end

		hasReceivedSnapshot = true
		renderSnapshot(scrapLabel, hypeLabel, snapshot)
	end)

	requestInitialState(stateRequest)
end

return HudController
