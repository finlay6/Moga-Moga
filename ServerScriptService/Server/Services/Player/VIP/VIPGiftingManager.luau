--!strict
-- ServerScriptService/Server/Core/Internal/VIPGiftingManager.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Server = ServerScriptService.Server

local VIPConstants = require(Shared.Constants.Player.VIPConstants)
local VIPTypes = require(Shared.Types.VIPTypes)
local DataService = require(Server.Services.Core.DataStore.DataService)
local Logger = require(Shared.Util.Logger)

-- ─── Types ────────────────────────────────────────────────────────────────────

type GiftQueueEntry = VIPTypes.GiftQueueEntry

-- ─── Upvalues ─────────────────────────────────────────────────────────────────

local os_time = os.time
local GetPlayerByUserId = Players.GetPlayerByUserId
local log = Logger.new("VIPGiftingManager")

-- ─── Private State ────────────────────────────────────────────────────────────

-- Map of GranterUserId -> GiftQueueEntry 
local _giftQueue: { [number]: GiftQueueEntry } = {}

-- ─── Module ───────────────────────────────────────────────────────────────────

local VIPGiftingManager = {}

--[[
    Checks if a UserId is authorized to initiate a gift.
    The list of authorized IDs is defined in VIPConstants.
]]
function VIPGiftingManager.isAuthorised(userId: number): boolean
	local authorizedIds = VIPConstants.GIFT_AUTHORISED_USER_IDS
	for i = 1, #authorizedIds do
		if authorizedIds[i] == userId then
			return true
		end
	end
	return false
end

--[[
    Queues a recipient for an impending VIP purchase.
    Returns false if authorization fails or if gifting to self.
]]
function VIPGiftingManager.queueTarget(granter: Player, target: Player): boolean
	local granterId = granter.UserId

	if not VIPGiftingManager.isAuthorised(granterId) then
		log:warn("{} is not authorised to gift VIP", granter.Name)
		return false
	end

	if granterId == target.UserId then
		log:warn("{} tried to gift VIP to themselves", granter.Name)
		return false
	end

	_giftQueue[granterId] = {
		granterId  = granterId,
		targetId   = target.UserId,
		targetName = target.Name,
		queuedAt   = os_time(),
	} :: GiftQueueEntry

	log:info("VIP gift queued: {} -> {}", granter.Name, target.Name)
	return true
end

--[[
    Processes the developer product receipt.
    Handles both online and offline target players.
    A success callback is used to update the online cache in VIPService.
]]
function VIPGiftingManager.processReceipt(
	granterUserId: number, 
	onAppliedCallback: (Player) -> ()
): boolean
	local entry = _giftQueue[granterUserId]
	if not entry then
		log:warn("No gift queue entry found for granter {}", granterUserId)
		return false
	end

	-- Clear queue immediately to prevent double-processing 
	_giftQueue[granterUserId] = nil

	local targetPlayer = GetPlayerByUserId(Players, entry.targetId)

	if targetPlayer then
		-- Handle Online Player 
		onAppliedCallback(targetPlayer)
		log:info("VIP gift applied to online player: {}", targetPlayer.Name)
		return true
	else
		log:error("Failed to apply offline VIP gift for UserId {}", entry.targetId)
	end
end

--[[
    Cleans up the queue for a specific user.
    Called when a granter leaves the game mid-purchase[cite: 63].
]]
function VIPGiftingManager.clearQueue(userId: number)
	_giftQueue[userId] = nil
end

return VIPGiftingManager