--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type SpeciesEntry = {
	SpeciesId: string,
	OwnedCount: number,
	DisplayedCount: number,
	CollectionCount: number,
	HypePerInterval: number,
	HypeIntervalSeconds: number,
}

type SlotEntry = {
	SlotIndex: number,
	SpeciesId: string?,
	Unlocked: boolean,
}

type CollectionSnapshot = {
	WorkshopLevel: number,
	Capacity: number,
	UsedSlots: number,
	CollectionOnlyCount: number,
	Species: { SpeciesEntry },
	Slots: { SlotEntry },
}

local OddlingCollectionController = {}

local MAX_SPECIES = 16
local MAX_SLOTS = 8
local MAX_SPECIES_ID_LENGTH = 64

local latestSnapshot: CollectionSnapshot? = nil
local selectedSpeciesId: string? = nil
local pendingSlotIndex: number? = nil
local panel: Frame? = nil
local capacityLabel: TextLabel? = nil
local pendingLabel: TextLabel? = nil
local content: ScrollingFrame? = nil
local requestRemote: RemoteEvent? = nil
local editRemote: RemoteEvent? = nil
local feedbackLabel: TextLabel? = nil
local feedbackGeneration = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][OddlingCollection] %s.%s must be a %s, but found %s.",
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

local function isSpeciesId(value: any): boolean
	return typeof(value) == "string" and #value > 0 and #value <= MAX_SPECIES_ID_LENGTH
end

local function readSnapshot(payload: any): CollectionSnapshot?
	if typeof(payload) ~= "table"
		or not isIntegerInRange(payload.WorkshopLevel, 1, 100)
		or not isIntegerInRange(payload.Capacity, 0, MAX_SLOTS)
		or not isIntegerInRange(payload.UsedSlots, 0, MAX_SLOTS)
		or not isIntegerInRange(payload.CollectionOnlyCount, 0, 1000000)
		or typeof(payload.Species) ~= "table"
		or #payload.Species > MAX_SPECIES
		or typeof(payload.Slots) ~= "table"
		or #payload.Slots > MAX_SLOTS
	then
		return nil
	end

	local species: { SpeciesEntry } = {}
	local knownSpecies: { [string]: boolean } = {}
	for _, entry in ipairs(payload.Species) do
		if typeof(entry) ~= "table"
			or not isSpeciesId(entry.SpeciesId)
			or knownSpecies[entry.SpeciesId]
			or not isIntegerInRange(entry.OwnedCount, 1, 1000000)
			or not isIntegerInRange(entry.DisplayedCount, 0, MAX_SLOTS)
			or not isIntegerInRange(entry.CollectionCount, 0, 1000000)
			or entry.DisplayedCount + entry.CollectionCount ~= entry.OwnedCount
			or not isFiniteNonnegativeNumber(entry.HypePerInterval)
			or not isFiniteNonnegativeNumber(entry.HypeIntervalSeconds)
			or entry.HypeIntervalSeconds <= 0
		then
			return nil
		end
		knownSpecies[entry.SpeciesId] = true
		table.insert(species, {
			SpeciesId = entry.SpeciesId,
			OwnedCount = entry.OwnedCount,
			DisplayedCount = entry.DisplayedCount,
			CollectionCount = entry.CollectionCount,
			HypePerInterval = entry.HypePerInterval,
			HypeIntervalSeconds = entry.HypeIntervalSeconds,
		})
	end

	local slots: { SlotEntry } = {}
	local seenSlots: { [number]: boolean } = {}
	for _, entry in ipairs(payload.Slots) do
		if typeof(entry) ~= "table"
			or not isIntegerInRange(entry.SlotIndex, 1, MAX_SLOTS)
			or seenSlots[entry.SlotIndex]
			or typeof(entry.Unlocked) ~= "boolean"
			or (entry.SpeciesId ~= nil and not isSpeciesId(entry.SpeciesId))
			or (entry.SpeciesId ~= nil and not knownSpecies[entry.SpeciesId])
		then
			return nil
		end
		seenSlots[entry.SlotIndex] = true
		table.insert(slots, {
			SlotIndex = entry.SlotIndex,
			SpeciesId = entry.SpeciesId,
			Unlocked = entry.Unlocked,
		})
	end
	table.sort(slots, function(left: SlotEntry, right: SlotEntry): boolean
		return left.SlotIndex < right.SlotIndex
	end)

	if payload.UsedSlots > payload.Capacity then
		return nil
	end
	return {
		WorkshopLevel = payload.WorkshopLevel,
		Capacity = payload.Capacity,
		UsedSlots = payload.UsedSlots,
		CollectionOnlyCount = payload.CollectionOnlyCount,
		Species = species,
		Slots = slots,
	}
