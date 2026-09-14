--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][OddlingDisplay] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local WorkshopService = require(Services:WaitForChild("WorkshopService"))

local oddlingsModule = Config:WaitForChild("Oddlings")
if not oddlingsModule:IsA("ModuleScript") then
	error("[ODDWORKS][OddlingDisplay] Server.Config.Oddlings must be a ModuleScript.")
end

local workshopLevelsModule = Config:WaitForChild("WorkshopLevels")
if not workshopLevelsModule:IsA("ModuleScript") then
	error("[ODDWORKS][OddlingDisplay] Server.Config.WorkshopLevels must be a ModuleScript.")
end

local Oddlings = require(oddlingsModule)
local WorkshopLevels = require(workshopLevelsModule)

type OddlingDefinition = {
	SpeciesId: string,
	TemplateName: string,
	RootPartName: string,
	AnchorAllParts: boolean,
	IdleAnimationAssetId: string?,
	HypePerInterval: number,
	HypeIntervalSeconds: number,
}

type WorkshopLevelDefinition = {
	Level: number,
	DisplayCapacity: number,
	UpgradeCost: number?,
	NextLevel: number?,
}

type DisplaySlot = {
	Name: string,
	WorldCFrame: CFrame,
}

type DisplayAllocation = {
	SlotIndex: number,
	SpeciesId: string,
	SpeciesDisplayIndex: number,
}

local DISPLAY_SLOTS_FOLDER_NAME = "OddlingDisplaySlots"
local RUNTIME_FOLDER_NAME = "ODDWORKSRuntime"
local DISPLAYS_FOLDER_NAME = "OddlingDisplays"

local OddlingDisplayService = {}

-- Template and display bookkeeping stays private on the server. Physical clones
-- are disposable presentation derived from PlayerState and workshop state.
local runtimeDisplaysFolder: Folder? = nil
local cachedTemplates: { [string]: Model } = {}
local pendingReconciliations: { [Player]: boolean } = {}
local capacityWarningKeys: { [Player]: string } = {}
local missingSlotWarnings: { [string]: boolean } = {}
local missingTemplateWarnings: { [string]: boolean } = {}
local started = false

-- Creates only temporary runtime organization folders. Persistent plot geometry
-- remains authored through the repository-backed world hierarchy.
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

-- Confirms each animated rig part is connected to its configured root by Motor6Ds.
-- Anchoring only that root is safe only when every other part belongs to the assembly.
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

	local visited: { [BasePart]: boolean } = { [rootPart] = true }
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

-- Rejects executable content from runtime art templates. The prototype is visual
-- content only and must never smuggle third-party behavior into the live server.
local function containsExecutableContent(model: Model): boolean
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			return true
		end
	end

	return false
end

-- Validates the minimum contract for either an animated production rig or a
-- static prototype without silently repairing artistic hierarchy.
local function validateTemplate(candidate: Instance, definition: OddlingDefinition): Model?
	local templatePath = string.format("ServerStorage.ODDWORKSAssets.Oddlings.%s", definition.TemplateName)
	if not candidate:IsA("Model") then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s must be a Model.", templatePath))
		return nil
	end

	if containsExecutableContent(candidate) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s contains executable scripts and was rejected.", templatePath))
		return nil
	end

	local rootPart = candidate:FindFirstChild(definition.RootPartName, true)
	if not rootPart or not rootPart:IsA("BasePart") then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s is missing BasePart %s.", templatePath, definition.RootPartName))
		return nil
	end

	if not candidate:FindFirstChildWhichIsA("BasePart", true) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s contains no visible BaseParts.", templatePath))
		return nil
	end

	if definition.IdleAnimationAssetId then
		if not candidate:FindFirstChildWhichIsA("MeshPart", true) then
			warn(string.format("[ODDWORKS][OddlingDisplay] %s contains no production MeshParts.", templatePath))
			return nil
		end

		if not candidate:FindFirstChildWhichIsA("Bone", true) then
			warn(string.format("[ODDWORKS][OddlingDisplay] %s contains no Bone hierarchy.", templatePath))
			return nil
		end

		if not candidate:FindFirstChildWhichIsA("AnimationController", true) then
			warn(string.format("[ODDWORKS][OddlingDisplay] %s is missing its AnimationController.", templatePath))
			return nil
		end

		if not hasConnectedRigAssembly(candidate, rootPart) then
			warn(string.format("[ODDWORKS][OddlingDisplay] %s has parts disconnected from its root.", templatePath))
			return nil
		end
	end

	return candidate
