--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][OddlingDisplay] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

local workshopLevelsModule = Config:WaitForChild("WorkshopLevels")
if not workshopLevelsModule:IsA("ModuleScript") then
	error("[ODDWORKS][OddlingDisplay] Server.Config.WorkshopLevels must be a ModuleScript.")
end

local WorkshopLevels = require(workshopLevelsModule)

type DisplaySlot = {
	Name: string,
	WorldCFrame: CFrame,
}

type WorkshopLevelDefinition = {
	Level: number,
	DisplayCapacity: number,
	UpgradeCost: number?,
	NextLevel: number?,
}

local TEMPLATE_PATH = "ServerStorage.ODDWORKSAssets.Oddlings.Toastmarshal_Common"
local TEMPLATE_NAME = "Toastmarshal_Common"
local SPECIES_ID = "Toastmarshal"
local IDLE_ANIMATION_ID = "rbxassetid://105040634265875"
local DISPLAY_SLOTS_FOLDER_NAME = "OddlingDisplaySlots"
local RUNTIME_FOLDER_NAME = "ODDWORKSRuntime"
local DISPLAYS_FOLDER_NAME = "OddlingDisplays"

local OddlingDisplayService = {}

-- Runtime display bookkeeping stays server-only. Workspace clones are presentation
-- derived from PlayerState; neither their attributes nor their existence owns gameplay truth.
local runtimeDisplaysFolder: Folder? = nil
local cachedTemplate: Model? = nil
local pendingReconciliations: { [Player]: boolean } = {}
local capacityWarningKeys: { [Player]: string } = {}
local missingSlotWarnings: { [string]: boolean } = {}
local warnedMissingTemplate = false
local started = false

-- Creates only the runtime organization folders needed for temporary displays.
-- Persistent workshop geometry remains authored through Studio/Rojo under ODDWORKSWorld.
local function getOrCreateFolder(parent: Instance, childName: string): Folder?
	local existing = parent:FindFirstChild(childName)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end

		warn(string.format("[ODDWORKS][OddlingDisplay] %s must be a Folder.", existing:GetFullName()))
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = childName
	folder.Parent = parent
	return folder
end

-- Confirms every physical part is connected to RootPart through imported Motor6Ds.
-- Anchoring only RootPart is safe only when the rest of the rig belongs to that assembly.
local function hasConnectedRigAssembly(model: Model, rootPart: BasePart): boolean
	local adjacency: { [BasePart]: { BasePart } } = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part1 and part0:IsDescendantOf(model) and part1:IsDescendantOf(model) then
				adjacency[part0] = adjacency[part0] or {}
				adjacency[part1] = adjacency[part1] or {}
				table.insert(adjacency[part0], part1)
				table.insert(adjacency[part1], part0)
			end
		end
	end

	local visited: { [BasePart]: boolean } = {
		[rootPart] = true,
	}
	local queue: { BasePart } = { rootPart }
	local queueIndex = 1

	while queueIndex <= #queue do
		local current = queue[queueIndex]
		queueIndex += 1

		for _, connectedPart in ipairs(adjacency[current] or {}) do
			if not visited[connectedPart] then
				visited[connectedPart] = true
				table.insert(queue, connectedPart)
			end
		end
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and not visited[descendant] then
			return false
		end
	end

	return true
end

-- Validates the imported production contract without repairing or restructuring the rig.
-- A malformed visual template must fail independently from authoritative ownership.
local function validateTemplate(candidate: Instance): Model?
	if not candidate:IsA("Model") then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s must be a Model.", TEMPLATE_PATH))
		return nil
	end

	local rootPart = candidate:FindFirstChild("RootPart", true)
	if not rootPart or not rootPart:IsA("BasePart") then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s is missing a BasePart named RootPart.", TEMPLATE_PATH))
		return nil
	end

	if not candidate:FindFirstChildWhichIsA("MeshPart", true) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s contains no production MeshParts.", TEMPLATE_PATH))
		return nil
	end

	if not candidate:FindFirstChildWhichIsA("Bone", true) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s contains no Bone hierarchy.", TEMPLATE_PATH))
		return nil
	end

	if not candidate:FindFirstChildWhichIsA("AnimationController", true) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s is missing its AnimationController.", TEMPLATE_PATH))
		return nil
	end

	if not hasConnectedRigAssembly(candidate, rootPart) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s has BaseParts disconnected from RootPart.", TEMPLATE_PATH))
		return nil
	end

	return candidate
