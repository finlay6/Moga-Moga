--!strict

local Players          = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared           = ReplicatedStorage.Shared
local Native           = require(Shared.Util.Native)
local Logger           = require(Shared.Util.Logger)
local ValidatorUtil    = require(Shared.Util.ValidatorUtil)
local DataTemplate     = require(ServerScriptService.Server.Constants.DataTemplate)

local Packages         = Shared.Packages
local ProfileStore     = require(ServerScriptService.Server.Packages.ProfileStore)
local Sera             = require(Packages.Sera)

local Services         = script.Parent
local DataMigration    = require(Services.DataMigrationService)

local spawn    = Native.spawn
local osTime   = Native.time

-- ─── Types ────────────────────────────────────────────────────────────────────

export type ProfileData = typeof(DataTemplate)

export type Profile = {
	Data             : ProfileData,
	LastSavedData    : ProfileData,
	FirstSessionTime : number,
	SessionLoadCount : number,
	IsActive         : (self: any) -> boolean,
	Reconcile        : (self: any) -> (),
	EndSession       : (self: any) -> (),
	AddUserId        : (self: any, userId: number) -> (),
	Save             : (self: any) -> (),
	OnSessionEnd     : RBXScriptSignal,
	OnAfterSave      : RBXScriptSignal,
}

-- ─── Sera Schema ─────────────────────────────────────────────────────────────
--
-- Defines the structure of player stats that get broadcast to clients.
-- Sera handles all buffer layout, serialisation, and delta encoding.
-- Only fields the client actually needs to display UI are included here.
--
-- To send a full update:
--   local buf, err = Sera.Serialize(StatsSchema, statsTable)
--
-- To send only changed fields (e.g. just cash changed):
--   local buf, err = Sera.DeltaSerialize(StatsSchema, deltaTable)
--
-- Client deserialises with:
--   local stats = Sera.Deserialize(StatsSchema, buf)
--   local stats, offset = Sera.DeltaDeserialize(StatsSchema, buf, offset)

local StatsSchema = Sera.Schema({
	Cash            = Sera.Uint32,
	Gems            = Sera.Uint16,
	LoyaltyPoints   = Sera.Uint16,
	VIPTier         = Sera.Uint8,
	Level           = Sera.Uint8,
	XP              = Sera.Uint32,
	ArcadeCoins     = Sera.Uint16,
	FreeSpins       = Sera.Uint8,
})

local function buildStatsTable(data: ProfileData): { [string]: number }
	return {
		Cash          = data.Economy.Cash,
		Gems          = data.Economy.Gems,
		LoyaltyPoints = data.Cafe.LoyaltyPoints,
		VIPTier       = data.VIP.Tier,
		Level         = data.Progression.Level,
		XP            = data.Progression.XP,
		ArcadeCoins   = data.Arcade.TotalCoinsEarned,
		FreeSpins     = data.SpinWheel.FreeSpinsAvailable,
	}
end

local function serializeStats(data: ProfileData): (buffer?, string?)
	return Sera.Serialize(StatsSchema, buildStatsTable(data))
end

local function deserializeStats(buf: buffer): { [string]: number }
	return Sera.Deserialize(StatsSchema, buf)
end

local function deltaSerializeStats(delta: { [string]: number }): (buffer?, string?)
	return Sera.DeltaSerialize(StatsSchema, delta)
end

-- ─── Constants ────────────────────────────────────────────────────────────────

local PATCH_TOPIC        = "DataService:GlobalPatch"
local PROFILE_KEY_PREFIX = "Player_"

-- ─── State ────────────────────────────────────────────────────────────────────

local log      = Logger.new("DataService")
local profiles : { [Player]: Profile } = {}

local PlayerStore = ProfileStore.New("PlayerData", DataTemplate)
if RunService:IsStudio() then
	PlayerStore = PlayerStore.Mock
	log:warn("Studio mode — using Mock ProfileStore")
end

-- ─── Patch Utility ────────────────────────────────────────────────────────────

