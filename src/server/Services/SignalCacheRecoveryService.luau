--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local Config = require(Services.Parent.Config.SignalCacheConfig)
local Capabilities = require(Services.ConstructCapabilityResolver)
local Registry = require(Services.RecoveryCarrierRegistry)
local PlayerState = require(Services.PlayerStateService)
local Displays = require(Services.OddlingDisplayService)
local Workshops = require(Services.WorkshopService)

local Service = {}
local ACTIVITY = "SignalCache"
local rng = Random.new()
local generation = 0
local phase = "RESETTING"
local correctCacheId = ""
local owner: Player? = nil
local character: Model? = nil
local area: Model
local remote: RemoteEvent
local caches: { [string]: BasePart } = {}
local lenses: { [string]: BasePart } = {}
local signalPatterns: { [string]: { number } } = {}
local signalEpoch = 0
local prompts: { ProximityPrompt } = {}
local connections: { RBXScriptConnection } = {}
local lastRequests: { [Player]: number } = {}
local lastMetrics: { [Player]: { [string]: any } } = {}
local metrics: { [string]: any }? = nil
local carry: BasePart? = nil
local warden: BasePart? = nil
local movement: { Humanoid: Humanoid, Baseline: number, Applied: number }? = nil
local busyUntil = 0
local lastActivityAt = 0
local activityPosition = Vector3.zero
local reservationStartedAt = 0
local absoluteInvestigationDeadline = 0
local inspectionSerial = 0
local inspectedCaches: { [string]: boolean } = {}
local started = false

local function liveRoot(player: Player): (BasePart?, Humanoid?)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if player.Parent ~= Players or not model or model.Parent ~= Workspace
		or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0
		or not PlayerState.HasState(player) then
		return nil, nil
	end
	return root, humanoid
end

local function secureZone(player: Player): BasePart?
	local plot = Workshops.GetAssignedPlot(player)
	local zone = plot and plot:FindFirstChild("FurnacePodSecureZone")
	return if zone and zone:IsA("BasePart") then zone else nil
end

local function inside(position: Vector3, zone: BasePart): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local h = zone.Size * 0.5
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- Server -> owner only: generation, short feedback, and optional clue/destination.
-- No OnServerEvent: requests are captured, generation-scoped Prompt.Triggered intents.
local function send(player: Player, kind: string, message: string, extra: { [string]: any }?)
	if player.Parent ~= Players then return end
	-- Replacement feedback closes the local observation; its completion must be cancelled too.
	if player == owner and kind ~= "OBSERVE" then inspectionSerial += 1 end
	local payload = extra or {}
	payload.Generation = generation
	payload.Kind = kind
	payload.Message = message
	remote:FireClient(player, payload)
end

local function current(player: Player, token: number): boolean
	return generation == token and owner == player and player.Character == character
		and Registry.GetActiveActivity(player) == ACTIVITY
end

local function canReach(player: Player, cache: BasePart, distance: number): boolean
	local root = liveRoot(player)
	if not root or not cache:IsDescendantOf(area) or (root.Position - cache.Position).Magnitude > distance then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local hit = Workspace:Raycast(root.Position, cache.Position - root.Position, params)
	return hit == nil or hit.Instance == cache
end

local function insideActivityFootprint(position: Vector3): boolean
	local membershipRange = Config.ScannerRange + Config.ActivityMargin
	for _, cache in pairs(caches) do
		if (position - cache.Position).Magnitude <= membershipRange then
			return true
		end
	end
	return false
end

local function setPrompts(enabled: boolean)
	for _, prompt in ipairs(prompts) do prompt.Enabled = enabled end
end