end

-- Finds the Studio-imported server template by its exact contract path.
-- No cloud fallback is used because arbitrary fetched assets are not trusted production content.
local function discoverTemplate(): Model?
	if cachedTemplate and cachedTemplate.Parent then
		return cachedTemplate
	end

	cachedTemplate = nil

	local assets = ServerStorage:FindFirstChild("ODDWORKSAssets")
	local oddlings = if assets then assets:FindFirstChild("Oddlings") else nil
	local candidate = if oddlings then oddlings:FindFirstChild(TEMPLATE_NAME) else nil

	if not candidate then
		if not warnedMissingTemplate then
			warn(string.format("[ODDWORKS][OddlingDisplay] Missing runtime template: %s", TEMPLATE_PATH))
			warnedMissingTemplate = true
		end
		return nil
	end

	local template = validateTemplate(candidate)
	if not template then
		return nil
	end

	cachedTemplate = template
	warnedMissingTemplate = false
	print(string.format("[ODDWORKS][OddlingDisplay] Template ready: %s", TEMPLATE_PATH))
	return template
end

-- Reads authored display contacts in stable name order.
-- Slots are server-known world objects, so clients never provide positions or capacity.
local function discoverDisplaySlots(plot: BasePart, plotId: string): { DisplaySlot }
	local slotsFolder = plot:FindFirstChild(DISPLAY_SLOTS_FOLDER_NAME)
	if not slotsFolder or not slotsFolder:IsA("Folder") then
		if not missingSlotWarnings[plotId] then
			warn(
				string.format(
					"[ODDWORKS][OddlingDisplay] %s is missing a Folder named %s.",
					plot:GetFullName(),
					DISPLAY_SLOTS_FOLDER_NAME
				)
			)
			missingSlotWarnings[plotId] = true
		end
		return {}
	end

	local slots: { DisplaySlot } = {}
	for _, child in ipairs(slotsFolder:GetChildren()) do
		if string.match(child.Name, "^Slot%d+$") then
			if child:IsA("Attachment") then
				table.insert(slots, {
					Name = child.Name,
					WorldCFrame = child.WorldCFrame,
				})
			elseif child:IsA("BasePart") then
				table.insert(slots, {
					Name = child.Name,
					WorldCFrame = child.CFrame,
				})
			end
		end
	end

	table.sort(slots, function(left: DisplaySlot, right: DisplaySlot): boolean
		return left.Name < right.Name
	end)

	missingSlotWarnings[plotId] = nil
	return slots
end

-- Uses only the visible production meshes to find the intended ground contact.
-- The imported invisible RootPart extends below Toastmarshal's feet and would create a false air gap.
local function getVisibleMeshBottomY(model: Model): number?
	local bottomY: number? = nil

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("MeshPart") and descendant.Transparency < 1 then
			local halfSize = descendant.Size / 2
			for xSign = -1, 1, 2 do
				for ySign = -1, 1, 2 do
					for zSign = -1, 1, 2 do
						local corner = descendant.CFrame:PointToWorldSpace(
							Vector3.new(halfSize.X * xSign, halfSize.Y * ySign, halfSize.Z * zSign)
						)
						bottomY = if bottomY then math.min(bottomY, corner.Y) else corner.Y
					end
				end
			end
		end
	end

	return bottomY
end