local function applyPatch(data: ProfileData, patch: { [string]: any })
	for path, value in patch do
		local keys = string.split(path, ".")
		local node = data :: any
		for i = 1, #keys - 1 do
			node = node[keys[i]]
			if node == nil then
				log:warn("Patch path '{}' invalid at '{}'", path, keys[i])
				break
			end
		end
		if node ~= nil then
			node[keys[#keys]] = value
		end
	end
end

-- ─── Session Lifecycle ────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	local key = PROFILE_KEY_PREFIX .. tostring(player.UserId)

	local profile = PlayerStore:StartSessionAsync(key, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		log:fatal("Nil profile for {} — server shutting down", player.Name)
		player:Kick("Failed to load data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	DataMigration.migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		log:debug("Session ended for {}", player.Name)
		player:Kick("Your session was ended. Please rejoin.")
	end)

	profile.OnAfterSave:Connect(function()
		log:debug("Auto-saved for {}", player.Name)
	end)

	if player.Parent ~= Players then
		log:info("Player {} left before profile loaded", player.Name)
		profile:EndSession()
		return
	end

	local data = profile.Data
	local now  = osTime()

	if data.Meta.CreatedAt == 0 then
		data.Meta.CreatedAt = now
		log:info("New player: {} (UserId: {})", player.Name, player.UserId)
	end

	data.Meta.LastSeenAt = now
	data.Meta.JoinCount += 1

	profiles[player] = profile
	log:info("Profile loaded for {} (Session #{})", player.Name, profile.SessionLoadCount)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then return end

	local data = profile.Data
	local sessionStart = data.Meta.LastSeenAt
	if sessionStart > 0 then
		data.Meta.TotalPlayTime += osTime() - sessionStart
	end
	data.Meta.LastSeenAt = osTime()

	profile:EndSession()
	profiles[player] = nil
	log:info("Session ended for {}", player.Name)
end

-- ─── Global Patch Subscription ────────────────────────────────────────────────

local function subscribeToPatchBroadcasts()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(PATCH_TOPIC, function(msg)
			local patch = msg.Data :: { [string]: any }
			if type(patch) ~= "table" then
				log:warn("Invalid patch broadcast — expected table")
				return
			end
			for player, profile in profiles do
				if profile:IsActive() then
					local pOk, pErr = pcall(applyPatch, profile.Data, patch)
					if not pOk then
						log:error("Patch failed for {}: {}", player.Name, pErr)
					end
				end
			end
		end)
	end)
	if not ok then log:warn("Patch subscription failed: {}", err) end
end

-- ─── ProfileStore Global Signals ─────────────────────────────────────────────

ProfileStore.OnError:Connect(function(msg, store, key)
	log:error("ProfileStore error — Store:{} Key:{} — {}", store, key, msg)
end)

ProfileStore.OnOverwrite:Connect(function(store, key)
	log:warn("Overwrite detected — Store:{} Key:{}", store, key)
end)

ProfileStore.OnCriticalToggle:Connect(function(isCritical)
	if isCritical then
		log:fatal("ProfileStore entered CRITICAL STATE")
	else
		log:info("ProfileStore critical state resolved")
	end
end)

-- ─── Public API ───────────────────────────────────────────────────────────────

local DataService = {}

-- Sera schema and helpers exposed so other services can
-- serialise/deserialise stats without depending on DataService internals
DataService.StatsSchema       = StatsSchema
DataService.serializeStats    = serializeStats
DataService.deserializeStats  = deserializeStats
DataService.deltaSerializeStats = deltaSerializeStats

function DataService:init()
	subscribeToPatchBroadcasts()
	for _, player in Players:GetPlayers() do
		spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	log:info("DataService initialised")
end

function DataService.getProfile(player: Player): Profile?
	return profiles[player]
end

function DataService.getData(player: Player): ProfileData?
	local p = profiles[player]
	return if p then p.Data else nil
end

function DataService.waitForProfile(player: Player, timeout: number?): Profile?
	local limit   = timeout or 10
	local elapsed = 0
	while profiles[player] == nil and elapsed < limit do
		task.wait(0.1)
		elapsed += 0.1
	end
	return profiles[player]
end

function DataService.saveNow(player: Player)
	local p = profiles[player]
	if p == nil then
		log:warn("saveNow: no profile loaded for {}", player.Name)
		return
	end
	p:Save()
	log:debug("Manual save triggered for {}", player.Name)
end

-- ─── Global Patch ─────────────────────────────────────────────────────────────

function DataService.broadcastPatch(patch: { [string]: any })
	ValidatorUtil.validate(patch, ValidatorUtil.isTable, "broadcastPatch")

	for player, profile in profiles do
		if profile:IsActive() then
			local ok, err = pcall(applyPatch, profile.Data, patch)
			if not ok then
				log:error("Local patch failed for {}: {}", player.Name, err)
			end
		end
	end

	local ok, err = pcall(function()
		MessagingService:PublishAsync(PATCH_TOPIC, patch)
	end)

	if ok then
		log:info("Patch broadcast sent")
	else
		log:error("Patch broadcast failed: {}", err)
	end
end

-- ─── Profile Deletion ─────────────────────────────────────────────────────────

function DataService.deleteProfile(userId: number): boolean
	ValidatorUtil.validate(userId, ValidatorUtil.isPositiveInteger, "deleteProfile")

	local key = PROFILE_KEY_PREFIX .. tostring(userId)

	for player, profile in profiles do
		if player.UserId == userId then
			log:warn("Deleting profile for online player {} — ending session", player.Name)
			profile:EndSession()
			profiles[player] = nil
			player:Kick("Your data has been reset by an administrator.")
			break
		end
	end

	local ok, err = pcall(function()
		PlayerStore:RemoveAsync(key)
	end)

	if ok then
		log:info("Profile permanently deleted for UserId {}", userId)
		return true
	else
		log:error("Delete failed for UserId {}: {}", userId, err)
		return false
	end
end

-- ─── Version Query ────────────────────────────────────────────────────────────

function DataService.getVersionQuery(
	userId: number,
	sortDir: Enum.SortDirection?,
	minDate: DateTime?,
	maxDate: DateTime?
)
	local key = PROFILE_KEY_PREFIX .. tostring(userId)
	return PlayerStore:VersionQuery(key, sortDir, minDate, maxDate)
end

return DataService