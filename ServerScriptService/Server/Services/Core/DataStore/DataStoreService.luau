--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Util.Logger)
local DataTemplate = require(ServerScriptService.Server.Constants.DataTemplate)

-- Assuming ProfileStore is in your Packages
local ProfileStore = require(ServerScriptService.Server.Packages.ProfileStore)

-- ─── Types ────────────────────────────────────────────────────────────────────
export type ProfileData = typeof(DataTemplate)
export type Profile = {
	Data: ProfileData,
	IsActive: (self: any) -> boolean,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
	Save: (self: any) -> (),
	OnSessionEnd: RBXScriptSignal,
	OnAfterSave: RBXScriptSignal,
	SessionLoadCount: number,
}

-- ─── Constants ────────────────────────────────────────────────────────────────
local PROFILE_KEY_PREFIX = "Player_"
local STORE_NAME = "PlayerData"

-- ─── State ────────────────────────────────────────────────────────────────────
local log = Logger.new("DataStoreService")

local PlayerStore = ProfileStore.New(STORE_NAME, DataTemplate)
if RunService:IsStudio() then
	PlayerStore = PlayerStore.Mock
	log:warn("Studio mode — using Mock ProfileStore")
end

-- ─── Global Signals ──────────────────────────────────────────────────────────
ProfileStore.OnError:Connect(function(msg, store, key)
	log:error("ProfileStore error — Store:{} Key:{} — {}", store, key, msg)
end)

ProfileStore.OnCriticalToggle:Connect(function(isCritical)
	if isCritical then
		log:fatal("ProfileStore entered CRITICAL STATE")
	else
		log:info("ProfileStore critical state resolved")
	end
end)

-- ─── Service ──────────────────────────────────────────────────────────────────
local DataStoreService = {}

--- The bridge between SessionService and the Database.
function DataStoreService:LoadProfile(player: Player): Profile
	local key = PROFILE_KEY_PREFIX .. tostring(player.UserId)

	local profile = PlayerStore:StartSessionAsync(key, {
		Cancel = function()
			return player.Parent ~= game:GetService("Players")
		end,
	})

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		return profile
	else
		log:fatal("Failed to load profile for {} — kick required", player.Name)
		player:Kick("Data failed to load. Please rejoin.")
		return nil
	end
end

--- Used for admin tools or data resets.
function DataStoreService:RemoveData(userId: number)
	local key = PROFILE_KEY_PREFIX .. tostring(userId)
	local ok, err = pcall(function()
		PlayerStore:RemoveAsync(key)
	end)
	return ok, err
end

return DataStoreService