-- Moves the whole imported Model through its pivot, then grounds visible mesh bounds
-- exactly to the authored slot contact plane without a guessed vertical offset.
local function placeDisplayAtSlot(model: Model, slot: DisplaySlot): boolean
	model:PivotTo(slot.WorldCFrame)

	local meshBottomY = getVisibleMeshBottomY(model)
	if not meshBottomY then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s has no visible mesh bounds for placement.", model.Name))
		return false
	end

	local verticalCorrection = slot.WorldCFrame.Position.Y - meshBottomY
	model:PivotTo(model:GetPivot() + Vector3.new(0, verticalCorrection, 0))
	return true
end

-- Keeps the imported rig stationary without freezing every animated mesh part.
-- RootPart anchors the Motor6D assembly; all display parts are non-collidable presentation.
local function configureDisplayPhysics(model: Model): boolean
	local rootPart = model:FindFirstChild("RootPart", true)
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false

			if descendant == rootPart then
				descendant.Anchored = true
			else
				descendant.Anchored = false
				descendant.Massless = true
			end
		end
	end

	return true
end

-- Starts the published production Idle on the server-created display.
-- The server owns the animation ID; no client remote can choose or trigger animation playback.
local function startIdleAnimation(model: Model): boolean
	if model:GetAttribute("IdleAnimationStarted") == true then
		return true
	end

	local controllerInstance = model:FindFirstChildWhichIsA("AnimationController", true)
	if not controllerInstance or not controllerInstance:IsA("AnimationController") then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s cannot play Idle: AnimationController missing.", model.Name))
		return false
	end

	local animatorInstance = controllerInstance:FindFirstChildWhichIsA("Animator")
	local animator: Animator
	if animatorInstance and animatorInstance:IsA("Animator") then
		animator = animatorInstance
	else
		animator = Instance.new("Animator")
		animator.Parent = controllerInstance
	end

	local animation = Instance.new("Animation")
	animation.Name = "Idle"
	animation.AnimationId = IDLE_ANIMATION_ID
	animation.Parent = controllerInstance

	local didStart, trackOrError = pcall(function(): AnimationTrack
		local track = animator:LoadAnimation(animation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play(0.1, 1, 1)
		return track
	end)
	if not didStart then
		animation:Destroy()
		warn(string.format("[ODDWORKS][OddlingDisplay] %s failed to start Idle: %s", model.Name, tostring(trackOrError)))
		return false
	end

	model:SetAttribute("IdleAnimationStarted", true)
	return true
end

-- Names each player's temporary display container by public, stable UserId.
-- Separate containers prevent one player's reconciliation from touching another player's models.
local function getPlayerContainerName(player: Player): string
	return string.format("Player_%d", player.UserId)
end

-- Returns an existing player-isolated container or creates one only when a display is needed.
local function getOrCreatePlayerContainer(player: Player): Folder?
	local displaysFolder = runtimeDisplaysFolder
	if not displaysFolder then
		return nil
	end

	local containerName = getPlayerContainerName(player)
	local existing = displaysFolder:FindFirstChild(containerName)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end

		warn(string.format("[ODDWORKS][OddlingDisplay] Runtime container %s must be a Folder.", containerName))
		return nil
	end

	local container = Instance.new("Folder")
	container.Name = containerName
	container:SetAttribute("OwnerUserId", player.UserId)
	container.Parent = displaysFolder
	return container
end

-- Removes all temporary physical representation for one player.
-- Authoritative ownership remains in PlayerStateService and is never changed by visual cleanup.
local function cleanupPlayerDisplays(player: Player)
	local displaysFolder = runtimeDisplaysFolder
	if not displaysFolder then
		return
	end

	local container = displaysFolder:FindFirstChild(getPlayerContainerName(player))
	if container then
		container:Destroy()
	end
end

-- Reads this service's existing Toastmarshal clones by deterministic display index.
-- Duplicate/malformed indexes are removed because this runtime folder is derived presentation only.
local function collectExistingDisplays(container: Folder): { [number]: Model }
	local displaysByIndex: { [number]: Model } = {}

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OddlingSpeciesId") == SPECIES_ID then
			local displayIndex = child:GetAttribute("DisplayIndex")
			if typeof(displayIndex) == "number" and displayIndex > 0 and math.floor(displayIndex) == displayIndex then
				if displaysByIndex[displayIndex] then
					child:Destroy()
				else
					displaysByIndex[displayIndex] = child
				end
			else
				child:Destroy()
			end
		end
	end

	return displaysByIndex
end

-- Clones one validated production template into a deterministic slot.
-- Spawn failure affects presentation only; it never refunds, decrements, or rewrites ownership.
local function spawnDisplay(player: Player, plotId: string, displayIndex: number, slot: DisplaySlot, container: Folder): Model?
	local template = discoverTemplate()
	if not template then
		return nil
	end

	local clone = template:Clone()
	clone.Name = string.format("Toastmarshal_%03d", displayIndex)
	clone:SetAttribute("OddlingSpeciesId", SPECIES_ID)
	clone:SetAttribute("DisplayIndex", displayIndex)
	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:SetAttribute("AssignedPlotId", plotId)
	clone.Parent = container

	if not configureDisplayPhysics(clone) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s has no usable RootPart.", clone.Name))
		clone:Destroy()
		return nil
	end

	if not placeDisplayAtSlot(clone, slot) then
		clone:Destroy()
		return nil
	end

	startIdleAnimation(clone)
	return clone
end

-- Reconciles authoritative ownership against physical display count and slot capacity.
-- This recoverable model can recreate missing visuals without replaying the craft transaction.
local function reconcilePlayer(player: Player)
	if player.Parent ~= Players then
		cleanupPlayerDisplays(player)
		return
	end

	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot or not snapshot.AssignedPlotId then
		cleanupPlayerDisplays(player)
		return
	end

	local plotId = snapshot.AssignedPlotId
	if WorkshopService.GetAssignedPlotId(player) ~= plotId then
		cleanupPlayerDisplays(player)
		return
	end

	local plot = WorkshopService.GetAssignedPlot(player)
	if not plot then
		cleanupPlayerDisplays(player)
		return
	end

	local ownedCount = snapshot.OwnedOddlings[SPECIES_ID] or 0
	if ownedCount <= 0 then
		cleanupPlayerDisplays(player)
		capacityWarningKeys[player] = nil
		return
	end

	local slots = discoverDisplaySlots(plot, plotId)
	local levelDefinition = WorkshopLevels.GetDefinition(snapshot.WorkshopLevel) :: WorkshopLevelDefinition?
	if
		not levelDefinition
		or levelDefinition.DisplayCapacity < 0
		or math.floor(levelDefinition.DisplayCapacity) ~= levelDefinition.DisplayCapacity
	then
		cleanupPlayerDisplays(player)
		warn(string.format("[ODDWORKS][OddlingDisplay] Missing valid capacity for Workshop Level %d.", snapshot.WorkshopLevel))
		return
	end

	local activeCapacity = math.min(#slots, levelDefinition.DisplayCapacity)
	local displayTarget = math.min(ownedCount, activeCapacity)
	local warningKey = string.format("%s:%d:%d:%d", plotId, snapshot.WorkshopLevel, ownedCount, activeCapacity)
	if ownedCount > activeCapacity then
		if capacityWarningKeys[player] ~= warningKey then
			warn(
				string.format(
					"[ODDWORKS][OddlingDisplay] %s owns %d Toastmarshals but Workshop Level %d activates %d of %d authored slots; ownership is preserved.",
					player.Name,
					ownedCount,
					snapshot.WorkshopLevel,
					activeCapacity,
					#slots
				)
			)
			capacityWarningKeys[player] = warningKey
		end
	else
		capacityWarningKeys[player] = nil
	end

	if displayTarget == 0 then
		cleanupPlayerDisplays(player)
		return
	end

	local container = getOrCreatePlayerContainer(player)
	if not container then
		return
	end

	local existingDisplays = collectExistingDisplays(container)
	local spawnedCount = 0
	local removedCount = 0

	local excessDisplayIndexes: { number } = {}
	for displayIndex in pairs(existingDisplays) do
		if displayIndex > displayTarget then
			table.insert(excessDisplayIndexes, displayIndex)
		end
	end

	for _, displayIndex in ipairs(excessDisplayIndexes) do
		existingDisplays[displayIndex]:Destroy()
		existingDisplays[displayIndex] = nil
		removedCount += 1
	end

	for displayIndex = 1, displayTarget do
		local slot = slots[displayIndex]
		local display = existingDisplays[displayIndex]

		if display then
			display:SetAttribute("AssignedPlotId", plotId)
			if placeDisplayAtSlot(display, slot) then
				startIdleAnimation(display)
			end
		else
			local spawned = spawnDisplay(player, plotId, displayIndex, slot, container)
			if spawned then
				spawnedCount += 1
			end
		end
	end

	if spawnedCount > 0 or removedCount > 0 then
		print(
			string.format(
				"[ODDWORKS][OddlingDisplay] Reconciled %s on %s (target: %d, spawned: %d, removed: %d).",
				player.Name,
				plotId,
				displayTarget,
				spawnedCount,
				removedCount
			)
		)
	end
end

-- Coalesces multiple synchronous state notifications from one craft transaction.
-- Spending Scrap and recording ownership may both fire, but representation needs one final-state reconciliation.
local function scheduleReconciliation(player: Player)
	if pendingReconciliations[player] then
		return
	end

	pendingReconciliations[player] = true
	task.defer(function()
		pendingReconciliations[player] = nil
		reconcilePlayer(player)
	end)
end

-- Starts the downstream display layer after PlayerState and WorkshopService are ready.
-- No client request is registered: server state changes are the only spawn trigger.
function OddlingDisplayService.Start()
	if started then
		return
	end

	started = true

	local runtimeRoot = getOrCreateFolder(Workspace, RUNTIME_FOLDER_NAME)
	if not runtimeRoot then
		warn("[ODDWORKS][OddlingDisplay] Service could not create its runtime root.")
		return
	end

	runtimeDisplaysFolder = getOrCreateFolder(runtimeRoot, DISPLAYS_FOLDER_NAME)
	if not runtimeDisplaysFolder then
		warn("[ODDWORKS][OddlingDisplay] Service could not create its display folder.")
		return
	end

	discoverTemplate()
	PlayerStateService.ObserveStateChanged(scheduleReconciliation)

	Players.PlayerRemoving:Connect(function(player: Player)
		pendingReconciliations[player] = nil
		capacityWarningKeys[player] = nil
		cleanupPlayerDisplays(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		scheduleReconciliation(player)
	end

	print("[ODDWORKS][OddlingDisplay] Service started.")
end

-- Counts only this service's valid server-created displays for the player's current plot.
-- Callers receive a number rather than mutable display bookkeeping or Workspace authority.
function OddlingDisplayService.GetDisplayedCount(player: Player, speciesId: string): number
	if not started or speciesId ~= SPECIES_ID then
		return 0
	end

	local assignedPlotId = WorkshopService.GetAssignedPlotId(player)
	if not assignedPlotId or not WorkshopService.GetAssignedPlot(player) then
		return 0
	end

	local displaysFolder = runtimeDisplaysFolder
	if not displaysFolder then
		return 0
	end

	local container = displaysFolder:FindFirstChild(getPlayerContainerName(player))
	if not container or not container:IsA("Folder") then
		return 0
	end

	local displayedIndexes: { [number]: boolean } = {}
	for _, child in ipairs(container:GetChildren()) do
		if
			child:IsA("Model")
			and child:GetAttribute("OddlingSpeciesId") == speciesId
			and child:GetAttribute("OwnerUserId") == player.UserId
			and child:GetAttribute("AssignedPlotId") == assignedPlotId
		then
			local displayIndex = child:GetAttribute("DisplayIndex")
			if
				typeof(displayIndex) == "number"
				and displayIndex > 0
				and math.floor(displayIndex) == displayIndex
			then
				displayedIndexes[displayIndex] = true
			end
		end
	end

	local displayedCount = 0
	for _ in pairs(displayedIndexes) do
		displayedCount += 1
	end

	return displayedCount
end

return OddlingDisplayService
