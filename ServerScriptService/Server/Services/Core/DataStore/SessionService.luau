--!strict
-- ServerScriptService/Server/Services/Core/DataStore/SessionService.luau

--[[
	SessionService

	Owns the player lifecycle: loading profiles, tracking active sessions,
	and finalising data on leave.

	Responsibilities:
	  - Loading profiles via PersistenceService (yields, handles failures)
	  - Running DataMigrationService once per session after load
	  - Stamping Meta fields (join time, play time, session count)
	  - Providing GetData / GetProfile for StateService
	  - Firing PlayerReady after data is confirmed safe

	Does NOT:
	  - Write gameplay data (that is EconomyService, VIPService, etc.)
	  - Know what is inside profile.Data beyond the Meta section
	  - Own the persistence mechanism (PersistenceService does that)

	─── PlayerReady signal ─────────────────────────────────────────────
	Fire order guarantee:
	  1. Profile loaded
	  2. Migration applied
	  3. Meta stamped
	  4. Profile inserted into _profiles
	  5. PlayerReady fires

	Any service that needs player data on join should connect to
	SessionService.PlayerReady instead of Players.PlayerAdded.
	By the time PlayerReady fires, StateService.Get will never return nil
	for that player.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared   = ReplicatedStorage.Shared
local Server   = ServerScriptService.Server
local Core     = Server.Services.Core
local Packages = Server.Packages

local Logger               = require(Shared.Util.Logger)
local Signal               = require(Shared.Packages.Signal)
local ProfileTypes         = require(Shared.Types.ProfileTypes)
local PersistenceService   = require(Core.DataStore.PersistenceService)
local DataMigrationService = require(Core.DataStore.DataMigrationService)

local Replica = require(Packages.ReplicaServer)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime    = os.time
local taskSpawn = task.spawn

-- ─── Types ───────────────────────────────────────────────────────────────────
export type Profile     = ProfileTypes.Profile
export type ProfileData = ProfileTypes.ProfileData

-- ─── Constants ───────────────────────────────────────────────────────────────
local KICK_MIGRATION_FAILED =
	"Your save data could not be migrated safely. "
	.. "Please contact support — your data is safe, do not rejoin repeatedly."

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("SessionService")

-- Profiles are inserted here only after migration succeeds and meta is stamped.
-- A nil entry means the player's data is not ready yet.
local _profiles: { [Player]: Profile } = {}
local _playerReplicas = {}

-- ─── Module ──────────────────────────────────────────────────────────────────
local SessionService = {}

local PlayerToken = Replica.Token("PlayerData")

-- ─── Private: Meta ───────────────────────────────────────────────────────────

local function _stampJoinMeta(player: Player, data: ProfileData)
	local now  = osTime()
	local meta = data.Meta

	if meta.CreatedAt == 0 then
		meta.CreatedAt = now
		log:info("First-ever join for {} ({})", player.Name, player.UserId)
	end

	meta.SessionStartAt = now
	meta.JoinCount      += 1
end

local function _stampLeaveMeta(data: ProfileData)
	local now  = osTime()
	local meta = data.Meta

	if meta.SessionStartAt > 0 then
		meta.TotalPlayTime += now - meta.SessionStartAt
	end

	meta.LastSeenAt     = now
	meta.SessionStartAt = 0
end

local function _makePlayerReplica(player: Player, data: ProfileData)
	local replica = Replica.New({
		Token = PlayerToken,
		Tags = {UserId = player.UserId},
		Data = data,
	})
	
	replica:Subscribe(player)

	return replica
end

-- ─── Private: Lifecycle ──────────────────────────────────────────────────────

local function _onPlayerAdded(player: Player)
	local profile = PersistenceService.LoadProfile(player)
	if profile == nil then
		return  -- PersistenceService already kicked the player
	end

	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		log:debug("{} left during profile load — session ended immediately", player.Name)
		return
	end

	profile.OnSessionEnd:Connect(function()
		if _profiles[player] then
			_profiles[player] = nil
			log:warn("Profile session ended unexpectedly for {} — kicking", player.Name)
			player:Kick("Your data session ended unexpectedly. Please rejoin.")
		end
	end)

	local migrationOk = DataMigrationService.migrate(profile.Data)
	if not migrationOk then
		profile:EndSession()
		player:Kick(KICK_MIGRATION_FAILED)
		log:error("Migration failed for {} — session ended", player.Name)
		return
	end

	_stampJoinMeta(player, profile.Data)

	-- Insert before firing so any PlayerReady handler that calls GetData
	-- immediately gets a non-nil result.
	_profiles[player] = profile

	log:info(
		"Session ready for {} — join #{}, DataVersion {}",
		player.Name,
		profile.Data.Meta.JoinCount,
		profile.Data.Meta.DataVersion
	)

	SessionService.PlayerReady:Fire(player)
end

local function _onPlayerRemoving(player: Player)
	local profile = _profiles[player]
	if profile == nil then return end

	_profiles[player] = nil
	_stampLeaveMeta(profile.Data)
	profile:EndSession()

	log:debug("Session finalised for {}", player.Name)
end

local function _updatePlayerReplica(player: Player, path: {string}, value: any)
	local thisPlayerReplica = _playerReplicas[player]
	
	if thisPlayerReplica == nil then
		log:error("Player Plum not found, Player: {}", player.Name)
		return
	end

	thisPlayerReplica:Set(path, value)
end

--[[
	PlayerReady : Signal<Player>

	Fires after the profile is loaded, migrated, and meta-stamped.
	StateService.Get is safe to call for this player from this point on.

	Use this instead of Players.PlayerAdded in any service that reads
	or writes player data on join.
]]
SessionService.PlayerReady = Signal() :: Signal.Signal<Player>

--[[
	GetProfile(player) → Profile?

	Returns the full Profile object, or nil if not yet loaded.
	Prefer GetData when you only need profile.Data.
]]
function SessionService.GetProfile(player: Player): Profile?
	return _profiles[player]
end

--[[
	GetData(player) → ProfileData?

	Returns the raw data table, or nil if the profile is not yet loaded.
	Only StateService should call this.
]]
function SessionService.GetData(player: Player): ProfileData?
	local profile = _profiles[player]
	return if profile ~= nil then profile.Data else nil
end

function SessionService.UpdatePlayerReplica(player: Player, path: {string}, value: any)
	_updatePlayerReplica(player, path, value)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function SessionService.init()
	for _, player in Players:GetPlayers() do
		taskSpawn(_onPlayerAdded, player)
	end
	
	Replica.NewReadyPlayer:Connect(function(player)
		local profile = SessionService.GetProfile(player)
		local thisPlayerReplica = _makePlayerReplica(player, profile.Data)
		_playerReplicas[player] = thisPlayerReplica
	end)

	Players.PlayerAdded:Connect(function(player)
		taskSpawn(_onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(_onPlayerRemoving)

	log:info("SessionService initialised")
end

return SessionService
