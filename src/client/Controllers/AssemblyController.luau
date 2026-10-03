--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type ComponentEntry = {
	ComponentId: string,
	DisplayName: string,
	Rarity: string,
	Slot: string,
	Count: number,
}

type ComponentSelection = {
	ComponentId: string,
	DisplayName: string,
	Rarity: string,
}

type PrototypeConstruct = {
	FrameId: string,
	Head: ComponentSelection,
	Arm: ComponentSelection,
	Legs: ComponentSelection,
}

type ModularSnapshot = {
	BankedComponents: { ComponentEntry },
	PrototypeConstruct: PrototypeConstruct?,
}

type AvailableSelection = ComponentSelection & {
	BankedCount: number,
	IsInstalled: boolean,
}

local AssemblyController = {}

local FRAME_ID = "SmallBiped_v1"
local LOCAL_REQUEST_INTERVAL_SECONDS = 1
local MAX_COMPONENT_ENTRIES = 54
local SLOT_ORDER = { "Head", "Arm", "Legs" }
local RARITY_ORDER: { [string]: number } = {
	Common = 1,
	Rare = 2,
	Legendary = 3,
}

local latestSnapshot: ModularSnapshot? = nil
local optionsBySlot: { [string]: { AvailableSelection } } = {}
local selectedIndices: { [string]: number } = {}
local selectionButtons: { [string]: TextButton } = {}
local panel: Frame? = nil
local currentBuildLabel: TextLabel? = nil
local actionButton: TextButton? = nil
local feedbackLabel: TextLabel? = nil
local stateRequest: RemoteEvent? = nil
local assemblyRequest: RemoteEvent? = nil
local lastLocalRequestTime = 0
local started = false

