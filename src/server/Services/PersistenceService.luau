--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = script.Parent
local ServerRoot = assert(Services.Parent, "[ODDWORKS][Persistence] Services folder must have a parent.")
local Config = ServerRoot:WaitForChild("Config")
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local Oddlings = require(Config:WaitForChild("Oddlings"))
local WorkshopLevels = require(Config:WaitForChild("WorkshopLevels"))
local PersistenceConfig = require(Config:WaitForChild("PersistenceConfig"))

type OddlingCounts = { [string]: number }
type SaveDataV1 = {
	SchemaVersion: number,
	Scrap: number,
	Hype: number,
	WorkshopLevel: number,
	OwnedOddlings: OddlingCounts,
}

export type PersistenceStatus = "NotLoaded" | "Loading" | "Ready" | "Failed" | "SessionLost" | "Disabled"

local PersistenceService = {}

local MAX_SAFE_INTEGER = 9_007_199_254_740_991
local PROFILE_LOAD_FAILURE_MESSAGE = "Your ODDWORKS data could not be loaded safely. Please rejoin and try again."
local SESSION_LOSS_MESSAGE = "Your ODDWORKS data session ended on this server. Please rejoin to continue safely."
local ENVIRONMENT_DISABLED_MESSAGE = "Persistence is not enabled for this ODDWORKS environment."

local profileStoreLibrary: any = nil
local activeStore: any = nil
local activeMode = "Disabled"
local profiles: { [Player]: any } = {}
local statuses: { [Player]: PersistenceStatus } = {}
local started = false