local function cleanup()
	inspectionSerial += 1
	table.clear(inspectedCaches)
	area:SetAttribute("SignalsActive", false)
	for _, lens in pairs(lenses) do
		lens.Material = Enum.Material.Metal
		lens.Color = Color3.fromRGB(57, 76, 65)
	end
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	for _, prompt in ipairs(prompts) do prompt:Destroy() end
	table.clear(prompts)
	if carry then carry:Destroy(); carry = nil end
	if warden then warden:Destroy(); warden = nil end
	local record = movement
	if record and record.Humanoid.Parent and math.abs(record.Humanoid.WalkSpeed - record.Applied) < 0.01 then
		record.Humanoid.WalkSpeed = record.Baseline
	end
	movement = nil
	if owner then Registry.Release(owner, ACTIVITY) end
	owner = nil
	character = nil
	metrics = nil
	busyUntil = 0
	lastActivityAt = 0
	activityPosition = Vector3.zero
	reservationStartedAt = 0
	absoluteInvestigationDeadline = 0
end

local startGeneration: () -> ()

local function finish(player: Player, token: number, success: boolean, message: string, abandoned: boolean?)
	-- Leave/profile cleanup must survive the registry clearing its entry first.
	if generation ~= token or owner ~= player or phase == "RESETTING" or phase == "SECURED" then return end
	if success and (phase ~= "CHASE_ACTIVE" or not current(player, token)) then return end
	-- Terminal latch precedes the non-yielding ownership API. Presentation never proves success.
	phase = if success then "SECURED" else "RESETTING"
	if success then
		local root = liveRoot(player)
		local zone = secureZone(player)
		success = root ~= nil and zone ~= nil and inside(root.Position, zone)
			and Displays.HasRuntimeTemplate(Config.RewardSpeciesId)
			and PlayerState.CanAddOwnedOddling(player, Config.RewardSpeciesId, 1)
		if success then success = PlayerState.AddOwnedOddling(player, Config.RewardSpeciesId, 1) end
		if not success then message = "RECOVERY CANCELLED" end
	end
	local record = metrics
	if record then
		record.Outcome = if success then "SECURED" else message
		lastMetrics[player] = table.clone(record)
		if RunService:IsStudio() then
			print(string.format("[ODDWORKS][SignalCache] %s", game:GetService("HttpService"):JSONEncode(record)))
		end
	end
	send(player, if success then "SECURED" else "ENDED", if success then "CACHE SECURED" else message)
	cleanup()
	phase = "RESETTING"
	local delaySeconds = if abandoned then 0 else (if success then Config.SuccessCooldown else Config.ResetSeconds)
	task.delay(delaySeconds, function()
		if generation == token and phase == "RESETTING" then startGeneration() end
	end)
end

local function reserve(player: Player, token: number): boolean
	if generation ~= token then return false end
	if owner then return current(player, token) and phase == "INVESTIGATING" end
	local root, humanoid = liveRoot(player)
	if phase ~= "AVAILABLE" or not root or not humanoid or not secureZone(player)
		or not Registry.TryAcquire(player, ACTIVITY) then return false end
	owner = player
	character = player.Character
	phase = "INVESTIGATING"
	reservationStartedAt = os.clock()
	absoluteInvestigationDeadline = reservationStartedAt + Config.AbsoluteInvestigationLeaseSeconds
	lastActivityAt = reservationStartedAt
	activityPosition = root.Position
	metrics = {
		Generation = token, CorrectCacheId = correctCacheId,
		SignalScanner = Capabilities.CanDetectStrangeSignals(player),
		SpringLegs = Capabilities.HasSpringLegsChaseCapability(player),
		InvestigationStartTime = reservationStartedAt,
		ReservationStartedAt = reservationStartedAt,
		AbsoluteInvestigationDeadline = absoluteInvestigationDeadline,
		InspectionCount = 0, WrongExtractionCount = 0,
		BlindExtractionAttemptCount = 0,
		MixedEquipment = false,
	}
	table.insert(connections, humanoid.Died:Connect(function() finish(player, token, false, "RECOVERY CANCELLED") end))
	table.insert(connections, player.CharacterRemoving:Connect(function() finish(player, token, false, "RECOVERY CANCELLED") end))
	-- Only one reserved investigator is sampled. Extraction/chase keep their existing lifetime.
	task.delay(Config.AbsoluteInvestigationLeaseSeconds, function()
		if current(player, token) and phase == "INVESTIGATING"
			and os.clock() >= absoluteInvestigationDeadline
		then
			finish(player, token, false, "INVESTIGATION LEASE EXPIRED", true)
		end
	end)
	task.spawn(function()
		local outsideSince: number? = nil
		while current(player, token) and phase == "INVESTIGATING" do
			local live = liveRoot(player)
			if not live then finish(player, token, false, "RECOVERY CANCELLED"); return end
			local now = os.clock()
			if now >= absoluteInvestigationDeadline then
				finish(player, token, false, "INVESTIGATION LEASE EXPIRED", true); return
			end
			if not insideActivityFootprint(live.Position) then
				outsideSince = outsideSince or now
				if now - outsideSince >= Config.AbandonmentGraceSeconds then
					finish(player, token, false, "INVESTIGATION RELEASED - LEFT AREA", true); return
				end
			else
				outsideSince = nil
				if (live.Position - activityPosition).Magnitude >= Config.ActivityMovementStuds then
					lastActivityAt = now
					activityPosition = live.Position
				end
			end
			if now - lastActivityAt >= Config.InactivitySeconds then
				finish(player, token, false, "INVESTIGATION RELEASED - INACTIVE", true); return
			end
			task.wait(Config.ReservationPollSeconds)
		end
	end)
	return true
