--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][PrototypeRuntime] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local Components = require(Config:WaitForChild("Components"))
local ModularPrototypeStateService = require(Services:WaitForChild("ModularPrototypeStateService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

type ComponentSelection = {
	ComponentId: string,
	Rarity: string,
}

type PrototypeConstruct = {
	FrameId: string,
	Head: ComponentSelection,
	Arm: ComponentSelection,
	Legs: ComponentSelection,
}

type ComponentDefinition = {
	ComponentId: string,
	DisplayName: string,
	Slot: string,
	ArtModel: string,
	CompatibleFrames: { [string]: boolean },
}

type RoleContract = {
	Role: string,
	SocketName: string,
	JointName: string,
	SocketCFrame: CFrame,
}

local FRAME_ID = "SmallBiped_v1"
local FRAME_TEMPLATE_NAME = "SmallBiped_v1_Frame"
local DISPLAY_MARKER_NAME = "PrototypeConstructDisplay"
local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "PrototypeConstructs"
local CONSTRUCT_MODEL_NAME = "SmallBiped_v1"
local ROOT_PART_NAME = "RootPart"
local MODULE_ROOT_NAME = "ModuleRoot"
local MOUNT_ATTACHMENT_NAME = "MountAttachment"
local ROOT_GROUND_OFFSET = 3
local AUDIT_INTERVAL_SECONDS = 2
local TRANSFORM_EPSILON = 0.0001

local ROLE_CONTRACTS: { RoleContract } = {
	{
		Role = "Head",
		SocketName = "HeadSocket",
		JointName = "HeadJoint",
		SocketCFrame = CFrame.new(0, 1.5, 0),
	},
	{
		Role = "Arm",
		SocketName = "ArmSocket",
		JointName = "ArmJoint",
		SocketCFrame = CFrame.new(0, 0.25, 0),
	},
	{
		Role = "Legs",
		SocketName = "LegsSocket",
		JointName = "LegsJoint",
		SocketCFrame = CFrame.new(0, -1.25, 0),
	},
}

local PrototypeConstructRuntimeService = {}

-- Runtime Models are disposable projections. All authority remains in
-- ModularPrototypeStateService's copied PrototypeConstruct record.
local runtimeConstructsFolder: Folder? = nil
local pendingReconciliations: { [Player]: boolean } = {}
local suppressRecovery: { [Player]: boolean } = {}
local modelConnections: { [Player]: RBXScriptConnection } = {}
local containerConnections: { [Player]: RBXScriptConnection } = {}
local recoveryGenerations: { [Player]: number } = {}
local warningKeys: { [string]: boolean } = {}
local started = false

local function warnOnce(key: string, message: string)
	if warningKeys[key] then
		return
	end

	warningKeys[key] = true
	warn(message)
end

local function clearWarning(key: string)
	warningKeys[key] = nil
end

local function getOrCreateFolder(parent: Instance, childName: string): Folder?
	local existing = parent:FindFirstChild(childName)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end

	warn(string.format("[ODDWORKS][PrototypeRuntime] %s must be a Folder.", existing:GetFullName()))
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = childName
	folder.Parent = parent
	return folder
end

local function containsExecutableContent(instance: Instance): boolean
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			return true
		end
	end
	return false
end

local function cframesMatch(left: CFrame, right: CFrame): boolean
	local leftComponents = { left:GetComponents() }
	local rightComponents = { right:GetComponents() }
	for index = 1, #leftComponents do
		if math.abs(leftComponents[index] - rightComponents[index]) > TRANSFORM_EPSILON then
			return false
		end
	end
	return true
end

local function getPlayerContainerName(player: Player): string
	return string.format("Player_%d", player.UserId)
end

local function getConstructSelection(construct: PrototypeConstruct, role: string): ComponentSelection
	if role == "Head" then
		return construct.Head
	elseif role == "Arm" then
		return construct.Arm
	end
	return construct.Legs
end

local function buildFingerprint(construct: PrototypeConstruct): string
	return table.concat({
		construct.FrameId,
		construct.Head.ComponentId,
		construct.Head.Rarity,
		construct.Arm.ComponentId,
		construct.Arm.Rarity,
		construct.Legs.ComponentId,
		construct.Legs.Rarity,
	}, "|")
end

local function getConstructTemplatesFolder(): Folder?
	local assets = ServerStorage:FindFirstChild("ODDWORKSAssets")
	local constructs = if assets then assets:FindFirstChild("Constructs") else nil
	if not constructs or not constructs:IsA("Folder") then
		warnOnce(
			"ConstructsFolder",
			"[ODDWORKS][PrototypeRuntime] Missing ServerStorage.ODDWORKSAssets.Constructs folder."
		)
		return nil
	end

	clearWarning("ConstructsFolder")
	return constructs
end

local function validateFrameTemplate(candidate: Instance?): Model?
	if not candidate or not candidate:IsA("Model") then
		warnOnce(
			"FrameTemplate",
			string.format(
				"[ODDWORKS][PrototypeRuntime] Missing Model ServerStorage.ODDWORKSAssets.Constructs.%s.",
				FRAME_TEMPLATE_NAME
			)
		)
		return nil
	end
	if containsExecutableContent(candidate) then
		warnOnce("FrameTemplate", "[ODDWORKS][PrototypeRuntime] Frame template contains executable content and was rejected.")
		return nil
	end

	local rootPart = candidate:FindFirstChild(ROOT_PART_NAME)
	if not rootPart or not rootPart:IsA("BasePart") then
		warnOnce("FrameTemplate", "[ODDWORKS][PrototypeRuntime] Frame template is missing direct RootPart.")
		return nil
	end

	for _, roleContract in ipairs(ROLE_CONTRACTS) do
		local socket = rootPart:FindFirstChild(roleContract.SocketName)
		if not socket
			or not socket:IsA("Attachment")
			or socket.Parent ~= rootPart
			or not cframesMatch(socket.CFrame, roleContract.SocketCFrame)
		then
			warnOnce(
				"FrameTemplate",
				string.format("[ODDWORKS][PrototypeRuntime] Frame template has invalid %s.", roleContract.SocketName)
			)
			return nil
		end
	end

	local hasVisibleGeometry = false
	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart and descendant.Transparency < 1 then
			hasVisibleGeometry = true
			break
		end
	end
	if not hasVisibleGeometry then
		warnOnce("FrameTemplate", "[ODDWORKS][PrototypeRuntime] Frame template has no visible chassis geometry.")
		return nil
	end

	clearWarning("FrameTemplate")
	return candidate
end

local function validateModuleTemplate(candidate: Instance?, definition: ComponentDefinition): Model?
	local warningKey = string.format("ModuleTemplate:%s", definition.ComponentId)
	if not candidate or not candidate:IsA("Model") then
		warnOnce(
			warningKey,
			string.format(
				"[ODDWORKS][PrototypeRuntime] Missing module template Components.%s for %s.",
				definition.ArtModel,
				definition.ComponentId
			)
		)
		return nil
	end
	if containsExecutableContent(candidate) then
		warnOnce(
			warningKey,
			string.format("[ODDWORKS][PrototypeRuntime] Module template %s contains executable content.", definition.ArtModel)
		)
		return nil
	end

	local moduleRoot = candidate:FindFirstChild(MODULE_ROOT_NAME)
	local mountAttachment = if moduleRoot then moduleRoot:FindFirstChild(MOUNT_ATTACHMENT_NAME) else nil
	if not moduleRoot
		or not moduleRoot:IsA("BasePart")
		or not mountAttachment
		or not mountAttachment:IsA("Attachment")
		or mountAttachment.Parent ~= moduleRoot
		or not cframesMatch(mountAttachment.CFrame, CFrame.identity)
	then
		warnOnce(
			warningKey,
			string.format("[ODDWORKS][PrototypeRuntime] Module template %s has an invalid ModuleRoot/MountAttachment.", definition.ArtModel)
		)
		return nil
	end

	local hasVisibleGeometry = false
	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= moduleRoot and descendant.Transparency < 1 then
			hasVisibleGeometry = true
			break
		end
	end
	if not hasVisibleGeometry then
		warnOnce(
			warningKey,
			string.format("[ODDWORKS][PrototypeRuntime] Module template %s has no visible geometry.", definition.ArtModel)
		)
		return nil
	end

	clearWarning(warningKey)
	return candidate
end

local function resolveTemplates(construct: PrototypeConstruct): (Model?, { [string]: Model }?)
	if construct.FrameId ~= FRAME_ID then
		warnOnce(
			string.format("Frame:%s", construct.FrameId),
			string.format("[ODDWORKS][PrototypeRuntime] Unsupported frame %s.", construct.FrameId)
		)
		return nil, nil
	end

	local constructsFolder = getConstructTemplatesFolder()
	if not constructsFolder then
		return nil, nil
	end
	local frameTemplate = validateFrameTemplate(constructsFolder:FindFirstChild(FRAME_TEMPLATE_NAME))
	local componentsFolder = constructsFolder:FindFirstChild("Components")
	if not componentsFolder or not componentsFolder:IsA("Folder") then
		warnOnce("ComponentsFolder", "[ODDWORKS][PrototypeRuntime] Missing Constructs.Components template folder.")
		return nil, nil
	end
	clearWarning("ComponentsFolder")

	local moduleTemplates: { [string]: Model } = {}
	for _, roleContract in ipairs(ROLE_CONTRACTS) do
		local selection = getConstructSelection(construct, roleContract.Role)
		local definition = Components.GetDefinition(selection.ComponentId) :: ComponentDefinition?
		if not definition
			or definition.Slot ~= roleContract.Role
			or not definition.CompatibleFrames[FRAME_ID]
			or not Components.IsValidRarity(selection.Rarity)
		then
			warnOnce(
				string.format("Selection:%s", roleContract.Role),
				string.format("[ODDWORKS][PrototypeRuntime] Invalid authoritative %s selection.", roleContract.Role)
			)
			return nil, nil
		end
		clearWarning(string.format("Selection:%s", roleContract.Role))

		local template = validateModuleTemplate(componentsFolder:FindFirstChild(definition.ArtModel), definition)
		if not template then
			return nil, nil
		end
		moduleTemplates[roleContract.Role] = template
	end

	return frameTemplate, moduleTemplates
end

local function getDisplayMarker(plot: BasePart): (CFrame?, string?)
	local marker = plot:FindFirstChild(DISPLAY_MARKER_NAME)
	if marker and marker:IsA("BasePart") then
		return marker.CFrame, plot.Name
	elseif marker and marker:IsA("Attachment") then
		return marker.WorldCFrame, plot.Name
	end

	warnOnce(
		string.format("Marker:%s", plot.Name),
		string.format("[ODDWORKS][PrototypeRuntime] %s is missing %s.", plot:GetFullName(), DISPLAY_MARKER_NAME)
	)
	return nil, nil
end

local function getTargetRootCFrame(markerCFrame: CFrame): CFrame
	-- The marker is the standing surface. The frozen frame root is exactly three
	-- studs above it because the root-local ground plane is Y = -3.
	return markerCFrame * CFrame.new(0, ROOT_GROUND_OFFSET, 0)
end

local function setInertPartPhysics(part: BasePart, anchored: boolean)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = part.Transparency < 1
end

local function weldVisibleGeometry(model: Model, rootPart: BasePart)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart then
			setInertPartPhysics(descendant, false)
			local weld = Instance.new("WeldConstraint")
			weld.Name = string.format("%sWeld", descendant.Name)
			weld.Part0 = rootPart
			weld.Part1 = descendant
			weld.Parent = rootPart
		end
	end
end

local function buildRuntimeModel(
	player: Player,
	construct: PrototypeConstruct,
	frameTemplate: Model,
	moduleTemplates: { [string]: Model },
	targetRootCFrame: CFrame,
	plotId: string
): Model?
	local frame = frameTemplate:Clone()
	frame.Name = CONSTRUCT_MODEL_NAME

	local rootPart = frame:FindFirstChild(ROOT_PART_NAME)
	if not rootPart or not rootPart:IsA("BasePart") then
		frame:Destroy()
		return nil
	end
	frame.PrimaryPart = rootPart
	setInertPartPhysics(rootPart, true)
	frame:PivotTo(targetRootCFrame)
	weldVisibleGeometry(frame, rootPart)

	for _, roleContract in ipairs(ROLE_CONTRACTS) do
		local selection = getConstructSelection(construct, roleContract.Role)
		local socket = rootPart:FindFirstChild(roleContract.SocketName)
		local moduleTemplate = moduleTemplates[roleContract.Role]
		if not socket or not socket:IsA("Attachment") or not moduleTemplate then
			frame:Destroy()
			return nil
		end

		local module = moduleTemplate:Clone()
		module.Name = roleContract.Role
		local moduleRoot = module:FindFirstChild(MODULE_ROOT_NAME)
		local mountAttachment = if moduleRoot then moduleRoot:FindFirstChild(MOUNT_ATTACHMENT_NAME) else nil
		if not moduleRoot
			or not moduleRoot:IsA("BasePart")
			or not mountAttachment
			or not mountAttachment:IsA("Attachment")
		then
			module:Destroy()
			frame:Destroy()
			return nil
		end

		module.PrimaryPart = moduleRoot
		setInertPartPhysics(moduleRoot, false)
		module:PivotTo(rootPart.CFrame * socket.CFrame * mountAttachment.CFrame:Inverse())
		weldVisibleGeometry(module, moduleRoot)
		module:SetAttribute("Role", roleContract.Role)
		module:SetAttribute("ComponentId", selection.ComponentId)
		module:SetAttribute("Rarity", selection.Rarity)
		module.Parent = frame

		local motor = Instance.new("Motor6D")
		motor.Name = roleContract.JointName
		motor.Part0 = rootPart
		motor.Part1 = moduleRoot
		motor.C0 = socket.CFrame
		motor.C1 = mountAttachment.CFrame
		motor.Parent = rootPart
	end

	frame:SetAttribute("OwnerUserId", player.UserId)
	frame:SetAttribute("FrameId", construct.FrameId)
	frame:SetAttribute("PlotId", plotId)
	frame:SetAttribute("ConstructFingerprint", buildFingerprint(construct))
	return frame
end

local function validateRuntimeModule(
	model: Model,
	rootPart: BasePart,
	construct: PrototypeConstruct,
	roleContract: RoleContract
): boolean
	local selection = getConstructSelection(construct, roleContract.Role)
	local module = model:FindFirstChild(roleContract.Role)
	if not module
		or not module:IsA("Model")
		or module:GetAttribute("Role") ~= roleContract.Role
		or module:GetAttribute("ComponentId") ~= selection.ComponentId
		or module:GetAttribute("Rarity") ~= selection.Rarity
	then
		return false
	end

	local moduleRoot = module:FindFirstChild(MODULE_ROOT_NAME)
	local mountAttachment = if moduleRoot then moduleRoot:FindFirstChild(MOUNT_ATTACHMENT_NAME) else nil
	local socket = rootPart:FindFirstChild(roleContract.SocketName)
	local joint = rootPart:FindFirstChild(roleContract.JointName)
	if not moduleRoot
		or not moduleRoot:IsA("BasePart")
		or not mountAttachment
		or not mountAttachment:IsA("Attachment")
		or not socket
		or not socket:IsA("Attachment")
		or not joint
		or not joint:IsA("Motor6D")
	then
		return false
	end
	if not cframesMatch(socket.CFrame, roleContract.SocketCFrame)
		or not cframesMatch(mountAttachment.CFrame, CFrame.identity)
		or joint.Part0 ~= rootPart
		or joint.Part1 ~= moduleRoot
		or not cframesMatch(joint.C0, socket.CFrame)
		or not cframesMatch(joint.C1, mountAttachment.CFrame)
	then
		return false
	end

	local part0Mount = rootPart.CFrame * joint.C0
	local part1Mount = moduleRoot.CFrame * joint.C1
	if not cframesMatch(part0Mount, part1Mount) then
		return false
	end

	for _, descendant in ipairs(module:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= moduleRoot and descendant.Transparency < 1 then
			return true
		end
	end
	return false
end

local function isRuntimeModelValid(
	player: Player,
	model: Model,
	construct: PrototypeConstruct,
	targetRootCFrame: CFrame,
	plotId: string
): boolean
	if model.Name ~= CONSTRUCT_MODEL_NAME
		or model:GetAttribute("OwnerUserId") ~= player.UserId
		or model:GetAttribute("FrameId") ~= construct.FrameId
		or model:GetAttribute("PlotId") ~= plotId
		or model:GetAttribute("ConstructFingerprint") ~= buildFingerprint(construct)
	then
		return false
	end

	local rootPart = model:FindFirstChild(ROOT_PART_NAME)
	if not rootPart
		or not rootPart:IsA("BasePart")
		or model.PrimaryPart ~= rootPart
		or not rootPart.Anchored
		or not cframesMatch(rootPart.CFrame, targetRootCFrame)
	then
		return false
	end

	for _, roleContract in ipairs(ROLE_CONTRACTS) do
		if not validateRuntimeModule(model, rootPart, construct, roleContract) then
			return false
		end
	end
	return true
end

local function disconnectConnection(map: { [Player]: RBXScriptConnection }, player: Player)
	local connection = map[player]
	if connection then
		connection:Disconnect()
		map[player] = nil
	end
end

local function getExistingPlayerContainer(player: Player): Folder?
	local runtimeFolder = runtimeConstructsFolder
	if not runtimeFolder then
		return nil
	end

	local existing = runtimeFolder:FindFirstChild(getPlayerContainerName(player))
	if existing and existing:IsA("Folder") then
		return existing
	end
	return nil
end

local function removeRuntime(player: Player, destroyContainer: boolean)
	local existingContainer = getExistingPlayerContainer(player)
	if not existingContainer and not modelConnections[player] and not containerConnections[player] then
		return
	end

	recoveryGenerations[player] = (recoveryGenerations[player] or 0) + 1
	suppressRecovery[player] = true
	disconnectConnection(modelConnections, player)
	if destroyContainer then
		disconnectConnection(containerConnections, player)
	end

	local container = existingContainer
	if container then
		if destroyContainer then
			container:Destroy()
		else
			for _, child in ipairs(container:GetChildren()) do
				child:Destroy()
			end
		end
	end
	suppressRecovery[player] = nil
end

local function queueReconcile(player: Player)
	if pendingReconciliations[player] then
		return
	end
	pendingReconciliations[player] = true
	task.defer(function()
		pendingReconciliations[player] = nil
		PrototypeConstructRuntimeService.Reconcile(player)
	end)
end

local function watchPlayerContainer(player: Player, container: Folder)
	disconnectConnection(containerConnections, player)
	local generation = recoveryGenerations[player] or 0
	containerConnections[player] = container.ChildRemoved:Connect(function(child: Instance)
		if suppressRecovery[player] or not child:IsA("Model") then
			return
		end
		task.defer(function()
			if not suppressRecovery[player] and recoveryGenerations[player] == generation then
				queueReconcile(player)
			end
		end)
	end)
end

local function getOrCreatePlayerContainer(player: Player): Folder?
	local runtimeFolder = runtimeConstructsFolder
	if not runtimeFolder then
		return nil
	end

	local containerName = getPlayerContainerName(player)
	local existing = runtimeFolder:FindFirstChild(containerName)
	if existing then
		if not existing:IsA("Folder") then
			warn(string.format("[ODDWORKS][PrototypeRuntime] %s must be a Folder.", existing:GetFullName()))
			return nil
		end
		if not containerConnections[player] then
			watchPlayerContainer(player, existing)
		end
		return existing
	end

	local container = Instance.new("Folder")
	container.Name = containerName
	container:SetAttribute("OwnerUserId", player.UserId)
	container.Parent = runtimeFolder
	watchPlayerContainer(player, container)
	return container
end

local function watchRuntimeModel(player: Player, model: Model)
	disconnectConnection(modelConnections, player)
	local generation = recoveryGenerations[player] or 0
	modelConnections[player] = model.DescendantRemoving:Connect(function()
		if suppressRecovery[player] then
			return
		end
		task.defer(function()
			if not suppressRecovery[player] and recoveryGenerations[player] == generation then
				queueReconcile(player)
			end
		end)
	end)
end

function PrototypeConstructRuntimeService.Reconcile(player: Player): boolean
	if not started then
		return false
	end

	local snapshot = ModularPrototypeStateService.GetSnapshot(player)
	local construct = if snapshot then snapshot.PrototypeConstruct else nil
	if player.Parent ~= Players or not construct then
		removeRuntime(player, true)
		return true
	end

	local plot = WorkshopService.GetAssignedPlot(player)
	if not plot then
		removeRuntime(player, true)
		return false
	end
	local markerCFrame, plotId = getDisplayMarker(plot)
	if not markerCFrame or not plotId then
		removeRuntime(player, true)
		return false
	end
	clearWarning(string.format("Marker:%s", plot.Name))

	local frameTemplate, moduleTemplates = resolveTemplates(construct)
	if not frameTemplate or not moduleTemplates then
		-- A content failure cannot be allowed to leave a stale model that implies
		-- a different authoritative build. Inventory and Construct state stay intact.
		removeRuntime(player, false)
		return false
	end

	local container = getOrCreatePlayerContainer(player)
	if not container then
		return false
	end
	local targetRootCFrame = getTargetRootCFrame(markerCFrame)
	local candidate: Model? = nil
	local modelCount = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			modelCount += 1
			candidate = child
		end
	end
	if modelCount == 1 and candidate and isRuntimeModelValid(player, candidate, construct, targetRootCFrame, plotId) then
		if not modelConnections[player] then
			watchRuntimeModel(player, candidate)
		end
		return true
	end

	recoveryGenerations[player] = (recoveryGenerations[player] or 0) + 1
	suppressRecovery[player] = true
	disconnectConnection(modelConnections, player)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end

	local rebuilt = buildRuntimeModel(player, construct, frameTemplate, moduleTemplates, targetRootCFrame, plotId)
	if rebuilt then
		rebuilt.Parent = container
	end
	suppressRecovery[player] = nil
	watchPlayerContainer(player, container)
	if not rebuilt then
		warn(string.format("[ODDWORKS][PrototypeRuntime] Failed to build runtime Construct for %s.", player.Name))
		return false
	end

	watchRuntimeModel(player, rebuilt)
	print(string.format("[ODDWORKS][PrototypeRuntime] Reconstructed %s for %s in %s.", FRAME_ID, player.Name, plotId))
	return true
end

local function cleanupPlayer(player: Player)
	pendingReconciliations[player] = nil
	removeRuntime(player, true)
	recoveryGenerations[player] = nil
end

function PrototypeConstructRuntimeService.Start()
	if started then
		return
	end
	started = true

	local runtimeRoot = getOrCreateFolder(Workspace, RUNTIME_ROOT_NAME)
	if not runtimeRoot then
		warn("[ODDWORKS][PrototypeRuntime] Runtime root unavailable; service cannot reconstruct Constructs.")
		return
	end
	runtimeConstructsFolder = getOrCreateFolder(runtimeRoot, RUNTIME_FOLDER_NAME)
	if not runtimeConstructsFolder then
		warn("[ODDWORKS][PrototypeRuntime] Runtime Constructs folder unavailable.")
		return
	end

	ModularPrototypeStateService.ObserveStateChanged(queueReconcile)
	ModularPrototypeStateService.ObserveStateRemoved(cleanupPlayer)
	PlayerStateService.ObserveStateChanged(queueReconcile)
	PlayerStateService.ObserveStateRemoved(cleanupPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		queueReconcile(player)
	end

	-- One bounded audit catches property corruption and deleted runtime folders
	-- without creating a heartbeat or loop per Construct.
	task.spawn(function()
		while started do
			task.wait(AUDIT_INTERVAL_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				if ModularPrototypeStateService.HasState(player) then
					queueReconcile(player)
				end
			end
		end
	end)

	print("[ODDWORKS][PrototypeRuntime] Service started; physical Constructs are derived and disposable.")
end

return PrototypeConstructRuntimeService
