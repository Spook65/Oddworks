--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

type IndexEntry = {
	Discovered: boolean,
	IndexNumber: number,
	SpeciesId: string?,
	DisplayName: string?,
	Classification: string?,
	FlavorText: string?,
	OwnedCount: number?,
	DisplayedCount: number?,
	CollectionCount: number?,
	HypePerInterval: number?,
	HypeIntervalSeconds: number?,
	RecoverySource: string?,
	SecurityTier: string?,
	AccentColor: Color3?,
}

type IndexSnapshot = {
	IndexSpecies: { IndexEntry },
	PublicDiscoveredCount: number,
	PublicSpeciesCount: number,
}

local OddlingIndexController = {}

local MAX_SPECIES = 16
local MAX_TEXT_LENGTH = 96
local MAX_FLAVOR_LENGTH = 240
local SMALL_SCREEN_WIDTH = 700
local NEW_ENTRY_DELAY_SECONDS = 3.2

local requestRemote: RemoteEvent? = nil
local latestSnapshot: IndexSnapshot? = nil
local notification: TextLabel? = nil
local browserPane: Frame? = nil
local detailPane: ScrollingFrame? = nil
local gridContent: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local completionLabel: TextLabel? = nil
local backButton: TextButton? = nil
local previewFrame: ViewportFrame? = nil
local previewWorld: WorldModel? = nil
local previewCamera: Camera? = nil
local unknownPreview: TextLabel? = nil
local detailNumber: TextLabel? = nil
local detailName: TextLabel? = nil
local detailClassification: TextLabel? = nil
local detailFlavor: TextLabel? = nil
local detailProduction: TextLabel? = nil
local detailCounts: TextLabel? = nil
local detailSecurity: TextLabel? = nil
local detailSource: TextLabel? = nil
local detailRail: Frame? = nil
local selectedEntry: IndexEntry? = nil
local tileButtons: { TextButton } = {}
local showingSmallDetail = false
local notificationGeneration = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][OddlingIndex] %s.%s must be a %s, but found %s.",
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

local function isIntegerInRange(value: any, minimum: number, maximum: number): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value % 1 == 0
		and value >= minimum
		and value <= maximum
end

