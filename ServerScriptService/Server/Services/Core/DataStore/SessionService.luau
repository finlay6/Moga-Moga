--!strict
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Util.Logger)


local Server = ServerScriptService.Server
local Services = Server.Services
local DataStoreService = require(Services.Core.DataStore.DataStoreService)
local DataMigrationService = require(Services.Core.DataStore.DataMigrationService)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime = os.time
local taskSpawn = task.spawn

-- ─── Types ───────────────────────────────────────────────────────────────────
export type Profile = DataStoreService.Profile
export type ProfileData = DataStoreService.ProfileData

-- ─── State ────────────────────────────────────────────────────────────────────
local log = Logger.new("SessionService")
local profiles: { [Player]: Profile } = {}

-- ─── Private Logic ────────────────────────────────────────────────────────────

local function initializeMetaData(player: Player, data: ProfileData)
	local now = osTime()

	if data.Meta.CreatedAt == 0 then
		data.Meta.CreatedAt = now
		log:info("New player detected: {} ({})", player.Name, player.UserId)
	end

	data.Meta.LastSeenAt = now
	data.Meta.JoinCount += 1
end

local function finalizeMetaData(data: ProfileData)
	local sessionStart = data.Meta.LastSeenAt
	if sessionStart > 0 then
		data.Meta.TotalPlayTime += osTime() - sessionStart
	end
	data.Meta.LastSeenAt = osTime()
end

local function onPlayerAdded(player: Player)
	-- Request the profile from the Persistence Layer
	local profile = DataStoreService:LoadProfile(player)

	if not profile then
		-- DataStoreService should handle its own logging/kicking, 
		-- but we guard here just in case.
		return 
	end

	-- Handle Session End (e.g., if ProfileStore loses ownership)
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Data session ended unexpectedly. Please rejoin.")
	end)
	
	profile.OnAfterSave:Connect(function()
		log:debug("Auto-saved for {}", player.Name)
	end)

	-- Check if player left while loading
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local success = DataMigrationService.migrate(profile.Data)
	if not success then
		player:Kick("Data migration failed. Please contact a developer.")
		return
	end
	
	initializeMetaData(player, profile.Data)

	profiles[player] = profile
	log:info("Session started for {} (Session #{})", player.Name, profile.SessionLoadCount)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then return end

	finalizeMetaData(profile.Data)

	-- Tell the persistence layer we are done
	profile:EndSession()
	profiles[player] = nil

	log:debug("Session cleaned up for {}", player.Name)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

local SessionService = {}

function SessionService:init()
	-- Handle players already in the server (Studio/Fast Loading)
	for _, player in Players:GetPlayers() do
		taskSpawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	log:info("SessionService initialised")
end

--- Returns the full Profile object for a player. Rare call
function SessionService.GetProfile(player: Player): Profile?
	return profiles[player]
end

--- Helper function specifically for StateService to get raw Data.
function SessionService.GetData(player: Player): ProfileData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

--- Yields until a profile is loaded or the timeout is reached.
function SessionService.WaitForProfile(player: Player, timeout: number?): Profile?
	local limit = timeout or 10
	local elapsed = 0
	while not profiles[player] and elapsed < limit do
		elapsed += task.wait(0.1)
	end
	return profiles[player]
end

return SessionService