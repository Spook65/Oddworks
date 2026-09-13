--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type ClientStateSnapshot = {
	Scrap: number,
	Hype: number,
	WorkshopLevel: number,
}

local INITIAL_REQUEST_RETRY_SECONDS = 1.2
local INITIAL_REQUEST_ATTEMPTS = 3

local HudController = {}

-- The client keeps only a display copy. Editing this value or the TextLabel
-- cannot change the authoritative currencies stored on the server.
local displayScrap = 0
local displayHype = 0
local displayWorkshopLevel = 1
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

-- Creates one intentionally plain status label inside the temporary HUD.
-- Shared styling keeps currencies and workshop progression readable without a production UI system.
local function createStatusLabel(
	parent: ScreenGui,
	name: string,
	position: UDim2,
	width: number,
	initialText: string
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = position
	label.Size = UDim2.fromOffset(width, 42)
	label.BackgroundColor3 = Color3.fromRGB(18, 24, 28)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = initialText
	label.TextColor3 = Color3.fromRGB(245, 238, 214)
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

-- Creates the intentionally plain status HUD for this technical pass.
-- Later UI can replace it; this layer only presents sanitized server state.
local function createStatusHud(): (TextLabel, TextLabel, TextLabel, TextLabel)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	local scrapLabel = createStatusLabel(screenGui, "ScrapLabel", UDim2.fromOffset(16, 16), 124, "Scrap: ...")
	local hypeLabel = createStatusLabel(screenGui, "HypeLabel", UDim2.fromOffset(146, 16), 124, "Hype: ...")
	local workshopLevelLabel = createStatusLabel(
		screenGui,
		"WorkshopLevelLabel",
		UDim2.fromOffset(276, 16),
		210,
		"Workshop Level: ..."
	)
	local conejurerRevealLabel = createStatusLabel(
		screenGui,
		"ConejurerRevealLabel",
		UDim2.fromOffset(276, 66),
		210,
		"Conejurer - Coming Soon"
	)
	conejurerRevealLabel.Visible = false

	return scrapLabel, hypeLabel, workshopLevelLabel, conejurerRevealLabel
end

-- Accepts only non-negative integer state values for stable HUD rendering.
-- Client validation handles malformed packets but never grants authority over server state.
local function isValidNonNegativeInteger(value: any): boolean
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
		if key ~= "Scrap" and key ~= "Hype" and key ~= "WorkshopLevel" then
			return nil
		end
	end

	local scrap = payload.Scrap
	local hype = payload.Hype
	local workshopLevel = payload.WorkshopLevel
	if
		not isValidNonNegativeInteger(scrap)
		or not isValidNonNegativeInteger(hype)
		or not isValidNonNegativeInteger(workshopLevel)
		or workshopLevel < 1
	then
		return nil
	end

	return {
		Scrap = scrap,
		Hype = hype,
		WorkshopLevel = workshopLevel,
	}
end

-- Renders the latest server-approved display copy into the HUD.
-- The TextLabels are output only; no client function sends currency mutations back.
local function renderSnapshot(
	scrapLabel: TextLabel,
	hypeLabel: TextLabel,
	workshopLevelLabel: TextLabel,
	conejurerRevealLabel: TextLabel,
	snapshot: ClientStateSnapshot
)
	displayScrap = snapshot.Scrap
	displayHype = snapshot.Hype
	displayWorkshopLevel = snapshot.WorkshopLevel
	scrapLabel.Text = string.format("Scrap: %d", displayScrap)
	hypeLabel.Text = string.format("Hype: %d", displayHype)
	workshopLevelLabel.Text = string.format("Workshop Level: %d", displayWorkshopLevel)
	-- The reveal is derived from server-replicated progression. It is presentation
	-- only; the crafting server independently enforces unlock and availability.
	conejurerRevealLabel.Visible = displayWorkshopLevel >= 2
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
	local scrapLabel, hypeLabel, workshopLevelLabel, conejurerRevealLabel = createStatusHud()

	stateSnapshot.OnClientEvent:Connect(function(payload: any)
		local snapshot = readValidSnapshot(payload)
		if not snapshot then
			warn("[ODDWORKS][HudController] Ignored invalid StateSnapshot payload.")
			return
		end

		hasReceivedSnapshot = true
		renderSnapshot(scrapLabel, hypeLabel, workshopLevelLabel, conejurerRevealLabel, snapshot)
	end)

	requestInitialState(stateRequest)
end

return HudController