end

local function makeLabel(parent: Instance, name: string, text: string, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(220, 225, 216)
	label.TextSize = 14
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
	button.BackgroundColor3 = Color3.fromRGB(61, 72, 68)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 239, 229)
	button.TextSize = 13
	button.TextWrapped = true
	button.Parent = parent
	return button
end

local function showFeedback(message: string, success: boolean)
	local label = feedbackLabel
	if not label then
		return
	end
	feedbackGeneration += 1
	local generation = feedbackGeneration
	label.Text = message
	label.TextColor3 = if success then Color3.fromRGB(137, 229, 166) else Color3.fromRGB(247, 170, 127)
	label.Visible = true
	task.delay(4, function()
		if feedbackLabel == label and feedbackGeneration == generation then
			label.Visible = false
		end
	end)
end

local function clearDynamicContent()
	local parent = content
	if not parent then
		return
	end
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function addSectionHeading(text: string, layoutOrder: number)
	local parent = content
	if not parent then
		return
	end
	local heading = makeLabel(parent, text:gsub(" ", "") .. "Heading", text, UDim2.new(1, 0, 0, 28))
	heading.Font = Enum.Font.GothamBold
	heading.TextColor3 = Color3.fromRGB(119, 222, 184)
	heading.TextSize = 13
	heading.LayoutOrder = layoutOrder
end

local renderSnapshot: ((CollectionSnapshot) -> ())? = nil

local function renderSpeciesRow(entry: SpeciesEntry, layoutOrder: number)
	local parent = content
	if not parent then
		return
	end
	local row = Instance.new("Frame")
	row.Name = entry.SpeciesId .. "Row"
	row.Size = UDim2.new(1, 0, 0, 88)
	row.BackgroundColor3 = if selectedSpeciesId == entry.SpeciesId
		then Color3.fromRGB(44, 72, 64)
		else Color3.fromRGB(38, 43, 42)
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local title = makeLabel(row, "SpeciesName", string.upper(entry.SpeciesId), UDim2.new(1, -138, 0, 28))
	title.Position = UDim2.fromOffset(12, 7)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(239, 237, 210)

	local counts = makeLabel(
		row,
		"Counts",
		string.format(
			"OWNED %d   DISPLAYED %d   IN COLLECTION %d\n+%g Hype / %gs while displayed",
			entry.OwnedCount,
			entry.DisplayedCount,
			entry.CollectionCount,
			entry.HypePerInterval,
			entry.HypeIntervalSeconds
		),
		UDim2.new(1, -150, 0, 48)
	)
	counts.Position = UDim2.fromOffset(12, 34)
	counts.TextSize = 12
	counts.TextColor3 = Color3.fromRGB(192, 202, 194)

	local selectButton = makeButton(
		row,
		"SelectButton",
		if selectedSpeciesId == entry.SpeciesId then "SELECTED" else "SELECT",
		UDim2.fromOffset(112, 36)
	)
	selectButton.Position = UDim2.new(1, -124, 0.5, -18)
	selectButton.BackgroundColor3 = if selectedSpeciesId == entry.SpeciesId
		then Color3.fromRGB(52, 121, 94)
		else Color3.fromRGB(61, 72, 68)
	selectButton.Activated:Connect(function()
		selectedSpeciesId = entry.SpeciesId
		pendingSlotIndex = nil
		local renderer = renderSnapshot
		if latestSnapshot and renderer then
			renderer(latestSnapshot :: CollectionSnapshot)
		end
	end)