-- DataStore numbers are untrusted input. Restricting them to safe non-negative
-- integers prevents NaN, infinity, fractions, and precision-unsafe values.
local function isNonNegativeSafeInteger(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and math.floor(value) == value
end

-- Creates a fresh known-species map so templates, profiles, and PlayerState do
-- not share nested table references.
local function createDefaultOddlingCounts(): OddlingCounts
	local counts: OddlingCounts = {}
	for _, definition in ipairs(Oddlings.GetAllDefinitions()) do
		counts[definition.SpeciesId] = 0
	end
	return counts
end

-- The explicit v1 template contains only durable authority. Session and derived
-- fields never enter ProfileStore data through this boundary.
local function createSaveTemplate(): SaveDataV1
	return {
		SchemaVersion = PersistenceConfig.SCHEMA_VERSION,
		Scrap = 0,
		Hype = 0,
		WorkshopLevel = 1,
		OwnedOddlings = createDefaultOddlingCounts(),
	}
end

-- Normalizes untrusted stored data into schema v1. A future schema newer than
-- this server is rejected to avoid silently overwriting data it cannot understand.
local function migrateSaveData(rawData: any): (SaveDataV1?, string)
	if typeof(rawData) ~= "table" then
		return createSaveTemplate(), "invalid root replaced with schema v1 defaults"
	end

	local rawVersion = rawData.SchemaVersion
	if isNonNegativeSafeInteger(rawVersion) and rawVersion > PersistenceConfig.SCHEMA_VERSION then
		return nil, string.format("unsupported future schema version %d", rawVersion)
	end

	local migrated = createSaveTemplate()
	if isNonNegativeSafeInteger(rawData.Scrap) then
		migrated.Scrap = rawData.Scrap
	end
	if isNonNegativeSafeInteger(rawData.Hype) then
		migrated.Hype = rawData.Hype
	end
	if isNonNegativeSafeInteger(rawData.WorkshopLevel) and WorkshopLevels.GetDefinition(rawData.WorkshopLevel) then
		migrated.WorkshopLevel = rawData.WorkshopLevel
	end

	if typeof(rawData.OwnedOddlings) == "table" then
		for speciesId in pairs(migrated.OwnedOddlings) do
			local count = rawData.OwnedOddlings[speciesId]
			if isNonNegativeSafeInteger(count) then
				migrated.OwnedOddlings[speciesId] = count
			end
		end
	end

	return migrated, string.format("normalized to schema v%d", PersistenceConfig.SCHEMA_VERSION)
end

-- Translates a defensive PlayerState snapshot into the only fields permitted in
-- persistent schema v1. AssignedPlotId and UnlockedRecipes are excluded by design.
local function buildSavePayload(snapshot: any): SaveDataV1
	local payload = createSaveTemplate()
	payload.Scrap = if isNonNegativeSafeInteger(snapshot.Scrap) then snapshot.Scrap else 0
	payload.Hype = if isNonNegativeSafeInteger(snapshot.Hype) then snapshot.Hype else 0
	payload.WorkshopLevel = if isNonNegativeSafeInteger(snapshot.WorkshopLevel)
		and WorkshopLevels.GetDefinition(snapshot.WorkshopLevel)
		then snapshot.WorkshopLevel
		else 1

	if typeof(snapshot.OwnedOddlings) == "table" then
		for speciesId in pairs(payload.OwnedOddlings) do
			local count = snapshot.OwnedOddlings[speciesId]
			if isNonNegativeSafeInteger(count) then
				payload.OwnedOddlings[speciesId] = count
			end
		end
	end

	return payload
end

-- Replaces the in-memory profile payload with a fresh canonical copy. ProfileStore
-- will autosave it; this function does not issue a DataStore write itself.
local function writeProfileData(profile: any, payload: SaveDataV1)
	for key in pairs(profile.Data) do
		profile.Data[key] = nil
	end

	profile.Data.SchemaVersion = payload.SchemaVersion
	profile.Data.Scrap = payload.Scrap
	profile.Data.Hype = payload.Hype
	profile.Data.WorkshopLevel = payload.WorkshopLevel
	profile.Data.OwnedOddlings = table.clone(payload.OwnedOddlings)
end

-- Keeps Profile.Data synchronized with server authority without manually saving
-- on every Hype tick; ProfileStore retains control of its autosave schedule.
local function syncProfileData(player: Player, profile: any): boolean
	local snapshot = PlayerStateService.GetSnapshot(player)
	if not snapshot then
		return false
	end

	writeProfileData(profile, buildSavePayload(snapshot))
	return true
end

-- Selects Mock unconditionally in Studio. Live writes are allowed only in the
-- separately verified internal-test universe; production has no selectable path.
local function configureStore(ProfileStore: any): (any?, string)
	if RunService:IsStudio() then
		local studioStore = ProfileStore.New(PersistenceConfig.STUDIO_MOCK_STORE_NAME, createSaveTemplate())
		return studioStore.Mock, "StudioMock"
	end

	if game.GameId == PersistenceConfig.INTERNAL_TEST_UNIVERSE_ID then
		return ProfileStore.New(PersistenceConfig.INTERNAL_TEST_STORE_NAME, createSaveTemplate()), "InternalTest"
	end

	return nil, "Disabled"
end

-- Handles both orderly shutdown release and unexpected session loss. A live
-- player cannot continue after loss because new progress would be unsavable.
local function handleSessionEnd(player: Player, profile: any)
	if profiles[player] ~= profile then
		return
	end

	profiles[player] = nil
	PlayerStateService.RemovePlayerState(player)

	-- ProfileStore deliberately ends every active session during BindToClose.
	-- That path is an orderly release, not a recoverable in-session data fault.
	if profileStoreLibrary.IsClosing then
		statuses[player] = nil
		print(string.format("[ODDWORKS][Persistence] Released profile during shutdown for %s (%d).", player.Name, player.UserId))
		return
	end

	statuses[player] = "SessionLost"
	warn(string.format("[ODDWORKS][Persistence] Profile session ended unexpectedly for %s (%d).", player.Name, player.UserId))

	if player.Parent == Players then
		player:Kick(SESSION_LOSS_MESSAGE)
	end
end

-- Loads one server-derived profile key and creates PlayerState only after the
-- session is active and its data has been normalized into a defensive copy.
local function loadPlayer(player: Player)
	if statuses[player] == "Loading" or statuses[player] == "Ready" then
		return
	end

	if not activeStore then
		statuses[player] = "Disabled"
		if player.Parent == Players then
			player:Kick(ENVIRONMENT_DISABLED_MESSAGE)
		end
		return
	end

	statuses[player] = "Loading"
	local profileKey = PersistenceConfig.PROFILE_KEY_PREFIX .. tostring(player.UserId)
	local profile = activeStore:StartSessionAsync(profileKey, {
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	})

	if not profile then
		if player.Parent == Players then
			statuses[player] = "Failed"
			warn(string.format("[ODDWORKS][Persistence] Could not acquire profile session for %s (%d).", player.Name, player.UserId))
			player:Kick(PROFILE_LOAD_FAILURE_MESSAGE)
		else
			statuses[player] = nil
		end
		return
	end

	if player.Parent ~= Players then
		profile:EndSession()
		statuses[player] = nil
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	local saveData, migrationResult = migrateSaveData(profile.Data)
	if not saveData then
		statuses[player] = "Failed"
		warn(string.format("[ODDWORKS][Persistence] Rejected %s profile: %s.", player.Name, migrationResult))
		profile:EndSession()
		player:Kick(PROFILE_LOAD_FAILURE_MESSAGE)
		return
	end
	writeProfileData(profile, saveData)

	profiles[player] = profile
	profile.OnLastSave:Connect(function()
		-- ProfileStore invokes this synchronously before its final save, including
		-- server shutdown; no yielding occurs inside this callback.
		if profiles[player] == profile then
			syncProfileData(player, profile)
		end
	end)
	profile.OnSessionEnd:Connect(function()
		handleSessionEnd(player, profile)
	end)

	if not profile:IsActive() then
		handleSessionEnd(player, profile)
		return
	end

	local didInitialize = PlayerStateService.InitializePlayer(player, {
		Scrap = saveData.Scrap,
		Hype = saveData.Hype,
		WorkshopLevel = saveData.WorkshopLevel,
		OwnedOddlings = table.clone(saveData.OwnedOddlings),
	})
	if not didInitialize then
		profiles[player] = nil
		statuses[player] = "Failed"
		profile:EndSession()
		player:Kick(PROFILE_LOAD_FAILURE_MESSAGE)
		return
	end

	statuses[player] = "Ready"
	syncProfileData(player, profile)
	local profileKind = if profile.SessionLoadCount == 1 then "new" else "returning"
	print(
		string.format(
			"[ODDWORKS][Persistence] Loaded %s profile for %s (%d), %s.",
			profileKind,
			player.Name,
			player.UserId,
			migrationResult
		)
	)
end

-- Synchronizes the final snapshot before explicitly ending the profile session.
-- Removing the map entry first makes the OnSessionEnd callback idempotent.
local function releasePlayer(player: Player)
	local profile = profiles[player]
	if profile then
		syncProfileData(player, profile)
		profiles[player] = nil
		if profile:IsActive() then
			profile:EndSession()
		end
		print(string.format("[ODDWORKS][Persistence] Released profile session for %s (%d).", player.Name, player.UserId))
	end

	PlayerStateService.RemovePlayerState(player)
	statuses[player] = nil
end

-- Starts after gameplay consumers have subscribed to PlayerState changes. The
-- first state notification therefore reconstructs progression, plots, displays, and HUD.
function PersistenceService.Start()
	if started then
		return
	end
	started = true

	local packages = ServerScriptService:FindFirstChild("ServerPackages")
	local profileStoreModule = packages and packages:FindFirstChild("ProfileStore")
	if not profileStoreModule or not profileStoreModule:IsA("ModuleScript") then
		error("[ODDWORKS][Persistence] ProfileStore is missing. Run `wally install` before starting the server.")
	end

	profileStoreLibrary = require(profileStoreModule)
	activeStore, activeMode = configureStore(profileStoreLibrary)
	if not activeStore then
		warn(
			string.format(
				"[ODDWORKS][Persistence] Disabled for universe %d; only Studio Mock or internal-test universe %d is allowed.",
				game.GameId,
				PersistenceConfig.INTERNAL_TEST_UNIVERSE_ID
			)
		)
	end

	profileStoreLibrary.OnError:Connect(function(message: string, storeName: string, profileKey: string)
		warn(string.format("[ODDWORKS][Persistence] ProfileStore error (%s/%s): %s", storeName, profileKey, message))
	end)

	PlayerStateService.ObserveStateChanged(function(player: Player)
		local profile = profiles[player]
		if profile and profile:IsActive() then
			syncProfileData(player, profile)
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(loadPlayer, player)
	end)
	Players.PlayerRemoving:Connect(releasePlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end

	print(string.format("[ODDWORKS][Persistence] Service started in %s mode.", activeMode))
end

-- Returns a primitive diagnostic value without exposing ProfileStore objects or save data.
function PersistenceService.GetStatus(player: Player): PersistenceStatus
	return statuses[player] or "NotLoaded"
end

return PersistenceService