end

-- Resolves one configured template by its exact server-only path. No cloud
-- fallback or placeholder is used when repository-backed runtime art is missing.
local function discoverTemplate(speciesId: string): Model?
	local definition = Oddlings.GetDefinition(speciesId) :: OddlingDefinition?
	if not definition then
		return nil
	end

	local assets = ServerStorage:FindFirstChild("ODDWORKSAssets")
	local oddlings = if assets then assets:FindFirstChild("Oddlings") else nil
	local candidate = if oddlings then oddlings:FindFirstChild(definition.TemplateName) else nil
	local cached = cachedTemplates[speciesId]
	if cached and candidate == cached then
		return cached
	end
	cachedTemplates[speciesId] = nil

	if not candidate then
		if not missingTemplateWarnings[speciesId] then
			warn(
				string.format(
					"[ODDWORKS][OddlingDisplay] Missing runtime template: ServerStorage.ODDWORKSAssets.Oddlings.%s",
					definition.TemplateName
				)
			)
			missingTemplateWarnings[speciesId] = true
		end
		return nil
	end

	local template = validateTemplate(candidate, definition)
	if not template then
		return nil
	end

	cachedTemplates[speciesId] = template
	missingTemplateWarnings[speciesId] = nil
	print(string.format("[ODDWORKS][OddlingDisplay] Template ready: %s", definition.TemplateName))
	return template
end

-- Reads authored display contacts in stable name order. Clients never provide
-- slot positions, ordering, or workshop capacity.
local function discoverDisplaySlots(plot: BasePart, plotId: string): { DisplaySlot }
	local slotsFolder = plot:FindFirstChild(DISPLAY_SLOTS_FOLDER_NAME)
	if not slotsFolder or not slotsFolder:IsA("Folder") then
		if not missingSlotWarnings[plotId] then
			warn(string.format("[ODDWORKS][OddlingDisplay] %s is missing %s.", plot:GetFullName(), DISPLAY_SLOTS_FOLDER_NAME))
			missingSlotWarnings[plotId] = true
		end
		return {}
	end

	local slots: { DisplaySlot } = {}
	for _, child in ipairs(slotsFolder:GetChildren()) do
		if string.match(child.Name, "^Slot%d+$") then
			if child:IsA("Attachment") then
				table.insert(slots, { Name = child.Name, WorldCFrame = child.WorldCFrame })
			elseif child:IsA("BasePart") then
				table.insert(slots, { Name = child.Name, WorldCFrame = child.CFrame })
			end
		end
	end

	table.sort(slots, function(left: DisplaySlot, right: DisplaySlot): boolean
		return left.Name < right.Name
	end)

	missingSlotWarnings[plotId] = nil
	return slots
end

-- Measures the lowest corner of visible parts after pivot placement. This works
-- for both MeshParts and primitive prototype Parts without guessed Y offsets.
local function getVisiblePartBottomY(model: Model): number?
	local bottomY: number? = nil

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
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

-- Moves the whole model with PivotTo, then aligns measured visible bounds to
-- the authored slot contact plane while preserving internal rig transforms.
local function placeDisplayAtSlot(model: Model, slot: DisplaySlot): boolean
	model:PivotTo(slot.WorldCFrame)

	local partBottomY = getVisiblePartBottomY(model)
	if not partBottomY then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s has no visible bounds for placement.", model.Name))
		return false
	end

	local verticalCorrection = slot.WorldCFrame.Position.Y - partBottomY
	model:PivotTo(model:GetPivot() + Vector3.new(0, verticalCorrection, 0))
	return true
