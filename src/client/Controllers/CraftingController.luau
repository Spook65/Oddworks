--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudController = require(script.Parent:WaitForChild("HudController"))

type CraftResultCode =
	"CRAFT_SUCCESS"
	| "NOT_ENOUGH_SCRAP"
	| "RECIPE_LOCKED"
	| "RECIPE_NOT_AVAILABLE"
	| "INVALID_RECIPE"
	| "RATE_LIMITED"
	| "CRAFT_FAILED"

local TOASTMARSHAL_RECIPE_ID = "Toastmarshal"
local CONEJURER_RECIPE_ID = "Conejurer"
local CONEJURER_REQUIRED_WORKSHOP_LEVEL = 2

local RESULT_MESSAGES: { [string]: string } = {
	CRAFT_SUCCESS = "Craft succeeded.",
	NOT_ENOUGH_SCRAP = "Not enough Scrap.",
	RECIPE_LOCKED = "Recipe locked.",
	RECIPE_NOT_AVAILABLE = "Recipe unavailable.",
	INVALID_RECIPE = "Invalid recipe.",
	RATE_LIMITED = "Slow down.",
	CRAFT_FAILED = "Craft failed.",
}

local CraftingController = {}

local started = false

-- Finds required replicated objects for this temporary crafting UI.
-- The remote is narrow: the client sends only a recipe ID, never a price or output.
local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][CraftingController] %s.%s must be a %s, but found %s.",
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

-- Creates one temporary crafting button. Its displayed price is presentation;
-- the server recipe configuration remains the only authoritative price.
local function createCraftButton(
	parent: ScreenGui,
	name: string,
	position: UDim2,
	text: string
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = UDim2.fromOffset(250, 42)
	button.BackgroundColor3 = Color3.fromRGB(62, 88, 98)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(250, 246, 232)
	button.TextSize = 18
	button.Parent = parent
	return button
end

-- Creates two temporary recipe buttons and one shared result label.
-- Their displayed prices aid presentation only; server Recipes decides every real cost and output.
local function createCraftingUi(): (TextButton, TextButton, TextLabel)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = requireChildOfClass(playerGui, "ODDWORKSHud", "ScreenGui")

	local toastmarshalButton = createCraftButton(
		hud,
		"CraftToastmarshalButton",
		UDim2.fromOffset(16, 66),
		"Craft Toastmarshal - 5 Scrap"
	)
	local conejurerButton = createCraftButton(
		hud,
		"CraftConejurerButton",
		UDim2.fromOffset(276, 66),
		"Craft Conejurer - 8 Scrap"
	)
	conejurerButton.Visible = false

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "CraftResultLabel"
	resultLabel.Position = UDim2.fromOffset(16, 112)
	resultLabel.Size = UDim2.fromOffset(510, 30)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.Gotham
	resultLabel.Text = ""
	resultLabel.TextColor3 = Color3.fromRGB(250, 246, 232)
	resultLabel.TextSize = 16
	resultLabel.TextXAlignment = Enum.TextXAlignment.Left
	resultLabel.Parent = hud

	return toastmarshalButton, conejurerButton, resultLabel
end

-- Converts a server-generated result code into local display text.
-- Unknown payloads are ignored so malformed packets cannot break the UI.
local function renderCraftResult(resultLabel: TextLabel, resultCode: any)
	if typeof(resultCode) ~= "string" then
		return
	end

	local message = RESULT_MESSAGES[resultCode]
	if not message then
		return
	end

	resultLabel.Text = message
end

-- Starts the temporary client crafting controls once.
-- Button clicks request crafting; only the server can decide whether it succeeds.
function CraftingController.Start()
	if started then
		return
	end

	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	local craftRequest = requireChildOfClass(networkFolder, "CraftRequest", "RemoteEvent") :: RemoteEvent
	local craftResult = requireChildOfClass(networkFolder, "CraftResult", "RemoteEvent") :: RemoteEvent
	local toastmarshalButton, conejurerButton, resultLabel = createCraftingUi()

	toastmarshalButton.Activated:Connect(function()
		craftRequest:FireServer(TOASTMARSHAL_RECIPE_ID)
	end)
	conejurerButton.Activated:Connect(function()
		craftRequest:FireServer(CONEJURER_RECIPE_ID)
	end)

	HudController.ObserveWorkshopLevelChanged(function(workshopLevel: number)
		-- Visibility is convenience only. Showing this button locally at Level 1
		-- cannot bypass the server-owned unlock and level requirement.
		conejurerButton.Visible = workshopLevel >= CONEJURER_REQUIRED_WORKSHOP_LEVEL
	end)

	craftResult.OnClientEvent:Connect(function(resultCode: any)
		renderCraftResult(resultLabel, resultCode)
	end)
end

return CraftingController
