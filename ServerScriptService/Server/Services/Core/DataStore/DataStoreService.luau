--!strict
-- ServerScriptService/Server/Services/Core/DataStore/DataStoreService.luau

--[[
	DataStoreService

	Thin bridge between SessionService and the ProfileStore library.
	All it knows is how to start, save, and remove profile sessions.

	Does NOT:
	  - Know what's inside profile.Data
	  - React to player events (that's SessionService's job)
	  - Mutate profile data (that's StateService's job)

	Consumers:
	  - SessionService (LoadProfile, on player added)
]]

local Players = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Server       = ServerScriptService.Server
local Shared       = game:GetService("ReplicatedStorage").Shared

local Logger       = require(Shared.Util.Logger)
local ProfileTypes = require(Shared.Types.ProfileTypes)
local DataTemplate = require(Server.Constants.DataTemplate)
local ProfileStore = require(Server.Packages.ProfileStore)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local tostring   = tostring
local taskDelay  = task.delay

-- ─── Types ───────────────────────────────────────────────────────────────────
export type Profile     = ProfileTypes.Profile
export type ProfileData = ProfileTypes.ProfileData

-- ─── Constants ───────────────────────────────────────────────────────────────
local KEY_PREFIX  = "Player_"
local STORE_NAME  = "PlayerData"
local KICK_MSG    = "Your data failed to load. Please rejoin. If this persists, contact support."

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("DataStoreService")

local _store = ProfileStore.New(STORE_NAME, DataTemplate)
if RunService:IsStudio() then
	_store = _store.Mock
	log:warn("Running in Studio — Mock ProfileStore active")
end

-- ─── Global ProfileStore signals ─────────────────────────────────────────────
-- Wire these up once at module load. They are server-wide, not per-player.

ProfileStore.OnError:Connect(function(message: string, storeName: string, key: string)
	log:error("ProfileStore error [{}][{}]: {}", storeName, key, message)
end)

ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
	if isCritical then
		log:fatal("ProfileStore entered CRITICAL STATE — data writes may be failing")
	else
		log:info("ProfileStore critical state resolved")
	end
end)

-- ─── Module ──────────────────────────────────────────────────────────────────
local DataStoreService = {}

--[[
	LoadProfile(player)

	Starts a ProfileStore session for the given player.
	Yields until the session is acquired or the player leaves.

	Returns the Profile on success, nil on failure (player is kicked automatically).

	This is the ONLY entry point for loading player data. SessionService
	calls this once per player and owns the returned Profile object.
]]
function DataStoreService.LoadProfile(player: Player): Profile?
	local key = KEY_PREFIX .. tostring(player.UserId)

	local profile = _store:StartSessionAsync(key, {
		Cancel = function(): boolean
			-- Abort if the player left while we were waiting for the session lock.
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- ProfileStore returned nil — either the player left, or the DataStore
		-- is in a bad state. Either way, kick with a clear message.
		log:fatal(
			"Failed to acquire profile session for {} ({}) — kicking",
			player.Name, player.UserId
		)
		-- task.delay so the kick fires outside the current call stack,
		-- giving ProfileStore time to log its own error first.
		taskDelay(0, player.Kick, player, KICK_MSG)
		return nil
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile() -- fills any fields missing from an older profile

	log:debug("Profile loaded for {} (load #{})", player.Name, profile.SessionLoadCount)
	return profile
end

--[[
	RemoveData(userId)

	Permanently wipes a player's stored data.
	For use by admin tools or GDPR erasure flows only.
	Returns (ok: boolean, err: string?).
]]
function DataStoreService.RemoveData(userId: number): (boolean, string?)
	local key = KEY_PREFIX .. tostring(userId)
	local ok, err = pcall(_store.RemoveAsync, _store, key)
	if not ok then
		log:error("RemoveData failed for UserId {}: {}", userId, err)
	end
	return ok, if ok then nil else tostring(err)
end

return DataStoreService
