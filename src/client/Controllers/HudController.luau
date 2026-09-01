--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type ClientStateSnapshot = {
	Scrap: number,
}

local INITIAL_REQUEST_RETRY_SECONDS = 1.2
local INITIAL_REQUEST_ATTEMPTS = 3

local HudController = {}

-- The client keeps only a display copy. Editing this value or the TextLabel
-- cannot change the authoritative Scrap stored on the server.
local displayScrap = 0
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

-- Creates the intentionally plain Scrap HUD for this technical pass.
-- Later UI can replace this, but the current responsibility is simply showing server state.
local function createScrapLabel(): TextLabel
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = playerGui

	local scrapLabel = Instance.new("TextLabel")
	scrapLabel.Name = "ScrapLabel"
	scrapLabel.AnchorPoint = Vector2.new(0, 0)
	scrapLabel.Position = UDim2.fromOffset(16, 16)
	scrapLabel.Size = UDim2.fromOffset(180, 42)
	scrapLabel.BackgroundColor3 = Color3.fromRGB(18, 24, 28)
	scrapLabel.BackgroundTransparency = 0.1
	scrapLabel.BorderSizePixel = 0
	scrapLabel.Font = Enum.Font.GothamBold
	scrapLabel.Text = "Scrap: ..."
	scrapLabel.TextColor3 = Color3.fromRGB(245, 238, 214)
	scrapLabel.TextSize = 20
	scrapLabel.TextXAlignment = Enum.TextXAlignment.Center
	scrapLabel.Parent = screenGui

	return scrapLabel
end

-- Validates the server snapshot shape before rendering.
-- This protects the UI from bad/mismatched packets, but it does not make the client authoritative.
local function readValidSnapshot(payload: any): ClientStateSnapshot?
	if typeof(payload) ~= "table" then
		return nil
	end

	for key in pairs(payload) do
		if key ~= "Scrap" then
			return nil
		end
	end

	local scrap = payload.Scrap
	if typeof(scrap) ~= "number" then
		return nil
	end

	if scrap ~= scrap or scrap == math.huge or scrap == -math.huge then
		return nil
	end

	if scrap < 0 or math.floor(scrap) ~= scrap then
		return nil
	end

	return {
		Scrap = scrap,
	}
end

-- Renders the latest server-approved display copy into the HUD.
-- The TextLabel is output only; there is no client function that sends Scrap mutations back.
local function renderSnapshot(scrapLabel: TextLabel, snapshot: ClientStateSnapshot)
	displayScrap = snapshot.Scrap
	scrapLabel.Text = string.format("Scrap: %d", displayScrap)
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
	local scrapLabel = createScrapLabel()

	stateSnapshot.OnClientEvent:Connect(function(payload: any)
		local snapshot = readValidSnapshot(payload)
		if not snapshot then
			warn("[ODDWORKS][HudController] Ignored invalid StateSnapshot payload.")
			return
		end

		hasReceivedSnapshot = true
		renderSnapshot(scrapLabel, snapshot)
	end)

	requestInitialState(stateRequest)
end

return HudController