end

-- Applies one configured physics policy: an animated rig anchors only its root,
-- while a static prototype anchors every part. Both remain non-interactive visuals.
local function configureDisplayPhysics(model: Model, definition: OddlingDefinition): boolean
	local rootPart = model:FindFirstChild(definition.RootPartName, true)
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		-- A classic Humanoid state machine may restore limb collision after setup.
		-- Static displays do not need locomotion, so disabling evaluation keeps the
		-- prototype inert without deleting the Humanoid that drives CharacterMeshes.
		if definition.AnchorAllParts then
			humanoid.EvaluateStateMachine = false
			humanoid.AutoRotate = false
		end
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false

			if definition.AnchorAllParts then
				descendant.Anchored = true
			else
				descendant.Anchored = descendant == rootPart
				descendant.Massless = descendant ~= rootPart
			end
		end
	end

	return true
end

-- Starts a configured Idle only for species that own a published animation.
-- Static prototypes with a nil animation ID spawn normally without fake rig setup.
local function startIdleAnimation(model: Model, definition: OddlingDefinition): boolean
	local animationAssetId = definition.IdleAnimationAssetId
	if not animationAssetId then
		return true
	end

	if model:GetAttribute("IdleAnimationStarted") == true then
		return true
	end

	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s cannot play Idle: AnimationController missing.", model.Name))
		return false
	end

	local animator = controller:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local animation = Instance.new("Animation")
	animation.Name = "Idle"
	animation.AnimationId = animationAssetId
	animation.Parent = controller

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

-- Stable UserId containers isolate reconciliation and cleanup between players.
local function getPlayerContainerName(player: Player): string
	return string.format("Player_%d", player.UserId)
end

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

-- Display cleanup removes derived visuals only. It never changes authoritative ownership.
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

-- Round-robin allocation gives every owned/configured species one slot before
-- duplicates. Sorted configuration order makes mixed workshops reproducible.
local function buildDisplayAllocation(ownedOddlings: { [string]: number }, capacity: number): { DisplayAllocation }
	local definitions = Oddlings.GetAllDefinitions()
	local remaining: { [string]: number } = {}
	local speciesDisplayIndexes: { [string]: number } = {}
	local allocations: { DisplayAllocation } = {}

	for _, definition in ipairs(definitions) do
		local ownedCount = ownedOddlings[definition.SpeciesId] or 0
		if ownedCount > 0 and discoverTemplate(definition.SpeciesId) then
			remaining[definition.SpeciesId] = ownedCount
			speciesDisplayIndexes[definition.SpeciesId] = 0
		end
	end

	while #allocations < capacity do
		local assignedThisRound = false

		for _, definition in ipairs(definitions) do
			local speciesId = definition.SpeciesId
			local remainingCount = remaining[speciesId] or 0
			if remainingCount > 0 and #allocations < capacity then
				local speciesDisplayIndex = (speciesDisplayIndexes[speciesId] or 0) + 1
				speciesDisplayIndexes[speciesId] = speciesDisplayIndex
				remaining[speciesId] = remainingCount - 1
				table.insert(allocations, {
					SlotIndex = #allocations + 1,
					SpeciesId = speciesId,
					SpeciesDisplayIndex = speciesDisplayIndex,
				})
				assignedThisRound = true
			end
		end

		if not assignedThisRound then
			break
		end
	end

	return allocations
end

-- Existing displays are keyed by total slot index; malformed or duplicate derived
-- entries are discarded so reconciliation can rebuild them from trusted state.
local function collectExistingDisplays(container: Folder): { [number]: Model }
	local displaysBySlot: { [number]: Model } = {}

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			local slotIndex = child:GetAttribute("DisplaySlotIndex")
			if typeof(slotIndex) == "number" and slotIndex > 0 and math.floor(slotIndex) == slotIndex then
				if displaysBySlot[slotIndex] then
					child:Destroy()
				else
					displaysBySlot[slotIndex] = child
				end
			else
				child:Destroy()
			end
		end
	end

	return displaysBySlot
