--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][OddlingVariants] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local Oddlings = require(Config:WaitForChild("Oddlings"))
local OddlingVariants = require(Config:WaitForChild("OddlingVariants"))

type VariantDefinition = OddlingVariants.VariantDefinition
export type VariantResult = {
	SpeciesId: string,
	SpeciesDisplayName: string,
	VariantId: string,
	VariantDisplayName: string,
	RarityLabel: string,
	AccentColor: Color3,
	RevealIntensity: number,
}
type ResolvedRecord = {
	PlayerUserId: number,
	Result: VariantResult,
	ResolveRequestCount: number,
	ResolutionCount: number,
	Committed: boolean,
}
type LastResult = {
	RecoveryResultKey: string,
	Result: VariantResult,
}
export type DiagnosticSnapshot = {
	LastRecoveryResultKey: string?,
	LastSpeciesId: string?,
	LastVariantId: string?,
	LastRarityLabel: string?,
	LastResolvedOnce: boolean,
	LastResolveRequestCount: number,
	SessionFinds: { [string]: { [string]: number } },
}

local OddlingVariantService = {}

local RUNTIME_ROOT_NAME = "ODDWORKSRuntime"
local RUNTIME_FOLDER_NAME = "OddlingVariantReveals"

local randomSource = Random.new()
local resolvedByKey: { [string]: ResolvedRecord } = {}
local resultKeysByPlayer: { [Player]: { [string]: boolean } } = {}
local sessionFinds: { [Player]: { [string]: { [string]: number } } } = {}
local lastResults: { [Player]: LastResult } = {}
local runtimeFolder: Folder? = nil
local started = false

