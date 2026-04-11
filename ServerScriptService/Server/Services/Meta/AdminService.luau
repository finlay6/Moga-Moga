--!strict
-- ServerScriptService/Server/Services/Meta/AdminService.luau

--[[
	AdminService

	Central authority for player ranks and staff status.

	Responsibilities:
	  - Resolving each player's rank from AdminConstants.STAFF_LIST on join
	  - Mirroring VIP status into the rank cache (rank 1) when VIPService fires
	  - Caching resolved PlayerRankStatus per player
	  - Exposing permission checks via can(player, capability)
	  - Exposing isStaff / getRank / getRankInfo for other services

	Does NOT:
	  - Handle chat commands or in-game admin actions (AdminCommandService)
	  - Know about the nametag UI (NametagService reads from AdminService)
	  - Grant or revoke VIP (VIPService owns that)

	─── Rank resolution order ──────────────────────────────────────────
	  1. Check STAFF_LIST — hardcoded staff always win
	  2. If VIPService reports isVIP and no staff rank, assign RANK.VIP (1)
	  3. Otherwise RANK.NONE (0)

	─── How other services read rank ───────────────────────────────────
	  NametagService:
	    local info = AdminService.getRankInfo(player)
	    -- info.badgeImageId, info.nameColor, info.label, etc.

	  Any permission gate:
	    if AdminService.can(player, AdminConstants.PERMISSIONS.KICK_PLAYERS) then
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared  = ReplicatedStorage.Shared
local Server  = ServerScriptService.Server

local AdminConstants = require(Shared.Constants.Meta.AdminConstants)
local AdminTypes     = require(Shared.Types.AdminTypes)
local Logger         = require(Shared.Util.Logger)
local Signal         = require(Shared.Packages.Signal)
local SessionService = require(Server.Services.Core.DataStore.SessionService)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime    = os.time
local taskSpawn = task.spawn

-- ─── Types ───────────────────────────────────────────────────────────────────
type RankLevel        = AdminTypes.RankLevel
type RankInfo         = AdminTypes.RankInfo
type PlayerRankStatus = AdminTypes.PlayerRankStatus

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("AdminService")

-- Per-player rank cache. Populated on PlayerReady, updated if VIP changes.
local _rankCache: { [Player]: PlayerRankStatus } = {}

-- Pre-built userId → rank level map from STAFF_LIST for O(1) lookups.
local _staffRankMap: { [number]: RankLevel } = {}
for _, entry in AdminConstants.STAFF_LIST do
	_staffRankMap[entry.userId] = entry.rank
end

-- Lazily resolved VIPService reference to avoid a circular require.
-- AdminService never requires VIPService at the top level.
local _vipService: any = nil

-- ─── Module ──────────────────────────────────────────────────────────────────
local AdminService = {}

-- ─── Private ─────────────────────────────────────────────────────────────────

local function _getRankInfo(level: RankLevel): RankInfo
	-- Walk down from the given level to find the closest defined rank.
	local best: RankInfo = AdminConstants.RANKS[0]
	for rankLevel, info in AdminConstants.RANKS do
		if rankLevel <= level and rankLevel > best.level then
			best = info
		end
	end
	return best
end

local function _resolveRankLevel(player: Player): RankLevel
	-- 1. Hardcoded staff list always takes priority.
	local staffRank = _staffRankMap[player.UserId]
	if staffRank ~= nil then
		return staffRank
	end

	-- 2. Mirror VIP status as rank 1 if VIPService is available.
	if _vipService ~= nil and _vipService.isVIP(player) then
		return AdminConstants.RANK.VIP
	end

	return AdminConstants.RANK.NONE
end

local function _buildStatus(player: Player): PlayerRankStatus
	local level = _resolveRankLevel(player)
	return {
		userId     = player.UserId,
		rankLevel  = level,
		rankInfo   = _getRankInfo(level),
		resolvedAt = osTime(),
	}
end

local function _resolveAndCache(player: Player)
	local status = _buildStatus(player)
	_rankCache[player] = status

	local label = if status.rankInfo.label ~= "" then status.rankInfo.label else "none"
	log:debug("{} resolved rank: {} (level {})", player.Name, label, status.rankLevel)

	AdminService.RankResolved:Fire(player, status)
end

--[[
	RankResolved : Signal<Player, PlayerRankStatus>

	Fires when a player's rank is first resolved or updated.
	NametagService connects here to refresh the billboard.
]]
AdminService.RankResolved = Signal() :: Signal.Signal<Player, PlayerRankStatus>

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	getRankLevel(player) → RankLevel

	Returns the player's numeric rank level.
	Returns RANK.NONE (0) if not yet resolved or not in the server.
]]
function AdminService.getRankLevel(player: Player): RankLevel
	local status = _rankCache[player]
	return if status ~= nil then status.rankLevel else AdminConstants.RANK.NONE