end

-- Clones one configured template into an authoritative allocation. Spawn failure
-- affects presentation only and never refunds or rewrites ownership.
local function spawnDisplay(
	player: Player,
	plotId: string,
	allocation: DisplayAllocation,
	slot: DisplaySlot,
	container: Folder
): Model?
	local definition = Oddlings.GetDefinition(allocation.SpeciesId) :: OddlingDefinition?
	local template = discoverTemplate(allocation.SpeciesId)
	if not definition or not template then
		return nil
	end

	local clone = template:Clone()
	clone.Name = string.format("%s_%03d", allocation.SpeciesId, allocation.SpeciesDisplayIndex)
	clone:SetAttribute("OddlingSpeciesId", allocation.SpeciesId)
	clone:SetAttribute("SpeciesDisplayIndex", allocation.SpeciesDisplayIndex)
	clone:SetAttribute("DisplaySlotIndex", allocation.SlotIndex)
	clone:SetAttribute("OwnerUserId", player.UserId)
	clone:SetAttribute("AssignedPlotId", plotId)
	clone.Parent = container

	if not configureDisplayPhysics(clone, definition) then
		warn(string.format("[ODDWORKS][OddlingDisplay] %s has no usable configured root part.", clone.Name))
		clone:Destroy()
		return nil
	end

	if not placeDisplayAtSlot(clone, slot) then
		clone:Destroy()
		return nil
	end

	startIdleAnimation(clone, definition)
	return clone
end