end

local function renderSlotRow(entry: SlotEntry, layoutOrder: number)
	local parent = content
	if not parent then
		return
	end
	local row = Instance.new("Frame")
	row.Name = string.format("Slot%02dRow", entry.SlotIndex)
	row.Size = UDim2.new(1, 0, 0, 60)
	row.BackgroundColor3 = if entry.Unlocked then Color3.fromRGB(36, 42, 41) else Color3.fromRGB(28, 31, 31)
	row.BackgroundTransparency = if entry.Unlocked then 0 else 0.25
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local state = if not entry.Unlocked then "LOCKED" elseif entry.SpeciesId then string.upper(entry.SpeciesId) else "EMPTY"
	local label = makeLabel(
		row,
		"SlotState",
		string.format("SLOT %d\n%s", entry.SlotIndex, state),
		UDim2.new(1, -260, 1, 0)
	)
	label.Position = UDim2.fromOffset(12, 0)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = if entry.Unlocked then Color3.fromRGB(225, 229, 216) else Color3.fromRGB(117, 123, 119)

	if entry.Unlocked and selectedSpeciesId then
		local assignButton = makeButton(row, "AssignButton", "DISPLAY HERE", UDim2.fromOffset(112, 36))
		assignButton.Position = UDim2.new(1, -244, 0.5, -18)
		assignButton.BackgroundColor3 = Color3.fromRGB(51, 103, 82)
		assignButton.Activated:Connect(function()
			local remote = editRemote
			local selected = selectedSpeciesId
			if remote and selected then
				pendingSlotIndex = entry.SlotIndex
				if pendingLabel then
					pendingLabel.Text = string.format("PENDING SLOT %d: %s", entry.SlotIndex, string.upper(selected))
				end
				remote:FireServer("ASSIGN", entry.SlotIndex, selected)
			end
		end)
	end

	if entry.Unlocked and entry.SpeciesId then
		local clearButton = makeButton(row, "ClearButton", "REMOVE FROM\nDISPLAY", UDim2.fromOffset(112, 36))
		clearButton.Position = UDim2.new(1, -124, 0.5, -18)
		clearButton.BackgroundColor3 = Color3.fromRGB(91, 66, 58)
		clearButton.TextSize = 11
		clearButton.Activated:Connect(function()
			local remote = editRemote
			if remote then
				pendingSlotIndex = entry.SlotIndex
				if pendingLabel then
					pendingLabel.Text = string.format("PENDING SLOT %d: REMOVE", entry.SlotIndex)
				end
				remote:FireServer("CLEAR", entry.SlotIndex)
			end
		end)
	end
end

renderSnapshot = function(snapshot: CollectionSnapshot)
	latestSnapshot = snapshot
	local cap = capacityLabel
	if cap then
		cap.Text = string.format(
			"WORKSHOP DISPLAY CAPACITY   %d / %d SLOTS USED   |   %d IN COLLECTION",
			snapshot.UsedSlots,
			snapshot.Capacity,
			snapshot.CollectionOnlyCount
		)
	end
	local pending = pendingLabel
	if pending then
		if pendingSlotIndex then
			-- Keep explicit pending feedback until the next authoritative snapshot.
			pending.Text = string.format("PENDING SERVER CONFIRMATION: SLOT %d", pendingSlotIndex)
		else
			pending.Text = if selectedSpeciesId
				then "SELECTED: " .. string.upper(selectedSpeciesId) .. "   CHOOSE AN UNLOCKED SLOT"
				else "SELECT AN OWNED ODDLING"
		end
	end

	clearDynamicContent()
	addSectionHeading("OWNED ODDLINGS", 1)
	local order = 10
	if #snapshot.Species == 0 then
		local empty = makeLabel(content :: ScrollingFrame, "EmptyCollection", "No recovered Oddlings yet.", UDim2.new(1, 0, 0, 48))
		empty.LayoutOrder = order
	else
		for _, entry in ipairs(snapshot.Species) do
			renderSpeciesRow(entry, order)
			order += 1
		end
	end

	addSectionHeading("DISPLAY SLOTS", 100)
	order += 10
	for _, entry in ipairs(snapshot.Slots) do
		renderSlotRow(entry, 100 + order)
		order += 1
	end