local function isPositiveFinite(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
end

local function copyResult(result: VariantResult): VariantResult
	return {
		SpeciesId = result.SpeciesId,
		SpeciesDisplayName = result.SpeciesDisplayName,
		VariantId = result.VariantId,
		VariantDisplayName = result.VariantDisplayName,
		RarityLabel = result.RarityLabel,
		AccentColor = result.AccentColor,
		RevealIntensity = result.RevealIntensity,
	}
end

local function validateConfiguration()
	local speciesIds = OddlingVariants.GetConfiguredSpeciesIds()
	if #speciesIds == 0 then
		error("[ODDWORKS][OddlingVariants] No species variants are configured.")
	end

	for _, speciesId in ipairs(speciesIds) do
		local speciesDefinition = Oddlings.GetDefinition(speciesId)
		local variants = OddlingVariants.GetVariants(speciesId)
		if not speciesDefinition or not speciesDefinition.IndexVisible then
			error(string.format("[ODDWORKS][OddlingVariants] %s is not a public configured Oddling species.", speciesId))
		end
		if not variants or #variants == 0 then
			error(string.format("[ODDWORKS][OddlingVariants] %s has no variants.", speciesId))
		end

		local ids: { [string]: boolean } = {}
		local totalWeight = 0
		for _, variant in ipairs(variants :: { VariantDefinition }) do
			if #variant.VariantId == 0
				or not string.match(variant.VariantId, "^[%w_]+$")
				or #variant.DisplayName == 0
				or #variant.RarityLabel == 0
				or not isPositiveFinite(variant.Weight)
				or not isPositiveFinite(variant.RevealIntensity)
			then
				error(string.format("[ODDWORKS][OddlingVariants] %s contains an invalid variant record.", speciesId))
			end
			if ids[variant.VariantId] then
				error(string.format("[ODDWORKS][OddlingVariants] %s contains duplicate variant %s.", speciesId, variant.VariantId))
			end
			ids[variant.VariantId] = true
			totalWeight += variant.Weight
		end
		if not isPositiveFinite(totalWeight) then
			error(string.format("[ODDWORKS][OddlingVariants] %s has a non-positive total weight.", speciesId))
		end
	end
end

local function chooseWeighted(variants: { VariantDefinition }): VariantDefinition
	local totalWeight = 0
	for _, variant in ipairs(variants) do
		totalWeight += variant.Weight
	end
	if not isPositiveFinite(totalWeight) then
		error("[ODDWORKS][OddlingVariants] Weighted selection received an invalid total weight.")
	end

	local roll = randomSource:NextNumber() * totalWeight
	local cumulativeWeight = 0
	for _, variant in ipairs(variants) do
		cumulativeWeight += variant.Weight
		if roll <= cumulativeWeight then
			return variant
		end
	end
	error("[ODDWORKS][OddlingVariants] Weighted selection failed to choose a configured variant.")
end

local function getOrCreateRuntimeFolder(): Folder
	local root = Workspace:FindFirstChild(RUNTIME_ROOT_NAME)
	if not root then
		root = Instance.new("Folder")
		root.Name = RUNTIME_ROOT_NAME
		root.Parent = Workspace
	end
	if not root:IsA("Folder") then
		error("[ODDWORKS][OddlingVariants] Workspace.ODDWORKSRuntime must be a Folder.")
	end
	local folder = root:FindFirstChild(RUNTIME_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = RUNTIME_FOLDER_NAME
		folder.Parent = root
	end
	if not folder:IsA("Folder") then
		error("[ODDWORKS][OddlingVariants] Reveal runtime must be a Folder.")
	end
	return folder
end

local function clearPlayer(player: Player)
	local keys = resultKeysByPlayer[player]
	if keys then
		for resultKey in pairs(keys) do
			resolvedByKey[resultKey] = nil
		end
	end
	resultKeysByPlayer[player] = nil
	sessionFinds[player] = nil
	lastResults[player] = nil
end

function OddlingVariantService.CanResolveSpecies(speciesId: string): boolean
	local variants = OddlingVariants.GetVariants(speciesId)
	return Oddlings.GetDefinition(speciesId) ~= nil and variants ~= nil and #variants > 0
end

function OddlingVariantService.ResolveVariant(player: Player, resultKey: string, speciesId: string): VariantResult
	if not started
		or player.Parent ~= Players
		or #resultKey == 0
		or #resultKey > 160
	then
		error("[ODDWORKS][OddlingVariants] ResolveVariant received an invalid server context.", 2)
	end

	local existing = resolvedByKey[resultKey]
	if existing then
		if existing.PlayerUserId ~= player.UserId or existing.Result.SpeciesId ~= speciesId then
			error("[ODDWORKS][OddlingVariants] A recovery result key was reused for different authority.", 2)
		end
		existing.ResolveRequestCount += 1
		lastResults[player] = {
			RecoveryResultKey = resultKey,
			Result = existing.Result,
		}
		return copyResult(existing.Result)
	end

	local speciesDefinition = Oddlings.GetDefinition(speciesId)
	local variants = OddlingVariants.GetVariants(speciesId)
	if not speciesDefinition or not variants or #variants == 0 then
		error(string.format("[ODDWORKS][OddlingVariants] No validated variants exist for %s.", speciesId), 2)
	end
	local selected = chooseWeighted(variants)
	local result: VariantResult = {
		SpeciesId = speciesId,
		SpeciesDisplayName = speciesDefinition.DisplayName,
		VariantId = selected.VariantId,
		VariantDisplayName = selected.DisplayName,
		RarityLabel = selected.RarityLabel,
		AccentColor = selected.AccentColor,
		RevealIntensity = selected.RevealIntensity,
	}
	resolvedByKey[resultKey] = {
		PlayerUserId = player.UserId,
		Result = result,
		ResolveRequestCount = 1,
		ResolutionCount = 1,
		Committed = false,
	}
	local keys = resultKeysByPlayer[player]
	if not keys then
		keys = {}
		resultKeysByPlayer[player] = keys
	end
	keys[resultKey] = true
	lastResults[player] = {
		RecoveryResultKey = resultKey,
		Result = result,
	}
	return copyResult(result)
end

function OddlingVariantService.CommitResolvedResult(player: Player, resultKey: string): (VariantResult, boolean)
	local record = resolvedByKey[resultKey]
	if not record or record.PlayerUserId ~= player.UserId then
		error("[ODDWORKS][OddlingVariants] Cannot commit an unresolved recovery variant.", 2)
	end
	if record.Committed then
		return copyResult(record.Result), false
	end
	record.Committed = true

	local playerFinds = sessionFinds[player]
	if not playerFinds then
		playerFinds = {}
		sessionFinds[player] = playerFinds
	end
	local speciesFinds = playerFinds[record.Result.SpeciesId]
	if not speciesFinds then
		speciesFinds = {}
		playerFinds[record.Result.SpeciesId] = speciesFinds
	end
	speciesFinds[record.Result.VariantId] = (speciesFinds[record.Result.VariantId] or 0) + 1
	return copyResult(record.Result), true
end

function OddlingVariantService.PresentCommittedReveal(player: Player, resultKey: string)
	local record = resolvedByKey[resultKey]
	local folder = runtimeFolder
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not record
		or record.PlayerUserId ~= player.UserId
		or not record.Committed
		or record.Result.RevealIntensity <= 1
		or not folder
		or not root
		or not root:IsA("BasePart")
	then
		return
	end

	local pulse = Instance.new("Part")
	pulse.Name = record.Result.VariantId .. "RevealPulse"
	pulse.Shape = Enum.PartType.Ball
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanQuery = false
	pulse.CanTouch = false
	pulse.Material = Enum.Material.Neon
	pulse.Color = record.Result.AccentColor
	pulse.Transparency = 0.62
	pulse.Size = Vector3.new(2.5, 2.5, 2.5)
	pulse.CFrame = CFrame.new(root.Position + Vector3.new(0, 2.5, 0))
	pulse.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = record.Result.AccentColor
	light.Brightness = 2.5 * record.Result.RevealIntensity
	light.Range = 12 * record.Result.RevealIntensity
	light.Shadows = false
	light.Parent = pulse
	TweenService:Create(
		pulse,
		TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(10, 10, 10) * record.Result.RevealIntensity,
			Transparency = 1,
		}
	):Play()
	TweenService:Create(light, TweenInfo.new(0.75), { Brightness = 0 }):Play()
	Debris:AddItem(pulse, 0.85)
end

function OddlingVariantService.GetDiagnosticSnapshot(player: Player): DiagnosticSnapshot
	local finds: { [string]: { [string]: number } } = {}
	local playerFinds = sessionFinds[player]
	for _, speciesId in ipairs(OddlingVariants.GetConfiguredSpeciesIds()) do
		local speciesFinds: { [string]: number } = {}
		local committedSpeciesFinds = if playerFinds then playerFinds[speciesId] else nil
		local variants = OddlingVariants.GetVariants(speciesId) or {}
		for _, variant in ipairs(variants) do
			speciesFinds[variant.VariantId] = if committedSpeciesFinds
				then committedSpeciesFinds[variant.VariantId] or 0
				else 0
		end
		finds[speciesId] = speciesFinds
	end

	local last = lastResults[player]
	local record = if last then resolvedByKey[last.RecoveryResultKey] else nil
	return {
		LastRecoveryResultKey = if last then last.RecoveryResultKey else nil,
		LastSpeciesId = if last then last.Result.SpeciesId else nil,
		LastVariantId = if last then last.Result.VariantId else nil,
		LastRarityLabel = if last then last.Result.RarityLabel else nil,
		LastResolvedOnce = record ~= nil and record.ResolutionCount == 1,
		LastResolveRequestCount = if record then record.ResolveRequestCount else 0,
		SessionFinds = finds,
	}
end

function OddlingVariantService.Start()
	if started then
		return
	end
	validateConfiguration()
	started = true
	runtimeFolder = getOrCreateRuntimeFolder()
	for _, child in ipairs((runtimeFolder :: Folder):GetChildren()) do
		child:Destroy()
	end
	Players.PlayerRemoving:Connect(clearPlayer)
	print("[ODDWORKS][OddlingVariants] Server-authoritative session variant resolution started.")
end

return OddlingVariantService
