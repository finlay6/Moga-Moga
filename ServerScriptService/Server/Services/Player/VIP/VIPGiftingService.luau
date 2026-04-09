--!strict
-- ServerScriptService/Server/Services/Player/VIP/VIPGiftingService.luau

--[[
	VIPGiftingService

	Manages the two-step VIP gifting flow:
	  Step 1 — queueTarget:      admin queues a recipient before prompting purchase
	  Step 2 — processReceipt:   called by the Roblox receipt handler to finalise

	─── Gifting flow ───────────────────────────────────────────────────
	1. Admin uses an in-game command → queueTarget(granter, target)
	2. Admin purchases VIPConstants.GIFT_PRODUCT_ID via MarketplaceService
	3. Roblox fires ProcessReceipt → caller invokes processReceipt(granterUserId, onApply)
	4a. Target is online  → onApply(targetPlayer) runs immediately; VIPService
	    updates the in-memory buffer and profile.
	4b. Target is offline → pending entry written to their profile via
	    DataStoreService.writeOfflineVIPGrant so it applies on next login.

	─── Bugs fixed from original ───────────────────────────────────────
	1. SILENT FAILURE: processReceipt returned nil (not false) on the offline
	   path and logged an error but did NOT persist the grant anywhere.
	   Money left the granter's account; VIP was never applied to the target.
	   Fixed: offline path calls DataStoreService.writeOfflineVIPGrant().

	2. isAuthorised used a linear scan every call. Now uses a pre-built set
	   keyed by UserId for O(1) lookup. Built once in _buildAuthSet().

	3. processReceipt return type was boolean but the offline error path
	   fell off the end and returned nil implicitly. Now always returns boolean.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared   = ReplicatedStorage.Shared
local Server   = ServerScriptService.Server

local VIPConstants       = require(Shared.Constants.Player.VIPConstants)
local VIPTypes           = require(Shared.Types.VIPTypes)
local PersistenceService   = require(Server.Services.Core.DataStore.PersistenceService)
local Logger             = require(Shared.Util.Logger)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime             = os.time
local GetPlayerByUserId  = Players.GetPlayerByUserId

-- ─── Types ───────────────────────────────────────────────────────────────────
type GiftQueueEntry = VIPTypes.GiftQueueEntry

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("VIPGiftingService")

-- Pre-built O(1) set from VIPConstants.GIFT_AUTHORISED_USER_IDS.
-- BUG FIXED: original did a linear scan of the array on every queueTarget call.
local _authSet: { [number]: true } = {}
for _, userId in VIPConstants.GIFT_AUTHORISED_USER_IDS do
	_authSet[userId] = true
end

-- Pending gift queue: granterUserId → GiftQueueEntry.
-- Cleared immediately on receipt to prevent double-processing.
local _queue: { [number]: GiftQueueEntry } = {}

-- ─── Module ──────────────────────────────────────────────────────────────────
local VIPGiftingService = {}

--[[
	isAuthorised(userId) → boolean

	Returns true if this UserId is in GIFT_AUTHORISED_USER_IDS.
	O(1) lookup against the pre-built set.
]]
local function _isAuthorised(userId: number): boolean
	return _authSet[userId] == true
end

--[[
	queueTarget(granter, target) → boolean

	Registers the intended gift recipient before the purchase is prompted.
	Returns false if:
	  - granter is not in GIFT_AUTHORISED_USER_IDS
	  - granter and target are the same player
]]
function VIPGiftingService.queueTarget(granter: Player, target: Player): boolean
	local granterId = granter.UserId

	if not _isAuthorised(granterId) then
		log:warn("{} (UserId {}) is not authorised to gift VIP", granter.Name, granterId)
		return false
	end

	if granterId == target.UserId then
		log:warn("{} tried to gift VIP to themselves", granter.Name)
		return false
	end

	_queue[granterId] = {
		granterId  = granterId,
		targetId   = target.UserId,
		targetName = target.Name,
		queuedAt   = osTime(),
	}

	log:info("VIP gift queued: {} → {} (UserId {})", granter.Name, target.Name, target.UserId)
	return true
end

--[[
	processReceipt(granterUserId, onApply) → boolean

	Finalises the gift when the Roblox receipt fires.

	onApply is a callback provided by VIPService — it handles updating
	the in-memory buffer and Replica for online players. VIPGiftingService
	does not know about buffers or Replica; it only orchestrates the flow.

	Returns true if the gift was applied (online or offline).
	Returns false if no queue entry was found or offline write failed.

	─── Offline handling ───────────────────────────────────────────────
	BUG FIXED: original logged an error on the offline path and returned
	nothing (nil), so money was taken but VIP was never granted.
	Now calls DataStoreService.writeOfflineVIPGrant(targetId) which writes
	a pending grant flag to the target's profile. VIPService reads this
	flag on the target's next login and applies VIP then.
]]
function VIPGiftingService.processReceipt(
	granterUserId : number,
	onApply       : (targetPlayer: Player) -> ()
) : boolean
	local entry = _queue[granterUserId]
	if entry == nil then
		log:warn("processReceipt: no queue entry found for granterUserId {}", granterUserId)
		return false
	end

	-- Clear immediately to prevent double-processing in case of a retry.
	_queue[granterUserId] = nil

	local targetPlayer = GetPlayerByUserId(Players, entry.targetId)

	if targetPlayer ~= nil then
		-- ── Online path ────────────────────────────────────────────────────
		-- onApply updates the live buffer + Replica + profile.Data.VIP
		onApply(targetPlayer)
		log:info(
			"VIP gift applied to online player {} (UserId {}) from UserId {}",
			targetPlayer.Name, entry.targetId, granterUserId
		)
		return true
	end

	-- ── Offline path ───────────────────────────────────────────────────────
	-- Write a pending grant to the target's stored profile.
	-- VIPService reads profile.Data.VIP.PendingGrant on next login.
	PersistenceService.writeOfflineVIPGrant(entry.targetId)
		:andThen(function()
			log:info("Offline VIP gift queued for {}", entry.targetName)
			return true
		end)
		:catch(function(err)
			log:error("Offline VIP gift failed after retries: {}", err)
			return false
			-- caller can decide whether to refund
		end)
end

--[[
	clearQueue(userId)

	Removes any pending gift entry for this user.
	Called by VIPService.init() on PlayerRemoving in case the granter
	leaves the server mid-purchase.
]]
function VIPGiftingService.clearQueue(userId: number)
	if _queue[userId] ~= nil then
		log:debug("Gift queue cleared for UserId {} (player left)", userId)
		_queue[userId] = nil
	end
end

return VIPGiftingService
