--!strict
-- ServerScriptService/Server/Services/Core/DataStore/SessionService.luau

--[[
	SessionService

	Owns the player lifecycle: loading profiles, tracking active sessions,
	and finalising data on leave.

	Responsibilities:
	  - Loading profiles via DataStoreService (yields, handles failures)
	  - Running DataMigrationService once per session after load
	  - Initialising and finalising Meta fields (join time, play time, etc.)
	  - Providing a safe read-access API for other services (GetData, GetProfile)
	  - Exposing WaitForProfile for services that race the load

	Does NOT:
	  - Write gameplay data (EconomyService, VIPService own their sections)
	  - Know what's inside profile.Data beyond the Meta section
	  - Own the persistence mechanism (DataStoreService does that)
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared   = ReplicatedStorage.Shared
local Server   = ServerScriptService.Server
local Services = Server.Services
local Core     = Services.Core

local Logger               = require(Shared.Util.Logger)
local ProfileTypes         = require(Shared.Types.ProfileTypes)
local DataStoreService     = require(Core.DataStore.DataStoreService)
local DataMigrationService = require(Core.DataStore.DataMigrationService)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime    = os.time
local taskSpawn = task.spawn
local taskWait  = task.wait

-- ─── Types ───────────────────────────────────────────────────────────────────
export type Profile     = ProfileTypes.Profile
export type ProfileData = ProfileTypes.ProfileData

-- ─── Constants ───────────────────────────────────────────────────────────────
local WAIT_PROFILE_POLL_RATE = 0.05  -- seconds between WaitForProfile polls
local KICK_MIGRATION_FAILED  =
	"Your save data could not be migrated safely. "
	.. "Please contact support and do not rejoin — your data is safe."

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("SessionService")

-- Active profile map. Profiles are inserted here only after migration succeeds.
-- All other services should treat a nil entry as "player data not ready yet".
local _profiles: { [Player]: Profile } = {}

-- ─── Private: Meta Helpers ───────────────────────────────────────────────────

--[[
	_initMeta(player, data)

	Called once per session after a profile is loaded and migrated.
	Sets join metadata. Does NOT touch LastSeenAt — that field is for
	disconnects only. SessionStartAt tracks when THIS session began.

	BUG FIXED (original code): LastSeenAt was used as both "session start"
	and "last disconnect". This caused TotalPlayTime to be calculated from
	the last DISCONNECT time (wrong) rather than the current JOIN time (correct).
	SessionStartAt is now a dedicated field that lives only for the session duration.
]]
local function _initMeta(player: Player, data: ProfileData)
	local now = osTime()
	local meta = data.Meta

	if meta.CreatedAt == 0 then
		meta.CreatedAt = now
		log:info("First-ever join for {} ({})", player.Name, player.UserId)
	end

	-- Record when THIS session started.
	-- finalizeMetaData reads this field — not LastSeenAt.
	meta.SessionStartAt = now
	meta.JoinCount      += 1

	log:debug(
		"Meta initialised for {} — join #{}, started at {}",
		player.Name, meta.JoinCount, now
	)
end

--[[
	_finaliseMeta(data)

	Called on PlayerRemoving before EndSession.
	Accumulates total play time using SessionStartAt (not LastSeenAt).
	Updates LastSeenAt to now so we know when they last disconnected.
]]
local function _finaliseMeta(data: ProfileData)
	local now  = osTime()
	local meta = data.Meta

	if meta.SessionStartAt > 0 then
		local sessionLength = now - meta.SessionStartAt
		meta.TotalPlayTime  += sessionLength
	end

	meta.LastSeenAt     = now
	meta.SessionStartAt = 0 -- reset so a stale value can't corrupt the next session
end

-- ─── Private: Player Lifecycle ───────────────────────────────────────────────

local function _onPlayerAdded(player: Player)
	-- 1. Load profile (yields — may take several frames)
	local profile = DataStoreService.LoadProfile(player)
	if profile == nil then
		-- DataStoreService already kicked the player; nothing more to do.
		return
	end

	-- 2. Guard: player may have left while we were loading.
	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		log:debug("Player {} left during profile load — session ended immediately", player.Name)
		return
	end

	-- 3. Handle unexpected session loss (ProfileStore ownership stolen, etc.)
	profile.OnSessionEnd:Connect(function()
		if _profiles[player] then
			_profiles[player] = nil
			log:warn("Profile session ended unexpectedly for {} — kicking", player.Name)
			player:Kick("Your data session ended unexpectedly. Please rejoin.")
		end
	end)

	profile.OnAfterSave:Connect(function()
		log:debug("Auto-save completed for {}", player.Name)
	end)

	-- 4. Run migrations before any other service reads the data.
	local migrationOk = DataMigrationService.migrate(profile.Data)
	if not migrationOk then
		profile:EndSession()
		player:Kick(KICK_MIGRATION_FAILED)
		log:error("Migration failed for {} — session ended", player.Name)
		return
	end

	-- 5. Stamp join metadata now that the data is confirmed safe.
	_initMeta(player, profile.Data)

	-- 6. Publish to the active map — other services can now read this player's data.
	_profiles[player] = profile

	log:info(
		"Session ready for {} — session #{}, DataVersion {}",
		player.Name,
		profile.SessionLoadCount,
		profile.Data.Meta.DataVersion
	)
end

local function _onPlayerRemoving(player: Player)
	local profile = _profiles[player]
	if profile == nil then return end

	-- Remove from map first so any signal handlers that run during EndSession
	-- don't see a stale entry and try to kick an already-leaving player.
	_profiles[player] = nil

	_finaliseMeta(profile.Data)
	profile:EndSession()

	log:debug("Session finalised for {}", player.Name)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

local SessionService = {}

--[[
	init()

	Wires up PlayerAdded / PlayerRemoving and handles players
	already in the server (Studio testing, fast-loaded scripts).
]]
function SessionService.init()
	-- Handle players already present before this script ran.
	for _, player in Players:GetPlayers() do
		taskSpawn(_onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(function(player)
		taskSpawn(_onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(_onPlayerRemoving)

	log:info("SessionService initialised")
end

--[[
	GetProfile(player) → Profile?

	Returns the full Profile object, or nil if not yet loaded.
	Prefer GetData when you only need to read profile.Data.
]]
function SessionService.GetProfile(player: Player): Profile?
	return _profiles[player]
end

--[[
	GetData(player) → ProfileData?

	Convenience accessor for the raw data table.
	Returns nil if the player's profile is not yet in the active map.
]]
function SessionService.GetData(player: Player): ProfileData?
	local profile = _profiles[player]
	return if profile ~= nil then profile.Data else nil
end

--[[
	WaitForProfile(player, timeout?) → Profile?

	Yields the calling coroutine until the profile is loaded or timeout expires.
	Default timeout is 10 seconds. Returns nil on timeout.

	Use this in services that are spawned concurrently with SessionService
	(e.g. VIPService.start) and need to be certain the data is ready.
]]
function SessionService.WaitForProfile(player: Player, timeout: number?): Profile?
	local deadline = osTime() + (timeout or 10)
	while _profiles[player] == nil and osTime() < deadline do
		if not player:IsDescendantOf(Players) then
			return nil -- player left, stop waiting
		end
		taskWait(WAIT_PROFILE_POLL_RATE)
	end
	return _profiles[player]
end

return SessionService
