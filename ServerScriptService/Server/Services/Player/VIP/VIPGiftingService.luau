--!strict
-- ServerScriptService/Server/Services/Player/VIP/VIPGiftingService.luau

--[[
	VIPGiftingService

	Manages the two-step VIP gifting flow.

	─── Flow ───────────────────────────────────────────────────────────
	1. Authorised admin calls queueTarget(granter, target)
	2. Admin purchases the VIP gift developer product via MarketplaceService
	3. ProductService fires ProcessReceipt → calls VIPService.processGiftReceipt
	4. VIPService calls processReceipt(granterUserId, onApply)
	   a. Target online  → onApply(targetPlayer) runs immediately
	   b. Target offline → PersistenceService.writeOfflineVIPGrant queued;
	                       VIPService applies on target's next login

	Does NOT:
	  - Know what VIPStatus looks like (onApply callback owns that)
	  - Touch StateService directly
	  - Handle the Roblox receipt itself (ProductService owns ProcessReceipt)
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared  = ReplicatedStorage.Shared
local Server  = ServerScriptService.Server

local VIPConstants       = require(Shared.Constants.Player.VIPConstants)
local VIPTypes           = require(Shared.Types.VIPTypes)
local PersistenceService = require(Server.Services.Core.DataStore.PersistenceService)
local Logger             = require(Shared.Util.Logger)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime = os.time

-- ─── Types ───────────────────────────────────────────────────────────────────
type GiftQueueEntry = VIPTypes.GiftQueueEntry

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("VIPGiftingService")

-- O(1) authorisation set built once at module load.
local _authSet: { [number]: true } = {}
for _, userId in VIPConstants.GIFT_AUTHORISED_USER_IDS do
	_authSet[userId] = true
end

-- granterUserId → GiftQueueEntry. Cleared immediately on receipt.
local _queue: { [number]: GiftQueueEntry } = {}

-- ─── Private ─────────────────────────────────────────────────────────────────

local function _isAuthorised(userId: number): boolean
	return _authSet[userId] == true
end

-- ─── Module ──────────────────────────────────────────────────────────────────
local VIPGiftingService = {}

--[[
	queueTarget(granter, target) → boolean

	Registers the intended recipient before the purchase prompt.
	Returns false if the granter is not authorised or is gifting themselves.
]]
function VIPGiftingService.queueTarget(granter: Player, target: Player): boolean
	local granterId = granter.UserId

	if not _isAuthorised(granterId) then
		log:warn("{} ({}) is not authorised to gift VIP", granter.Name, granterId)
		return false
	end

	if granterId == target.UserId then
		log:warn("{} attempted to gift VIP to themselves", granter.Name)
		return false
	end

	_queue[granterId] = {
		granterId  = granterId,
		targetId   = target.UserId,
		targetName = target.Name,
		queuedAt   = osTime(),
	}

	log:info("VIP gift queued: {} → {} ({})", granter.Name, target.Name, target.UserId)
	return true
end

--[[
	processReceipt(granterUserId, onApply) → boolean

	Finalises the gift when the receipt fires.

	onApply: callback supplied by VIPService to update cache + profile for
	an online target. VIPGiftingService does not know about VIPStatus.

	Returns true if the gift was applied or successfully queued for offline delivery.
	Returns false if no queue entry exists or the offline write failed after retries.

	The offline path is fire-and-forget via a Promise — the function returns
	true optimistically once the write is queued. If the Promise rejects after
	retries, an error is logged and the receipt handler should consider a refund.
]]
function VIPGiftingService.processReceipt(
	granterUserId : number,
	onApply       : (targetPlayer: Player) -> ()
): boolean
	local entry = _queue[granterUserId]
	if entry == nil then
		log:warn("processReceipt: no queue entry for granterUserId {}", granterUserId)
		return false
	end

	-- Clear immediately — prevents double-processing on receipt retry.
	_queue[granterUserId] = nil

	local targetPlayer = Players:GetPlayerByUserId(entry.targetId)

	if targetPlayer ~= nil then
		-- Online path: apply immediately.
		onApply(targetPlayer)
		log:info(
			"VIP gift applied to online player {} ({}) from {}",
			targetPlayer.Name, entry.targetId, granterUserId
		)
		return true
	end

	-- Offline path: queue for next login via ProfileStore:MessageAsync.
	-- Returns true here — the write is async. Errors are logged by the Promise chain.
	PersistenceService.writeOfflineVIPGrant(entry.targetId)
		:andThen(function()
			log:info(
				"Offline VIP gift queued for {} ({}) — will apply on next login",
				entry.targetName, entry.targetId
			)
		end)
		:catch(function(err)
			log:error(
				"Offline VIP gift FAILED for {} ({}) after retries: {}",
				entry.targetName, entry.targetId, tostring(err)
			)
			-- At this point money has left the granter's account but VIP was not
			-- granted. Surface this for manual review / refund logic.
		end)

	return true
end

--[[
	clearQueue(userId)

	Removes any pending entry for this user.
	Called when the granter leaves mid-purchase so stale entries don't linger.
]]
function VIPGiftingService.clearQueue(userId: number)
	if _queue[userId] ~= nil then
		_queue[userId] = nil
		log:debug("Gift queue cleared for {} (player left)", userId)
	end
end

return VIPGiftingService