local function isFiniteNonnegativeNumber(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
end

local function isShortText(value: any, maximum: number?): boolean
	return typeof(value) == "string" and #value > 0 and #value <= (maximum or MAX_TEXT_LENGTH)
end

local function readSnapshot(payload: any): IndexSnapshot?
	if typeof(payload) ~= "table"
		or typeof(payload.IndexSpecies) ~= "table"
		or #payload.IndexSpecies > MAX_SPECIES
		or not isIntegerInRange(payload.PublicDiscoveredCount, 0, MAX_SPECIES)
		or not isIntegerInRange(payload.PublicSpeciesCount, 0, MAX_SPECIES)
		or payload.PublicDiscoveredCount > payload.PublicSpeciesCount
	then
		return nil
	end

	local entries: { IndexEntry } = {}
	local knownSpecies: { [string]: boolean } = {}
	local knownNumbers: { [number]: boolean } = {}
	for _, entry in ipairs(payload.IndexSpecies) do
		if typeof(entry) ~= "table"
			or typeof(entry.Discovered) ~= "boolean"
			or not isIntegerInRange(entry.IndexNumber, 1, 9999)
			or knownNumbers[entry.IndexNumber]
		then
			return nil
		end
		knownNumbers[entry.IndexNumber] = true
		if not entry.Discovered then
			table.insert(entries, {
				Discovered = false,
				IndexNumber = entry.IndexNumber,
			})
			continue
		end
		if not isShortText(entry.SpeciesId)
			or knownSpecies[entry.SpeciesId]
			or not isShortText(entry.DisplayName)
			or not isShortText(entry.Classification)
			or not isShortText(entry.FlavorText, MAX_FLAVOR_LENGTH)
			or not isIntegerInRange(entry.OwnedCount, 1, 1000000)
			or not isIntegerInRange(entry.DisplayedCount, 0, 100)
			or not isIntegerInRange(entry.CollectionCount, 0, 1000000)
			or entry.DisplayedCount + entry.CollectionCount ~= entry.OwnedCount
			or not isFiniteNonnegativeNumber(entry.HypePerInterval)
			or not isFiniteNonnegativeNumber(entry.HypeIntervalSeconds)
			or entry.HypeIntervalSeconds <= 0
			or not isShortText(entry.RecoverySource)
			or not isShortText(entry.SecurityTier)
			or typeof(entry.AccentColor) ~= "Color3"
		then
			return nil
		end
		knownSpecies[entry.SpeciesId] = true
		table.insert(entries, {
			Discovered = true,
			IndexNumber = entry.IndexNumber,
			SpeciesId = entry.SpeciesId,
			DisplayName = entry.DisplayName,
			Classification = entry.Classification,
			FlavorText = entry.FlavorText,
			OwnedCount = entry.OwnedCount,
			DisplayedCount = entry.DisplayedCount,
			CollectionCount = entry.CollectionCount,
			HypePerInterval = entry.HypePerInterval,
			HypeIntervalSeconds = entry.HypeIntervalSeconds,
			RecoverySource = entry.RecoverySource,
			SecurityTier = entry.SecurityTier,
			AccentColor = entry.AccentColor,
		})
	end

	return {
		IndexSpecies = entries,
		PublicDiscoveredCount = payload.PublicDiscoveredCount,
		PublicSpeciesCount = payload.PublicSpeciesCount,
	}
end

local function makeLabel(parent: Instance, name: string, text: string, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(222, 228, 221)
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, name: string, text: string, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(52, 72, 69)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Selectable = true
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 241, 235)
	button.TextSize = 13
	button.Parent = parent
	return button
end

local function formatIndexNumber(indexNumber: number): string
	return string.format("#%03d", indexNumber)
end

local function clearPreview()
	local world = previewWorld
	if world then
		for _, child in ipairs(world:GetChildren()) do
			child:Destroy()
		end
	end
end

local function renderPreview(speciesId: string, accent: Color3): boolean
	local frame = previewFrame
	local world = previewWorld
	local camera = previewCamera
	if not frame or not world or not camera then
		return false
	end
	clearPreview()
	local presentation = ReplicatedStorage:FindFirstChild("ODDWORKSPresentation")
	local previews = if presentation then presentation:FindFirstChild("OddlingPreviews") else nil
	local template = if previews then previews:FindFirstChild(speciesId) else nil
	if not template or not template:IsA("Model") then
		return false
	end

	local model = template:Clone()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript")
			or descendant:IsA("ProximityPrompt") or descendant:IsA("ClickDetector")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	model.Parent = world
	local boundingCFrame, boundingSize = model:GetBoundingBox()
	model:PivotTo(boundingCFrame:Inverse() * model:GetPivot())
	local largest = math.max(boundingSize.X, boundingSize.Y, boundingSize.Z)
	local distance = math.max(6, largest * 1.65)
	camera.CFrame = CFrame.lookAt(
		Vector3.new(largest * 0.12, boundingSize.Y * 0.08, -distance),
		Vector3.new(0, 0, 0)
	)
	frame.Ambient = accent:Lerp(Color3.new(1, 1, 1), 0.48)
	frame.LightColor = Color3.fromRGB(255, 238, 214)
	frame.LightDirection = Vector3.new(-1, -1, -1)
	return true
end

local function setDetailText(label: TextLabel?, text: string, visible: boolean?)
	if label then
		label.Text = text
		label.Visible = visible ~= false
	end
end

local function renderDetail(entry: IndexEntry)
	selectedEntry = entry
	local accent = entry.AccentColor or Color3.fromRGB(105, 114, 111)
	if detailRail then
		detailRail.BackgroundColor3 = accent
	end
	setDetailText(detailNumber, formatIndexNumber(entry.IndexNumber))
	if not entry.Discovered then
		setDetailText(detailName, "???")
		setDetailText(detailClassification, "UNDISCOVERED")
		setDetailText(detailFlavor, "Recover this Oddling to unlock its Index record.")
		setDetailText(detailProduction, "", false)
		setDetailText(detailCounts, "", false)
		setDetailText(detailSecurity, "", false)
		setDetailText(detailSource, "", false)
		clearPreview()
		if previewFrame then
			previewFrame.BackgroundColor3 = Color3.fromRGB(26, 30, 30)
		end
		if unknownPreview then
			unknownPreview.Text = "UNDISCOVERED"
			unknownPreview.Visible = true
		end
	else
		local displayName = entry.DisplayName :: string
		setDetailText(detailName, string.upper(displayName))
		setDetailText(detailClassification, entry.Classification :: string)
		setDetailText(detailFlavor, entry.FlavorText :: string)
		setDetailText(
			detailProduction,
			string.format(
				"PRODUCTION\n+%g Hype / %gs per displayed %s",
				entry.HypePerInterval :: number,
				entry.HypeIntervalSeconds :: number,
				displayName
			)
		)
		setDetailText(
			detailCounts,
			string.format(
				"OWNED  %d     DISPLAYED  %d\nIN COLLECTION  %d",
				entry.OwnedCount :: number,
				entry.DisplayedCount :: number,
				entry.CollectionCount :: number
			)
		)
		setDetailText(detailSecurity, "SECURITY\n" .. (entry.SecurityTier :: string))
		setDetailText(detailSource, "RECOVERED FROM\n" .. (entry.RecoverySource :: string))
		if previewFrame then
			previewFrame.BackgroundColor3 = Color3.fromRGB(28, 33, 33):Lerp(accent, 0.08)
		end
		if unknownPreview then
			unknownPreview.Text = "PREVIEW UNAVAILABLE"
			unknownPreview.Visible = not renderPreview(entry.SpeciesId :: string, accent)
		end
	end

	for _, button in ipairs(tileButtons) do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if button:GetAttribute("IndexNumber") == entry.IndexNumber then 2 else 1
			stroke.Transparency = if button:GetAttribute("IndexNumber") == entry.IndexNumber then 0 else 0.65
		end
	end
end

local function isSmallScreen(): boolean
	local camera = Workspace.CurrentCamera
	return not camera or camera.ViewportSize.X < SMALL_SCREEN_WIDTH
end

local function updateResponsiveLayout()
	local browser = browserPane
	local detail = detailPane
	local back = backButton
	local layout = gridLayout
	if not browser or not detail or not back or not layout then
		return
	end
	if isSmallScreen() then
		browser.Position = UDim2.fromOffset(14, 70)
		browser.Size = UDim2.new(1, -28, 1, -84)
		detail.Position = UDim2.fromOffset(14, 78)
		detail.Size = UDim2.new(1, -28, 1, -92)
		browser.Visible = not showingSmallDetail
		detail.Visible = showingSmallDetail
		back.Visible = showingSmallDetail
		if completionLabel then
			completionLabel.Position = UDim2.new(1, -62, 0, 42)
			completionLabel.Visible = not showingSmallDetail
		end
		layout.CellSize = UDim2.new(0.5, -5, 0, 118)
	else
		browser.Position = UDim2.fromOffset(14, 70)
		browser.Size = UDim2.new(0.37, -19, 1, -84)
		detail.Position = UDim2.new(0.37, 3, 0, 70)
		detail.Size = UDim2.new(0.63, -17, 1, -84)
		browser.Visible = true
		detail.Visible = true
		back.Visible = false
		if completionLabel then
			completionLabel.Position = UDim2.new(1, -62, 0, 13)
			completionLabel.Visible = true
		end
		layout.CellSize = UDim2.new(0.5, -5, 0, 118)
	end
end

local function makeSpeciesTile(parent: Instance, entry: IndexEntry, layoutOrder: number): TextButton
	local accent = entry.AccentColor or Color3.fromRGB(93, 103, 100)
	local button = makeButton(parent, "SpeciesTile", "", UDim2.fromOffset(140, 118))
	button.LayoutOrder = layoutOrder
	button.BackgroundColor3 = Color3.fromRGB(35, 40, 40)
	button:SetAttribute("IndexNumber", entry.IndexNumber)

	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 1
	stroke.Transparency = 0.65
	stroke.Parent = button

	local icon = Instance.new("Frame")
	icon.Name = "SpeciesIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 13)
	icon.Size = UDim2.fromOffset(42, 42)
	icon.Rotation = 45
	icon.BackgroundColor3 = accent
	icon.BackgroundTransparency = if entry.Discovered then 0.12 else 0.72
	icon.BorderSizePixel = 0
	icon.Parent = button

	local core = Instance.new("Frame")
	core.Name = "IconCore"
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromOffset(17, 17)
	core.BackgroundColor3 = if entry.Discovered then Color3.fromRGB(230, 241, 235) else Color3.fromRGB(58, 63, 62)
	core.BorderSizePixel = 0
	core.Parent = icon
	if entry.Discovered and entry.SpeciesId == "Voltlet" then
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = core
		local charge = Instance.new("Frame")
		charge.Name = "ChargeNode"
		charge.AnchorPoint = Vector2.new(0.5, 0.5)
		charge.Position = UDim2.fromScale(0.78, 0.22)
		charge.Size = UDim2.fromOffset(8, 8)
		charge.BackgroundColor3 = Color3.fromRGB(222, 253, 255)
		charge.BorderSizePixel = 0
		charge.Parent = icon
		local chargeRound = Instance.new("UICorner")
		chargeRound.CornerRadius = UDim.new(1, 0)
		chargeRound.Parent = charge
	elseif entry.Discovered and entry.SpeciesId == "Kilnback" then
		core.Size = UDim2.fromOffset(22, 19)
		local chimney = Instance.new("Frame")
		chimney.Name = "Chimney"
		chimney.AnchorPoint = Vector2.new(0.5, 1)
		chimney.Position = UDim2.fromScale(0.7, 0.34)
		chimney.Size = UDim2.fromOffset(7, 13)
		chimney.BackgroundColor3 = Color3.fromRGB(230, 241, 235)
		chimney.BorderSizePixel = 0
		chimney.Parent = icon
	end

	local number = makeLabel(button, "IndexNumber", formatIndexNumber(entry.IndexNumber), UDim2.new(1, -12, 0, 18))
	number.Position = UDim2.fromOffset(6, 2)
	number.TextColor3 = Color3.fromRGB(139, 151, 146)
	number.TextSize = 10

	local name = makeLabel(
		button,
		"SpeciesName",
		if entry.Discovered then string.upper(entry.DisplayName :: string) else "???",
		UDim2.new(1, -12, 0, 24)
	)
	name.Position = UDim2.fromOffset(6, 68)
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = if entry.Discovered then Color3.fromRGB(233, 239, 234) else Color3.fromRGB(126, 135, 132)
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Center

	local status = makeLabel(
		button,
		"DiscoveryState",
		if entry.Discovered then "RECORDED" else "UNDISCOVERED",
		UDim2.new(1, -12, 0, 18)
	)
	status.Position = UDim2.fromOffset(6, 92)
	status.TextColor3 = accent
	status.TextSize = 9
	status.TextXAlignment = Enum.TextXAlignment.Center

	button.Activated:Connect(function()
		renderDetail(entry)
		if isSmallScreen() then
			showingSmallDetail = true
			updateResponsiveLayout()
		end
	end)
	return button
end

local function clearGrid()
	local grid = gridContent
	if not grid then
		return
	end
	for _, child in ipairs(grid:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(tileButtons)
end

local function renderSnapshot(snapshot: IndexSnapshot)
	latestSnapshot = snapshot
	clearGrid()
	if completionLabel then
		completionLabel.Text = string.format(
			"DISCOVERED  %d / %d",
			snapshot.PublicDiscoveredCount,
			snapshot.PublicSpeciesCount
		)
	end

	local preservedEntry: IndexEntry? = nil
	local firstDiscovered: IndexEntry? = nil
	local firstEntry: IndexEntry? = nil
	local previousNumber = if selectedEntry then selectedEntry.IndexNumber else nil
	for index, entry in ipairs(snapshot.IndexSpecies) do
		local button = makeSpeciesTile(gridContent :: ScrollingFrame, entry, index)
		table.insert(tileButtons, button)
		if entry.IndexNumber == previousNumber then
			preservedEntry = entry
		end
		if not firstDiscovered and entry.Discovered then
			firstDiscovered = entry
		end
		firstEntry = firstEntry or entry
	end
	local defaultEntry = preservedEntry or firstDiscovered or firstEntry
	if defaultEntry then
		renderDetail(defaultEntry)
	end
end

local function showNewEntry(speciesId: string)
	notificationGeneration += 1
	local generation = notificationGeneration
	task.delay(NEW_ENTRY_DELAY_SECONDS, function()
		local label = notification
		if notificationGeneration ~= generation or not label then
			return
		end
		label.Text = "NEW INDEX ENTRY\n" .. string.upper(speciesId)
		label.Visible = true
		task.delay(2.8, function()
			if notificationGeneration == generation and notification == label then
				label.Visible = false
			end
		end)
	end)
end

local function handleFeedback(payload: any)
	if typeof(payload) == "table"
		and payload.Kind == "ODDLING_ADDED"
		and isShortText(payload.SpeciesId)
		and payload.FirstOwnedCopy == true
	then
		showNewEntry(payload.SpeciesId)
	end
end

local function createDetailPane(parent: Instance): ScrollingFrame
	local pane = Instance.new("ScrollingFrame")
	pane.Name = "SelectedOddlingDetail"
	pane.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pane.CanvasSize = UDim2.fromOffset(0, 548)
	pane.BackgroundColor3 = Color3.fromRGB(22, 26, 26)
	pane.BorderSizePixel = 0
	pane.ScrollBarThickness = 6
	pane.Parent = parent

	local accentRail = Instance.new("Frame")
	accentRail.Name = "DetailRail"
	accentRail.Size = UDim2.fromOffset(4, 548)
	accentRail.BackgroundColor3 = Color3.fromRGB(107, 150, 139)
	accentRail.BorderSizePixel = 0
	accentRail.Parent = pane
	detailRail = accentRail

	detailNumber = makeLabel(pane, "DetailNumber", "#---", UDim2.new(1, -32, 0, 18))
	detailNumber.Position = UDim2.fromOffset(18, 10)
	detailNumber.TextColor3 = Color3.fromRGB(137, 152, 146)
	detailNumber.TextSize = 11

	detailName = makeLabel(pane, "DetailName", "SELECT AN ODDLING", UDim2.new(1, -32, 0, 30))
	detailName.Position = UDim2.fromOffset(18, 28)
	detailName.Font = Enum.Font.GothamBlack
	detailName.TextColor3 = Color3.fromRGB(231, 238, 232)
	detailName.TextSize = 24

	detailClassification = makeLabel(pane, "Classification", "", UDim2.new(1, -32, 0, 22))
	detailClassification.Position = UDim2.fromOffset(18, 60)
	detailClassification.Font = Enum.Font.GothamBold
	detailClassification.TextColor3 = Color3.fromRGB(145, 204, 190)
	detailClassification.TextSize = 11

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "OddlingPreview"
	viewport.Position = UDim2.fromOffset(18, 90)
	viewport.Size = UDim2.new(1, -36, 0, 232)
	viewport.BackgroundColor3 = Color3.fromRGB(28, 33, 33)
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(170, 181, 177)
	viewport.LightColor = Color3.fromRGB(255, 238, 214)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Parent = pane
	previewFrame = viewport

	local world = Instance.new("WorldModel")
	world.Name = "PreviewWorld"
	world.Parent = viewport
	previewWorld = world

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 36
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	previewCamera = camera

	local unknown = makeLabel(viewport, "UnknownPreview", "UNDISCOVERED", UDim2.fromScale(1, 1))
	unknown.Font = Enum.Font.GothamBlack
	unknown.TextColor3 = Color3.fromRGB(93, 103, 100)
	unknown.TextSize = 18
	unknown.TextXAlignment = Enum.TextXAlignment.Center
	unknownPreview = unknown

	detailFlavor = makeLabel(pane, "FlavorText", "", UDim2.new(1, -36, 0, 52))
	detailFlavor.Position = UDim2.fromOffset(18, 330)
	detailFlavor.Font = Enum.Font.GothamMedium
	detailFlavor.TextColor3 = Color3.fromRGB(183, 194, 188)
	detailFlavor.TextSize = 13
	detailFlavor.TextYAlignment = Enum.TextYAlignment.Top

	detailProduction = makeLabel(pane, "Production", "", UDim2.new(1, -36, 0, 46))
	detailProduction.Position = UDim2.fromOffset(18, 386)
	detailProduction.Font = Enum.Font.GothamBold
	detailProduction.TextColor3 = Color3.fromRGB(239, 209, 116)
	detailProduction.TextSize = 12

	detailCounts = makeLabel(pane, "OwnershipCounts", "", UDim2.new(1, -36, 0, 36))
	detailCounts.Position = UDim2.fromOffset(18, 436)
	detailCounts.Font = Enum.Font.GothamBold
	detailCounts.TextSize = 11

	detailSecurity = makeLabel(pane, "Security", "", UDim2.new(0.42, -20, 0, 46))
	detailSecurity.Position = UDim2.fromOffset(18, 474)
	detailSecurity.Font = Enum.Font.GothamBold
	detailSecurity.TextColor3 = Color3.fromRGB(226, 163, 92)
	detailSecurity.TextSize = 11

	detailSource = makeLabel(pane, "RecoverySource", "", UDim2.new(0.58, -20, 0, 46))
	detailSource.Position = UDim2.new(0.42, 8, 0, 474)
	detailSource.Font = Enum.Font.GothamBold
	detailSource.TextColor3 = Color3.fromRGB(157, 179, 170)
	detailSource.TextSize = 11

	return pane
end

local function createInterface()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSOddlingIndexGui"
	screenGui.DisplayOrder = 19
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local openButton = makeButton(screenGui, "IndexButton", "INDEX", UDim2.fromOffset(122, 34))
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -14, 0, 94)
	openButton.BackgroundColor3 = Color3.fromRGB(65, 82, 78)

	local panel = Instance.new("Frame")
	panel.Name = "IndexPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.84, 0)
	panel.BackgroundColor3 = Color3.fromRGB(25, 29, 29)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 380)
	constraint.MaxSize = Vector2.new(980, 650)
	constraint.Parent = panel

	local title = makeLabel(panel, "Title", "ODDLING INDEX", UDim2.new(0.55, -20, 0, 34))
	title.Position = UDim2.fromOffset(16, 8)
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(146, 220, 202)
	title.TextSize = 20

	local completion = makeLabel(panel, "Completion", "DISCOVERED  0 / 0", UDim2.fromOffset(180, 26))
	completion.AnchorPoint = Vector2.new(1, 0)
	completion.Position = UDim2.new(1, -62, 0, 13)
	completion.Font = Enum.Font.GothamBold
	completion.TextColor3 = Color3.fromRGB(174, 188, 181)
	completion.TextSize = 11
	completion.TextXAlignment = Enum.TextXAlignment.Right
	completionLabel = completion

	local closeButton = makeButton(panel, "CloseButton", "X", UDim2.fromOffset(38, 32))
	closeButton.Position = UDim2.new(1, -50, 0, 10)

	local back = makeButton(panel, "BackButton", "<  INDEX", UDim2.fromOffset(92, 30))
	back.Position = UDim2.fromOffset(14, 42)
	back.BackgroundColor3 = Color3.fromRGB(45, 58, 55)
	back.Visible = false
	backButton = back

	local browser = Instance.new("Frame")
	browser.Name = "SpeciesBrowser"
	browser.BackgroundColor3 = Color3.fromRGB(19, 22, 22)
	browser.BorderSizePixel = 0
	browser.Parent = panel
	browserPane = browser

	local browserTitle = makeLabel(browser, "BrowserTitle", "SPECIES RECORDS", UDim2.new(1, -20, 0, 30))
	browserTitle.Position = UDim2.fromOffset(10, 4)
	browserTitle.Font = Enum.Font.GothamBold
	browserTitle.TextColor3 = Color3.fromRGB(151, 169, 161)
	browserTitle.TextSize = 11

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "SpeciesGrid"
	grid.Position = UDim2.fromOffset(8, 38)
	grid.Size = UDim2.new(1, -16, 1, -46)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.fromOffset(0, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 5
	grid.Parent = browser
	gridContent = grid

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 2)
	padding.PaddingTop = UDim.new(0, 2)
	padding.Parent = grid

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.CellSize = UDim2.new(0.5, -5, 0, 118)
	layout.FillDirectionMaxCells = 2
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	gridLayout = layout

	detailPane = createDetailPane(panel)

	local toast = makeLabel(screenGui, "NewEntryNotification", "", UDim2.fromOffset(250, 64))
	toast.Position = UDim2.fromOffset(14, 70)
	toast.BackgroundColor3 = Color3.fromRGB(27, 38, 37)
	toast.BackgroundTransparency = 0.08
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamBold
	toast.TextColor3 = Color3.fromRGB(146, 229, 207)
	toast.TextSize = 15
	toast.TextXAlignment = Enum.TextXAlignment.Center
	toast.Visible = false
	notification = toast

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end
	updateResponsiveLayout()

	openButton.Activated:Connect(function()
		local collectionGui = playerGui:FindFirstChild("ODDWORKSOddlingCollectionGui")
		local collectionPanel = if collectionGui then collectionGui:FindFirstChild("CollectionPanel") else nil
		if collectionPanel and collectionPanel:IsA("GuiObject") then
			collectionPanel.Visible = false
		end
		showingSmallDetail = false
		panel.Visible = true
		updateResponsiveLayout()
		if latestSnapshot then
			renderSnapshot(latestSnapshot :: IndexSnapshot)
		end
		local remote = requestRemote
		if remote then
			remote:FireServer()
		end
	end)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)
	back.Activated:Connect(function()
		showingSmallDetail = false
		updateResponsiveLayout()
	end)
end

function OddlingIndexController.Start()
	if started then
		return
	end
	started = true
	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	requestRemote = requireChildOfClass(network, "OddlingCollectionRequest", "RemoteEvent") :: RemoteEvent
	local snapshotRemote = requireChildOfClass(network, "OddlingCollectionSnapshot", "RemoteEvent") :: RemoteEvent
	local feedbackRemote = requireChildOfClass(network, "OddlingCollectionFeedback", "RemoteEvent") :: RemoteEvent
	createInterface()
	snapshotRemote.OnClientEvent:Connect(function(payload: any)
		local snapshot = readSnapshot(payload)
		if snapshot then
			renderSnapshot(snapshot)
		end
	end)
	feedbackRemote.OnClientEvent:Connect(handleFeedback)
end

return OddlingIndexController