local function requireChildOfClass(parent: Instance, childName: string, expectedClassName: string): Instance
	local child = parent:WaitForChild(childName)
	if not child:IsA(expectedClassName) then
		error(
			string.format(
				"[ODDWORKS][AssemblyController] %s.%s must be a %s, but found %s.",
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

local function isBoundedString(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

local function isPositiveInteger(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
		and math.floor(value) == value
end

local function isValidRarity(value: any): boolean
	return RARITY_ORDER[value] ~= nil
end

local function isValidSlot(value: any): boolean
	return value == "Head" or value == "Arm" or value == "Legs"
end

local function readSelection(value: any): ComponentSelection?
	if typeof(value) ~= "table"
		or not isBoundedString(value.ComponentId, 48)
		or not isBoundedString(value.DisplayName, 64)
		or not isValidRarity(value.Rarity)
	then
		return nil
	end
	for key in pairs(value) do
		if key ~= "ComponentId" and key ~= "DisplayName" and key ~= "Rarity" then
			return nil
		end
	end
	return {
		ComponentId = value.ComponentId,
		DisplayName = value.DisplayName,
		Rarity = value.Rarity,
	}
end

local function readConstruct(value: any): PrototypeConstruct?
	if value == nil then
		return nil
	end
	if typeof(value) ~= "table" or value.FrameId ~= FRAME_ID then
		return nil
	end
	for key in pairs(value) do
		if key ~= "FrameId" and key ~= "Head" and key ~= "Arm" and key ~= "Legs" then
			return nil
		end
	end

	local head = readSelection(value.Head)
	local arm = readSelection(value.Arm)
	local legs = readSelection(value.Legs)
	if not head or not arm or not legs then
		return nil
	end
	return {
		FrameId = value.FrameId,
		Head = head,
		Arm = arm,
		Legs = legs,
	}
end

local function readSnapshot(payload: any): ModularSnapshot?
	if typeof(payload) ~= "table"
		or typeof(payload.UnbankedComponents) ~= "table"
		or typeof(payload.BankedComponents) ~= "table"
		or #payload.BankedComponents > MAX_COMPONENT_ENTRIES
	then
		return nil
	end
	for key in pairs(payload) do
		if key ~= "UnbankedComponents" and key ~= "BankedComponents" and key ~= "PrototypeConstruct" then
			return nil
		end
	end

	local entries: { ComponentEntry } = {}
	for _, entry in ipairs(payload.BankedComponents) do
		if typeof(entry) ~= "table"
			or not isBoundedString(entry.ComponentId, 48)
			or not isBoundedString(entry.DisplayName, 64)
			or not isValidRarity(entry.Rarity)
			or not isValidSlot(entry.Slot)
			or not isPositiveInteger(entry.Count)
			or entry.Count > 999
		then
			return nil
		end
		table.insert(entries, {
			ComponentId = entry.ComponentId,
			DisplayName = entry.DisplayName,
			Rarity = entry.Rarity,
			Slot = entry.Slot,
			Count = entry.Count,
		})
	end

	local construct = readConstruct(payload.PrototypeConstruct)
	if payload.PrototypeConstruct ~= nil and not construct then
		return nil
	end
	return {
		BankedComponents = entries,
		PrototypeConstruct = construct,
	}
end

local function selectionKey(selection: ComponentSelection): string
	return selection.ComponentId .. "\0" .. selection.Rarity
end

local function getInstalledSelection(construct: PrototypeConstruct?, slot: string): ComponentSelection?
	if not construct then
		return nil
	end
	if slot == "Head" then
		return construct.Head
	elseif slot == "Arm" then
		return construct.Arm
	else
		return construct.Legs
	end
end

local function formatOption(option: AvailableSelection): string
	local availability = string.format("banked x%d", option.BankedCount)
	if option.IsInstalled then
		availability = if option.BankedCount > 0 then availability .. " + installed" else "installed"
	end
	return string.format("%s [%s] - %s", option.DisplayName, option.Rarity, availability)
end

local function getSelectedOption(slot: string): AvailableSelection?
	local options = optionsBySlot[slot]
	local index = selectedIndices[slot]
	return if options and index then options[index] else nil
end

local function refreshButton(slot: string)
	local button = selectionButtons[slot]
	if not button then
		return
	end
	local selected = getSelectedOption(slot)
	button.Text = if selected then formatOption(selected) else "No available component"
	button.Active = selected ~= nil
	button.AutoButtonColor = selected ~= nil
end

local function rebuildOptions(snapshot: ModularSnapshot)
	for _, slot in ipairs(SLOT_ORDER) do
		local previousSelection = getSelectedOption(slot)
		local previousKey = if previousSelection then selectionKey(previousSelection) else nil
		local installed = getInstalledSelection(snapshot.PrototypeConstruct, slot)
		local installedKey = if installed then selectionKey(installed) else nil
		local options: { AvailableSelection } = {}
		local optionsByKey: { [string]: AvailableSelection } = {}

		for _, entry in ipairs(snapshot.BankedComponents) do
			if entry.Slot == slot then
				local option: AvailableSelection = {
					ComponentId = entry.ComponentId,
					DisplayName = entry.DisplayName,
					Rarity = entry.Rarity,
					BankedCount = entry.Count,
					IsInstalled = false,
				}
				optionsByKey[selectionKey(option)] = option
				table.insert(options, option)
			end
		end

		if installed then
			local existing = optionsByKey[installedKey :: string]
			if existing then
				existing.IsInstalled = true
			else
				local option: AvailableSelection = {
					ComponentId = installed.ComponentId,
					DisplayName = installed.DisplayName,
					Rarity = installed.Rarity,
					BankedCount = 0,
					IsInstalled = true,
				}
				table.insert(options, option)
			end
		end

		table.sort(options, function(left: AvailableSelection, right: AvailableSelection): boolean
			if left.DisplayName == right.DisplayName then
				return (RARITY_ORDER[left.Rarity] or 0) < (RARITY_ORDER[right.Rarity] or 0)
			end
			return left.DisplayName < right.DisplayName
		end)

		optionsBySlot[slot] = options
		selectedIndices[slot] = 1
		local preferredKey = installedKey or previousKey
		if preferredKey then
			for index, option in ipairs(options) do
				if selectionKey(option) == preferredKey then
					selectedIndices[slot] = index
					break
				end
			end
		end
		refreshButton(slot)
	end

	local label = currentBuildLabel
	local button = actionButton
	if snapshot.PrototypeConstruct then
		local construct = snapshot.PrototypeConstruct
		if label then
			label.Text = string.format(
				"CURRENT BUILD\nHead: %s [%s]\nArms: %s [%s]\nLegs: %s [%s]",
				construct.Head.DisplayName,
				construct.Head.Rarity,
				construct.Arm.DisplayName,
				construct.Arm.Rarity,
				construct.Legs.DisplayName,
				construct.Legs.Rarity
			)
		end
		if button then
			button.Text = "REBUILD"
		end
	else
		if label then
			label.Text = "CURRENT BUILD\nNone"
		end
		if button then
			button.Text = "ASSEMBLE"
		end
	end
end

local function showFeedback(message: string, isSuccess: boolean)
	local label = feedbackLabel
	if not label then
		return
	end
	label.Text = message
	label.TextColor3 = if isSuccess then Color3.fromRGB(137, 222, 148) else Color3.fromRGB(245, 155, 129)
end

local function createInterface()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ODDWORKSPrototypeAssemblyGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 8
	screenGui.Parent = playerGui

	local assemblyPanel = Instance.new("Frame")
	assemblyPanel.Name = "AssemblyPanel"
	assemblyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	assemblyPanel.Position = UDim2.fromScale(0.5, 0.5)
	assemblyPanel.Size = UDim2.new(0.9, 0, 0, 430)
	assemblyPanel.BackgroundColor3 = Color3.fromRGB(31, 34, 33)
	assemblyPanel.BackgroundTransparency = 0.03
	assemblyPanel.BorderSizePixel = 0
	assemblyPanel.Visible = false
	assemblyPanel.Parent = screenGui
	panel = assemblyPanel

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(300, 430)
	sizeConstraint.MaxSize = Vector2.new(520, 430)
	sizeConstraint.Parent = assemblyPanel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.new(1, -70, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "SMALLBIPED_V1 ASSEMBLER"
	title.TextColor3 = Color3.fromRGB(245, 238, 214)
	title.TextSize = 19
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = assemblyPanel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.fromOffset(36, 36)
	closeButton.BackgroundColor3 = Color3.fromRGB(68, 71, 68)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(245, 238, 214)
	closeButton.TextSize = 18
	closeButton.Parent = assemblyPanel
	closeButton.Activated:Connect(function()
		assemblyPanel.Visible = false
	end)

	local buildLabel = Instance.new("TextLabel")
	buildLabel.Name = "CurrentBuildLabel"
	buildLabel.Position = UDim2.fromOffset(20, 53)
	buildLabel.Size = UDim2.new(1, -40, 0, 94)
	buildLabel.BackgroundColor3 = Color3.fromRGB(44, 48, 46)
	buildLabel.BorderSizePixel = 0
	buildLabel.Font = Enum.Font.Gotham
	buildLabel.Text = "CURRENT BUILD\nLoading..."
	buildLabel.TextColor3 = Color3.fromRGB(225, 224, 208)
	buildLabel.TextSize = 14
	buildLabel.TextWrapped = true
	buildLabel.TextXAlignment = Enum.TextXAlignment.Left
	buildLabel.TextYAlignment = Enum.TextYAlignment.Top
	buildLabel.Parent = assemblyPanel
	currentBuildLabel = buildLabel

	local roleLabels = { Head = "HEAD", Arm = "ARMS", Legs = "LEGS" }
	for index, slot in ipairs(SLOT_ORDER) do
		local y = 160 + (index - 1) * 55
		local roleLabel = Instance.new("TextLabel")
		roleLabel.Position = UDim2.fromOffset(20, y)
		roleLabel.Size = UDim2.fromOffset(65, 42)
		roleLabel.BackgroundTransparency = 1
		roleLabel.Font = Enum.Font.GothamBold
		roleLabel.Text = roleLabels[slot]
		roleLabel.TextColor3 = Color3.fromRGB(196, 191, 168)
		roleLabel.TextSize = 14
		roleLabel.TextXAlignment = Enum.TextXAlignment.Left
		roleLabel.Parent = assemblyPanel

		local optionButton = Instance.new("TextButton")
		optionButton.Name = slot .. "SelectionButton"
		optionButton.Position = UDim2.new(0, 88, 0, y)
		optionButton.Size = UDim2.new(1, -108, 0, 42)
		optionButton.BackgroundColor3 = Color3.fromRGB(61, 68, 64)
		optionButton.BorderSizePixel = 0
		optionButton.Font = Enum.Font.Gotham
		optionButton.Text = "No available component"
		optionButton.TextColor3 = Color3.fromRGB(245, 238, 214)
		optionButton.TextSize = 14
		optionButton.TextWrapped = true
		optionButton.Parent = assemblyPanel
		selectionButtons[slot] = optionButton
		optionButton.Activated:Connect(function()
			local options = optionsBySlot[slot]
			if not options or #options == 0 then
				return
			end
			selectedIndices[slot] = ((selectedIndices[slot] or 1) % #options) + 1
			refreshButton(slot)
		end)
	end

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "AssemblyFeedbackLabel"
	resultLabel.Position = UDim2.fromOffset(20, 328)
	resultLabel.Size = UDim2.new(1, -40, 0, 30)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.Gotham
	resultLabel.Text = ""
	resultLabel.TextColor3 = Color3.fromRGB(245, 155, 129)
	resultLabel.TextSize = 14
	resultLabel.TextWrapped = true
	resultLabel.Parent = assemblyPanel
	feedbackLabel = resultLabel

	local submitButton = Instance.new("TextButton")
	submitButton.Name = "AssembleButton"
	submitButton.AnchorPoint = Vector2.new(0.5, 0)
	submitButton.Position = UDim2.new(0.5, 0, 0, 370)
	submitButton.Size = UDim2.fromOffset(220, 44)
	submitButton.BackgroundColor3 = Color3.fromRGB(184, 91, 53)
	submitButton.BorderSizePixel = 0
	submitButton.Font = Enum.Font.GothamBold
	submitButton.Text = "ASSEMBLE"
	submitButton.TextColor3 = Color3.fromRGB(255, 247, 225)
	submitButton.TextSize = 17
	submitButton.Parent = assemblyPanel
	actionButton = submitButton
	submitButton.Activated:Connect(function()
		local remote = assemblyRequest
		local head = getSelectedOption("Head")
		local arm = getSelectedOption("Arm")
		local legs = getSelectedOption("Legs")
		if not remote or not head or not arm or not legs then
			showFeedback("Select one owned component for every role.", false)
			return
		end

		local now = os.clock()
		if now - lastLocalRequestTime < LOCAL_REQUEST_INTERVAL_SECONDS then
			return
		end
		lastLocalRequestTime = now
		showFeedback("Submitting authoritative assembly request...", true)
		remote:FireServer({
			FrameId = FRAME_ID,
			Head = { ComponentId = head.ComponentId, Rarity = head.Rarity },
			Arm = { ComponentId = arm.ComponentId, Rarity = arm.Rarity },
			Legs = { ComponentId = legs.ComponentId, Rarity = legs.Rarity },
		})
	end)
end

function AssemblyController.Start()
	if started then
		return
	end
	started = true

	local networkFolder = requireChildOfClass(ReplicatedStorage, "ODDWORKSNetwork", "Folder")
	stateRequest = requireChildOfClass(networkFolder, "ModularStateRequest", "RemoteEvent") :: RemoteEvent
	local stateSnapshot = requireChildOfClass(networkFolder, "ModularStateSnapshot", "RemoteEvent") :: RemoteEvent
	local openRemote = requireChildOfClass(networkFolder, "AssemblerOpen", "RemoteEvent") :: RemoteEvent
	assemblyRequest = requireChildOfClass(networkFolder, "AssembleConstructRequest", "RemoteEvent") :: RemoteEvent
	local resultRemote = requireChildOfClass(networkFolder, "AssemblyResult", "RemoteEvent") :: RemoteEvent
	createInterface()

	stateSnapshot.OnClientEvent:Connect(function(payload: any)
		local snapshot = readSnapshot(payload)
		if not snapshot then
			return
		end
		latestSnapshot = snapshot
		rebuildOptions(snapshot)
	end)

	openRemote.OnClientEvent:Connect(function(...: any)
		if select("#", ...) ~= 0 then
			return
		end
		if panel then
			panel.Visible = true
		end
		showFeedback("", false)
		if latestSnapshot then
			rebuildOptions(latestSnapshot)
		end
		if stateRequest then
			stateRequest:FireServer()
		end
	end)

	resultRemote.OnClientEvent:Connect(function(resultCode: any, mode: any, ...: any)
		if select("#", ...) ~= 0 or typeof(resultCode) ~= "string" then
			return
		end

		if resultCode == "ASSEMBLY_SUCCESS" and (mode == "ASSEMBLED" or mode == "REBUILT") then
			showFeedback(if mode == "ASSEMBLED" then "Prototype Construct assembled." else "Prototype Construct rebuilt.", true)
		elseif resultCode == "INSUFFICIENT_COMPONENTS" then
			showFeedback("One or more selected components are unavailable.", false)
		elseif resultCode == "INCOMPATIBLE_COMPONENT" or resultCode == "INVALID_COMPONENT" or resultCode == "INVALID_FRAME" then
			showFeedback("Selection is not compatible with SmallBiped_v1.", false)
		elseif resultCode == "RATE_LIMITED" then
			showFeedback("Please wait before assembling again.", false)
		elseif resultCode == "OUT_OF_RANGE" then
			showFeedback("Return to your assigned assembler.", false)
		else
			showFeedback("Assembly request rejected.", false)
		end
	end)
end

return AssemblyController