end

local function visual(name: string, size: Vector3, color: Color3, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = cf
	part.Parent = area
	return part
end

local function runChase(player: Player, token: number, cache: BasePart)
	local root, humanoid = liveRoot(player)
	local zone = secureZone(player)
	if not current(player, token) or phase ~= "EXTRACTION_ACTIVE" then return end
	if not root or not humanoid or not zone then finish(player, token, false, "RECOVERY CANCELLED"); return end
	phase = "CHASE_ACTIVE"
	carry = visual("SignalCarry", Vector3.new(2.5, 2, 2), Color3.fromRGB(170, 235, 170), root.CFrame * CFrame.new(0, 0, -2))
	carry.Anchored = false
	carry.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = carry
	weld.Parent = carry
	warden = visual("SignalSentinel", Vector3.new(4, 5, 4), Color3.fromRGB(230, 140, 60), CFrame.new(cache.Position + Vector3.new(0, 1, 14)))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Brightness = 3
	light.Range = 16
	light.Parent = warden
	if Capabilities.HasSpringLegsChaseCapability(player) then
		movement = { Humanoid = humanoid, Baseline = humanoid.WalkSpeed, Applied = humanoid.WalkSpeed * 1.20 }
		humanoid.WalkSpeed = movement.Applied
	end
	send(player, "CHASE", "SECURITY ACTIVE - RETURN TO YOUR WORKSHOP", { Destination = zone.Position })
	local began = os.clock()
	local previous = began
	while current(player, token) and phase == "CHASE_ACTIVE" do
		local live = liveRoot(player)
		local destination = secureZone(player)
		local guardian = warden
		if not live or not destination or not guardian or not guardian.Parent or not carry or not carry.Parent then
			finish(player, token, false, "RECOVERY CANCELLED"); return
		end
		if inside(live.Position, destination) then finish(player, token, true, ""); return end
		local now = os.clock()
		if now - began >= Config.ChaseTimeout then finish(player, token, false, "SIGNAL LOST"); return end
		if now - began >= Config.HeadStartSeconds then
			local target = Vector3.new(live.Position.X, guardian.Position.Y, live.Position.Z)
			local offset = target - guardian.Position
			if offset.Magnitude <= Config.CatchRadius then finish(player, token, false, "CACHE LOST - SENTINEL CAUGHT YOU"); return end
			if offset.Magnitude > 0.001 then
				local direction = offset.Unit
				local position = guardian.Position + direction * math.min(offset.Magnitude, Config.WardenSpeed * math.min(now - previous, 0.25))
				guardian.CFrame = CFrame.lookAt(position, position + direction)
			end
		end
		previous = now
		task.wait(Config.PollSeconds)
	end
end

local function interact(player: Player, token: number, id: string, inspect: boolean)
	local now = os.clock()
	if now - (lastRequests[player] or -math.huge) < Config.RequestInterval then return end
	lastRequests[player] = now
	if generation ~= token or (phase ~= "AVAILABLE" and phase ~= "INVESTIGATING") or now < busyUntil then return end
	if owner == player and phase == "INVESTIGATING" and now >= absoluteInvestigationDeadline then
		finish(player, token, false, "INVESTIGATION LEASE EXPIRED", true)
		return
	end
	local cache = caches[id]
	local scanner = Capabilities.CanDetectStrangeSignals(player)
	local range = if inspect then (if scanner then Config.ScannerRange else Config.ManualRange) else Config.ExtractRange
	if not cache or not canReach(player, cache, range) then
		if inspect and cache and canReach(player, cache, Config.ScannerRange) then
			send(player, "MESSAGE", "MOVE CLOSER TO INSPECT")
		end
		return
	end
	if not reserve(player, token) then
		send(player, "MESSAGE", "CACHE RECOVERY BUSY")
		return
	end
	local record = metrics :: { [string]: any }
	lastActivityAt = now
	local live = liveRoot(player)
	if live then activityPosition = live.Position end
	if scanner ~= record.SignalScanner then record.MixedEquipment = true end
	if Capabilities.HasSpringLegsChaseCapability(player) ~= record.SpringLegs then record.MixedEquipment = true end
	if inspect then
		record.InspectionCount += 1
		inspectionSerial += 1
		local serial = inspectionSerial
		-- A clue dispatch timestamp is evidence of information offered, not comprehension.
		if id == correctCacheId and not record.FirstAuthenticClueTime then record.FirstAuthenticClueTime = now end
		send(player, "OBSERVE", "CACHE " .. id .. " - WATCH THE RHYTHM\nLIVE SIGNALS KEEP AN EVEN BEAT", {
			CacheId = id, Scanner = scanner, Range = range, Duration = Config.ObservationSeconds,
			-- Public optical timing, not an authenticity flag. Scanner plots it live, never labels an answer.
			PulseOffsets = table.clone(signalPatterns[id]), SignalEpoch = signalEpoch,
			CycleSeconds = Config.SignalCycleSeconds, PulseSeconds = Config.SignalPulseSeconds,
		})
		task.delay(Config.ObservationSeconds, function()
			if not current(player, token) or phase ~= "INVESTIGATING" or inspectionSerial ~= serial then return end
			if not canReach(player, cache, range) then return end
			if scanner and not Capabilities.CanDetectStrangeSignals(player) then return end
			inspectedCaches[id] = true
		end)
		return
	end
	-- Conservative proxy: no completed observation of this cache. It cannot prove actual guessing.
	local blind = inspectedCaches[id] ~= true
	if blind then record.BlindExtractionAttemptCount += 1 end
	if id ~= correctCacheId then
		record.WrongExtractionCount += 1
		busyUntil = now + Config.WrongRetrySeconds
		send(player, "MESSAGE", "EMPTY CACHE - RETRY IN 2s")
		return
	end
	if not record.FirstCorrectExtractionAttemptTime then
		record.FirstCorrectExtractionAttemptTime = now
		record.ChoiceTime = now - record.InvestigationStartTime
		record.FirstCorrectExtractionBlind = blind
	end
	phase = "EXTRACTION_ACTIVE"
	area:SetAttribute("SignalsActive", false)
	setPrompts(false)
	send(player, "EXTRACTING", "EXTRACTING SIGNAL CACHE")
	task.delay(Config.ExtractSeconds, function()
		if not current(player, token) or phase ~= "EXTRACTION_ACTIVE" then return end
		if not canReach(player, cache, Config.ExtractRange) then finish(player, token, false, "EXTRACTION INTERRUPTED"); return end
		runChase(player, token, cache)
	end)
end

startGeneration = function()
	cleanup()
	generation += 1
	local token = generation
	correctCacheId = Config.CacheIds[rng:NextInteger(1, #Config.CacheIds)]
	phase = "AVAILABLE"
	signalEpoch = Workspace:GetServerTimeNow()
	area:SetAttribute("RecoveryGeneration", token)
	area:SetAttribute("SignalsActive", true)
	local decoyIndex = 2
	for _, id in ipairs(Config.CacheIds) do
		local cache = caches[id]
		signalPatterns[id] = Config.SignalPatterns[if id == correctCacheId then 1 else decoyIndex]
		if id ~= correctCacheId then decoyIndex += 1 end
		for _, inspect in ipairs({ true, false }) do
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = if inspect then "Inspect" else "Extract"
			prompt.ActionText = if inspect then "INSPECT SIGNAL" else "EXTRACT CACHE"
			prompt.ObjectText = "Cache " .. id
			prompt.KeyboardKeyCode = if inspect then Enum.KeyCode.E else Enum.KeyCode.F
			prompt.GamepadKeyCode = if inspect then Enum.KeyCode.ButtonX else Enum.KeyCode.ButtonY
			prompt.MaxActivationDistance = if inspect then Config.ScannerRange else Config.ExtractRange
			prompt.RequiresLineOfSight = true
			prompt.UIOffset = Vector2.new(0, if inspect then -30 else 30)
			prompt:SetAttribute("RecoveryGeneration", token)
			prompt.Parent = cache
			table.insert(prompts, prompt)
			table.insert(connections, prompt.Triggered:Connect(function(player) interact(player, token, id, inspect) end))
		end
	end
	-- Three known lenses, only optical transitions replicated; no players or Workspace scans.
	task.spawn(function()
		local previous: { [string]: boolean } = {}
		while generation == token and (phase == "AVAILABLE" or phase == "INVESTIGATING") do
			local t = (Workspace:GetServerTimeNow() - signalEpoch) % Config.SignalCycleSeconds
			for _, id in ipairs(Config.CacheIds) do
				local on = false
				for _, onset in ipairs(signalPatterns[id]) do
					if t >= onset and t < onset + Config.SignalPulseSeconds then on = true; break end
				end
				if previous[id] ~= on then
					previous[id] = on
					lenses[id].Material = if on then Enum.Material.Neon else Enum.Material.Metal
					lenses[id].Color = if on then Color3.fromRGB(144, 211, 161) else Color3.fromRGB(57, 76, 65)
				end
			end
			task.wait(0.1)
		end
		if generation == token then
			for _, lens in pairs(lenses) do lens.Material = Enum.Material.Metal; lens.Color = Color3.fromRGB(57, 76, 65) end
		end
	end)
end

function Service.GetDiagnosticSnapshot(player: Player): { [string]: any }
	if not RunService:IsStudio() then return {} end
	local result = table.clone(if owner == player and metrics then metrics else lastMetrics[player] or {})
	result.CurrentGeneration = generation
	result.CurrentPhase = phase
	result.CurrentCorrectCacheId = correctCacheId
	return result
end

function Service.Start()
	if started then return end
	started = true
	area = Workspace:WaitForChild("ODDWORKSWorld"):WaitForChild("SignalCacheArea") :: Model
	remote = ReplicatedStorage:WaitForChild("ODDWORKSNetwork"):WaitForChild("SignalCacheState") :: RemoteEvent
	for _, id in ipairs(Config.CacheIds) do
		caches[id] = area:WaitForChild("Cache" .. id) :: BasePart
		lenses[id] = caches[id]:WaitForChild("SignalLens") :: BasePart
	end
	local function remove(player: Player)
		if owner == player then finish(player, generation, false, "RECOVERY CANCELLED") end
		lastRequests[player] = nil
		lastMetrics[player] = nil
	end
	Players.PlayerRemoving:Connect(remove)
	PlayerState.ObserveStateRemoved(remove)
	startGeneration()
	print("[ODDWORKS][SignalCache] Three-cache recovery prototype started.")
end

return Service