end

local function handleFeedback(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Kind) ~= "string" then
		return
	end
	pendingSlotIndex = nil
	if payload.Kind == "ODDLING_ADDED"
		and isSpeciesId(payload.SpeciesId)
		and isIntegerInRange(payload.AddedCount, 1, 1000)
		and isIntegerInRange(payload.AutoDisplayedCount, 0, MAX_SLOTS)
		and typeof(payload.FirstOwnedCopy) == "boolean"
	then
		local function showOddlingAdded()
			local heading = string.format("NEW ODDLING\n%s +%d", string.upper(payload.SpeciesId), payload.AddedCount)
			if payload.AutoDisplayedCount > 0 and isIntegerInRange(payload.FirstSlotIndex, 1, MAX_SLOTS) then
				local outcome = string.format("\nDISPLAYED IN SLOT %d", payload.FirstSlotIndex)
				if payload.DisplayFull == true then
					outcome ..= "\nREMAINDER ADDED TO COLLECTION"
				end
				showFeedback(heading .. outcome, true)
			else
				showFeedback(heading .. "\nADDED TO COLLECTION - DISPLAY FULL", true)
			end
		end
		-- The first Voltlet display confirmation follows the secure/reveal banner
		-- instead of competing with it. Repeat recoveries retain immediate feedback.
		if payload.SpeciesId == "Voltlet" and payload.FirstOwnedCopy == true then
			task.delay(3.2, showOddlingAdded)
		else
			showOddlingAdded()
		end
	elseif payload.Kind == "DISPLAY_ASSIGNED"
		and isSpeciesId(payload.SpeciesId)
		and isIntegerInRange(payload.SlotIndex, 1, MAX_SLOTS)
	then
		selectedSpeciesId = nil
		showFeedback(string.format("%s DISPLAYED IN SLOT %d", string.upper(payload.SpeciesId), payload.SlotIndex), true)
		local renderer = renderSnapshot
		if latestSnapshot and renderer then
			renderer(latestSnapshot :: CollectionSnapshot)
		end
	elseif payload.Kind == "DISPLAY_CLEARED"
		and isSpeciesId(payload.SpeciesId)
		and isIntegerInRange(payload.SlotIndex, 1, MAX_SLOTS)
	then
		showFeedback(string.upper(payload.SpeciesId) .. " REMOVED FROM DISPLAY\nRETURNED TO COLLECTION", true)
	elseif payload.Kind == "WORKSHOP_EXPANDED" and isIntegerInRange(payload.AddedSlots, 0, MAX_SLOTS) then
		showFeedback(string.format("WORKSHOP EXPANDED\n+%d DISPLAY SLOTS", payload.AddedSlots), true)
	end
end

