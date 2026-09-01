--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type CraftResultCode =
	"CRAFT_SUCCESS"
	| "NOT_ENOUGH_SCRAP"
	| "RECIPE_LOCKED"
	| "INVALID_RECIPE"
	| "RATE_LIMITED"
	| "CRAFT_FAILED"

local TOASTMARSHAL_RECIPE_ID = "Toastmarshal"

local RESULT_MESSAGES: { [string]: string } = {
	CRAFT_SUCCESS = "Crafted Toastmarshal.",
	NOT_ENOUGH_SCRAP = "Need 5 Scrap.",
	RECIPE_LOCKED = "Recipe locked.",
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

-- Creates the small temporary crafting button and result label.
-- The displayed "5 Scrap" is presentation; the server recipe config is the real price.
local function createCraftingUi(): (TextButton, TextLabel)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = requireChildOfClass(playerGui, "ODDWORKSHud", "ScreenGui")

	local craftButton = Instance.new("TextButton")
	craftButton.Name = "CraftToastmarshalButton"
	craftButton.Position = UDim2.fromOffset(16, 66)
	craftButton.Size = UDim2.fromOffset(250, 42)
	craftButton.BackgroundColor3 = Color3.fromRGB(62, 88, 98)
	craftButton.BorderSizePixel = 0
	craftButton.Font = Enum.Font.GothamBold
	craftButton.Text = "Craft Toastmarshal - 5 Scrap"
	craftButton.TextColor3 = Color3.fromRGB(250, 246, 232)
	craftButton.TextSize = 18
	craftButton.Parent = hud

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "CraftResultLabel"
	resultLabel.Position = UDim2.fromOffset(16, 112)
	resultLabel.Size = UDim2.fromOffset(250, 30)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.Gotham
	resultLabel.Text = ""
	resultLabel.TextColor3 = Color3.fromRGB(250, 246, 232)
	resultLabel.TextSize = 16
	resultLabel.TextXAlignment = Enum.TextXAlignment.Left
	resultLabel.Parent = hud

	return craftButton, resultLabel
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
	local craftButton, resultLabel = createCraftingUi()

	craftButton.Activated:Connect(function()
		craftRequest:FireServer(TOASTMARSHAL_RECIPE_ID)
	end)

	craftResult.OnClientEvent:Connect(function(resultCode: any)
		renderCraftResult(resultLabel, resultCode)
	end)
end

return CraftingController