-- Reconciles all configured species against one shared workshop capacity. The
-- allocation is always derived from server ownership, level, and templates.
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

	local levelDefinition = WorkshopLevels.GetDefinition(snapshot.WorkshopLevel) :: WorkshopLevelDefinition?
	if not levelDefinition or levelDefinition.DisplayCapacity < 0
		or math.floor(levelDefinition.DisplayCapacity) ~= levelDefinition.DisplayCapacity
	then
		warn(string.format("[ODDWORKS][OddlingDisplay] Workshop level %s has invalid capacity.", tostring(snapshot.WorkshopLevel)))
		cleanupPlayerDisplays(player)
		return
	end

	local slots = discoverDisplaySlots(plot, plotId)
	local capacity = math.min(#slots, levelDefinition.DisplayCapacity)
	local allocations = buildDisplayAllocation(snapshot.OwnedOddlings, capacity)
	if #allocations == 0 then
		cleanupPlayerDisplays(player)
		capacityWarningKeys[player] = nil
		return
	end

	local container = getOrCreatePlayerContainer(player)
	if not container then
		return
	end

	local existingDisplays = collectExistingDisplays(container)
	for slotIndex, display in pairs(existingDisplays) do
		if slotIndex > #allocations then
			display:Destroy()
			existingDisplays[slotIndex] = nil
		end
	end

	local spawnedCount = 0
	for _, allocation in ipairs(allocations) do
		local existing = existingDisplays[allocation.SlotIndex]
		local reusable = existing
			and existing:GetAttribute("OddlingSpeciesId") == allocation.SpeciesId
			and existing:GetAttribute("SpeciesDisplayIndex") == allocation.SpeciesDisplayIndex
			and existing:GetAttribute("AssignedPlotId") == plotId

		if not reusable then
			if existing then
				existing:Destroy()
			end
			if spawnDisplay(player, plotId, allocation, slots[allocation.SlotIndex], container) then
				spawnedCount += 1
			end
		elseif existing then
			placeDisplayAtSlot(existing, slots[allocation.SlotIndex])
		end
	end

	local totalOwnedConfigured = 0
	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		totalOwnedConfigured += snapshot.OwnedOddlings[definition.SpeciesId] or 0
	end
	local warningKey = string.format("%d:%d:%d", totalOwnedConfigured, #allocations, capacity)
	if totalOwnedConfigured > capacity and capacityWarningKeys[player] ~= warningKey then
		warn(
			string.format(
				"[ODDWORKS][OddlingDisplay] %s owns %d configured Oddlings but has %d active display slots.",
				player.Name,
				totalOwnedConfigured,
				capacity
			)
		)
		capacityWarningKeys[player] = warningKey
	elseif totalOwnedConfigured <= capacity then
		capacityWarningKeys[player] = nil
	end

	if spawnedCount > 0 then
		print(string.format("[ODDWORKS][OddlingDisplay] Reconciled %s: spawned %d display(s).", player.Name, spawnedCount))
	end
end

-- Defers reconciliation so repeated same-frame state notifications collapse into
-- one derived-state rebuild after the authoritative mutation has completed.
local function queueReconcile(player: Player)
	if pendingReconciliations[player] then
		return
	end

	pendingReconciliations[player] = true
	task.defer(function()
		pendingReconciliations[player] = nil
		reconcilePlayer(player)
	end)
end

-- Returns whether the server currently has a validated runtime representation.
-- Crafting checks this before spending Scrap to avoid invisible prototype ownership.
function OddlingDisplayService.HasRuntimeTemplate(speciesId: string): boolean
	return discoverTemplate(speciesId) ~= nil
end

-- Returns a fresh species-count map derived from this service's current clones.
-- Callers can mutate the copy without changing display bookkeeping.
function OddlingDisplayService.GetDisplayedCounts(player: Player): { [string]: number }
	local counts: { [string]: number } = {}
	local displaysFolder = runtimeDisplaysFolder
	if not displaysFolder then
		return counts
	end

	local container = displaysFolder:FindFirstChild(getPlayerContainerName(player))
	if not container or not container:IsA("Folder") then
		return counts
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			local speciesId = child:GetAttribute("OddlingSpeciesId")
			if typeof(speciesId) == "string" and Oddlings.GetDefinition(speciesId) then
				counts[speciesId] = (counts[speciesId] or 0) + 1
			end
		end
	end

	return counts
end

-- Keeps the established narrow query for callers interested in one species.
function OddlingDisplayService.GetDisplayedCount(player: Player, speciesId: string): number
	return OddlingDisplayService.GetDisplayedCounts(player)[speciesId] or 0
end

-- Requests the normal derived-display reconciliation without granting ownership
-- or exposing display internals. Studio tooling uses this to recover presentation
-- from authoritative state, exactly as ordinary state notifications do.
function OddlingDisplayService.Reconcile(player: Player): boolean
	if not started or player.Parent ~= Players or not PlayerStateService.HasState(player) then
		return false
	end

	queueReconcile(player)
	return true
end

-- Starts after PlayerStateService and WorkshopService. State changes reconcile
-- derived visuals; player removal cleans only that player's runtime container.
function OddlingDisplayService.Start()
	if started then
		return
	end

	local runtimeFolder = getOrCreateFolder(Workspace, RUNTIME_FOLDER_NAME)
	if not runtimeFolder then
		error("[ODDWORKS][OddlingDisplay] Could not create runtime root folder.")
	end

	local displaysFolder = getOrCreateFolder(runtimeFolder, DISPLAYS_FOLDER_NAME)
	if not displaysFolder then
		error("[ODDWORKS][OddlingDisplay] Could not create runtime display folder.")
	end

	runtimeDisplaysFolder = displaysFolder
	started = true

	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		discoverTemplate(definition.SpeciesId)
	end

	PlayerStateService.ObserveStateChanged(function(player: Player)
		queueReconcile(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		pendingReconciliations[player] = nil
		capacityWarningKeys[player] = nil
		cleanupPlayerDisplays(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		queueReconcile(player)
	end

	print("[ODDWORKS][OddlingDisplay] Service started with generic species reconciliation.")
end

return OddlingDisplayService