local function createInterface()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSOddlingCollectionGui"
	screenGui.DisplayOrder = 18
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local openButton = makeButton(screenGui, "CollectionButton", "COLLECTION", UDim2.fromOffset(122, 34))
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -14, 0, 52)
	openButton.BackgroundColor3 = Color3.fromRGB(47, 91, 76)

	local collectionPanel = Instance.new("Frame")
	collectionPanel.Name = "CollectionPanel"
	collectionPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	collectionPanel.Position = UDim2.fromScale(0.5, 0.5)
	collectionPanel.Size = UDim2.new(0.92, 0, 0.84, 0)
	collectionPanel.BackgroundColor3 = Color3.fromRGB(27, 31, 30)
	collectionPanel.BorderSizePixel = 0
	collectionPanel.Visible = false
	collectionPanel.Parent = screenGui
	panel = collectionPanel

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(420, 420)
	sizeConstraint.MaxSize = Vector2.new(680, 620)
	sizeConstraint.Parent = collectionPanel

	local title = makeLabel(collectionPanel, "Title", "ODDLING COLLECTION", UDim2.new(1, -72, 0, 38))
	title.Position = UDim2.fromOffset(18, 8)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(128, 229, 189)
	title.TextSize = 19

	local closeButton = makeButton(collectionPanel, "CloseButton", "X", UDim2.fromOffset(38, 32))
	closeButton.Position = UDim2.new(1, -50, 0, 10)

	local capacity = makeLabel(collectionPanel, "Capacity", "WORKSHOP DISPLAY CAPACITY", UDim2.new(1, -36, 0, 26))
	capacity.Position = UDim2.fromOffset(18, 48)
	capacity.Font = Enum.Font.GothamBold
	capacity.TextColor3 = Color3.fromRGB(226, 222, 190)
	capacity.TextSize = 13
	capacityLabel = capacity

	local pending = makeLabel(collectionPanel, "PendingSelection", "SELECT AN OWNED ODDLING", UDim2.new(1, -36, 0, 26))
	pending.Position = UDim2.fromOffset(18, 74)
	pending.TextColor3 = Color3.fromRGB(164, 183, 172)
	pending.TextSize = 12
	pendingLabel = pending

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CollectionContent"
	scroll.Position = UDim2.fromOffset(16, 108)
	scroll.Size = UDim2.new(1, -32, 1, -124)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.BackgroundColor3 = Color3.fromRGB(20, 23, 23)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 7
	scroll.Parent = collectionPanel
	content = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	local feedback = makeLabel(screenGui, "CollectionFeedback", "", UDim2.new(0.86, 0, 0, 86))
	feedback.AnchorPoint = Vector2.new(0.5, 1)
	feedback.Position = UDim2.new(0.5, 0, 1, -36)
	feedback.BackgroundColor3 = Color3.fromRGB(24, 31, 29)
	feedback.BackgroundTransparency = 0.08
	feedback.BorderSizePixel = 0
	feedback.Font = Enum.Font.GothamBold
	feedback.TextSize = 17
	feedback.TextXAlignment = Enum.TextXAlignment.Center
	feedback.Visible = false
	feedback.Parent = screenGui
	local feedbackConstraint = Instance.new("UISizeConstraint")
	feedbackConstraint.MaxSize = Vector2.new(560, 86)
	feedbackConstraint.Parent = feedback
	feedbackLabel = feedback

	local function openCollection()
		collectionPanel.Visible = true
		local remote = requestRemote
		if remote then
			remote:FireServer()
		end
	end
	openButton.Activated:Connect(openCollection)
	closeButton.Activated:Connect(function()
		collectionPanel.Visible = false
	end)
end

function OddlingCollectionController.Start()
	if started then
		return
	end
	started = true
	local network = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	requestRemote = requireChildOfClass(network, "OddlingCollectionRequest", "RemoteEvent") :: RemoteEvent
	local snapshotRemote = requireChildOfClass(network, "OddlingCollectionSnapshot", "RemoteEvent") :: RemoteEvent
	editRemote = requireChildOfClass(network, "OddlingDisplayEditRequest", "RemoteEvent") :: RemoteEvent
	local collectionFeedback = requireChildOfClass(network, "OddlingCollectionFeedback", "RemoteEvent") :: RemoteEvent

	createInterface()
	snapshotRemote.OnClientEvent:Connect(function(payload: any)
		local snapshot = readSnapshot(payload)
		local renderer = renderSnapshot
		if snapshot and renderer then
			pendingSlotIndex = nil
			renderer(snapshot)
		end
	end)
	collectionFeedback.OnClientEvent:Connect(handleFeedback)
	local initialRequest = requestRemote
	if initialRequest then
		initialRequest:FireServer()
	end
end

return OddlingCollectionController