end

--[[
	getRankInfo(player) → RankInfo

	Returns the full RankInfo for the player's current rank.
	Includes label, colors, badge asset, and canEditName.
]]
function AdminService.getRankInfo(player: Player): RankInfo
	local status = _rankCache[player]
	if status ~= nil then
		return status.rankInfo
	end
	return AdminConstants.RANKS[0]
end

--[[
	getStatus(player) → PlayerRankStatus?

	Returns the full resolved status struct, or nil if not yet loaded.
]]
function AdminService.getStatus(player: Player): PlayerRankStatus?
	return _rankCache[player]
end

--[[
	isStaff(player) → boolean

	Returns true if the player has any rank above VIP.
	Moderator, Admin, Developer, Owner all qualify.
]]
function AdminService.isStaff(player: Player): boolean
	return AdminService.getRankLevel(player) >= AdminConstants.RANK.MODERATOR
end

--[[
	isOwner(player) → boolean
]]
function AdminService.isOwner(player: Player): boolean
	return AdminService.getRankLevel(player) >= AdminConstants.RANK.OWNER
end

--[[
	can(player, permissionThreshold) → boolean

	General permission gate. Pass a value from AdminConstants.PERMISSIONS.

	Example:
	  if AdminService.can(player, AdminConstants.PERMISSIONS.KICK_PLAYERS) then
	      -- allow kick
	  end
]]
function AdminService.can(player: Player, permissionThreshold: number): boolean
	return AdminService.getRankLevel(player) >= permissionThreshold
end

--[[
	canEditName(player) → boolean

	Returns true if the player is allowed to set a custom display name.
	Staff ranks and VIP can edit; regular players cannot.
]]
function AdminService.canEditName(player: Player): boolean
	return AdminService.getRankInfo(player).canEditName
end

--[[
	refreshRank(player)

	Re-resolves and re-caches a player's rank.
	Call this after VIPService.VIPStatusChanged fires so the rank cache
	stays in sync with VIP status changes mid-session.
]]
function AdminService.refreshRank(player: Player)
	_resolveAndCache(player)
end

--[[
	getStaffOnline() → { PlayerRankStatus }

	Returns rank statuses for all online staff (rank ≥ MODERATOR).
	Useful for admin dashboards or logging.
]]
function AdminService.getStaffOnline(): { PlayerRankStatus }
	local result: { PlayerRankStatus } = {}
	for _, status in _rankCache do
		if status.rankLevel >= AdminConstants.RANK.MODERATOR then
			result[#result + 1] = status
		end
	end
	return result
end

--[[
	getAllRanks() → { [number]: RankInfo }

	Returns the full rank definition table from AdminConstants.
	Useful for UI that needs to render all rank options.
]]
function AdminService.getAllRanks(): { [number]: RankInfo }
	return AdminConstants.RANKS
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--[[
	init(vipService?)

	Wires VIPStatusChanged if a VIPService reference is provided.
	VIPService is optional — AdminService works without it, players
	just won't get rank 1 from VIP alone.
]]
function AdminService.init(vipService: any?)
	_vipService = vipService

	if _vipService ~= nil then
		-- When VIP status changes mid-session, re-resolve the rank so
		-- NametagService gets an updated badge immediately.
		_vipService.VIPStatusChanged:Connect(function(player: Player)
			if _rankCache[player] ~= nil then
				_resolveAndCache(player)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		_rankCache[player] = nil
	end)

	log:info("AdminService initialised")
end

function AdminService.start()
	-- Resolve rank after each player's profile is ready.
	SessionService.PlayerReady:Connect(function(player: Player)
		taskSpawn(_resolveAndCache, player)
	end)

	-- Handle players already past the ready gate.
	for _, player in Players:GetPlayers() do
		if SessionService.GetData(player) ~= nil then
			taskSpawn(_resolveAndCache, player)
		end
	end

	log:info("AdminService started")
end

return AdminService
