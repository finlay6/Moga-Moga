--!strict
-- ServerScriptService/Server/Core/VIPService.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Server = ServerScriptService.Server

local VIPConstants      = require(Shared.Constants.Player.VIPConstants)
local VIPTypes          = require(Shared.Types.VIPTypes)
local VIPRoller         = require(Server.Services.Player.VIP.VIPRoller)
local VIPVerifier       = require(Server.Services.Player.VIP.VIPVerifier)
local VIPGiftingManager = require(Server.Services.Player.VIP.VIPGiftingManager)
local Logger            = require(Shared.Util.Logger)

-- ─── Upvalues & Fast Calls ────────────────────────────────────────────────────

local buffer_create   = buffer.create
local buffer_writeu8  = buffer.writeu8
local buffer_writef64 = buffer.writef64
local buffer_readu8   = buffer.readu8
local buffer_readf64  = buffer.readf64

local log = Logger.new("VIPService")

-- ─── Types ────────────────────────────────────────────────────────────────────

type MultiplierResult = VIPTypes.MultiplierResult
type BakedTable = VIPRoller.BakedBufferTable

-- ─── Private State ────────────────────────────────────────────────────────────

-- Buffer layout per player (10 bytes total):
-- [0]   u8  : isVIP (1 = true, 0 = false)
-- [1]   u8  : Tier (0 = None, 1 = Standard, 2 = Premium)
-- [2-9] f64 : ExpiresAt (Unix timestamp, 0 = permanent)
local _playerBuffers: { [Player]: buffer } = {}

-- Pre-baked probability tables
local _bakedWheelTable: BakedTable
local _bakedIconTable: BakedTable

-- ─── Internal Buffer Codec ────────────────────────────────────────────────────

local function _writeVIPState(player: Player, isVIP: boolean, tier: number, expiresAt: number)
	local b = _playerBuffers[player]
	if not b then
		b = buffer_create(10)
		_playerBuffers[player] = b
	end

	buffer_writeu8(b, 0, isVIP and 1 or 0)
	buffer_writeu8(b, 1, tier)
	buffer_writef64(b, 2, expiresAt)
end

local function _getVIPState(player: Player): (boolean, number, number)
	local b = _playerBuffers[player]
	if not b then return false, 0, 0 end

	return (buffer_readu8(b, 0) == 1), buffer_readu8(b, 1), buffer_readf64(b, 2)
end

-- ─── Module ───────────────────────────────────────────────────────────────────

local VIPService = {}

--[[
    Initialises the service, bakes tables, and registers listeners.
]]
function VIPService.init()
	-- Bake probability tables once into fixed-memory lookup tables
	_bakedWheelTable = VIPRoller.bake(VIPConstants.WHEEL_MULTIPLIERS)

	local iconConfig = if VIPConstants.ICON_USES_WHEEL_TABLE 
		then VIPConstants.WHEEL_MULTIPLIERS 
		else VIPConstants.ICON_MULTIPLIERS

	_bakedIconTable = VIPRoller.bake(iconConfig)

	-- Player cleanup
	Players.PlayerRemoving:Connect(function(player: Player)
		_playerBuffers[player] = nil
		VIPGiftingManager.clearQueue(player.UserId)
	end)

	log:info("VIPService initialized with buffer-backed caching.")
end

--[[
    Resolves a player's VIP state via the Verifier and caches it in a buffer.
]]
function VIPService.resolvePlayer(player: Player, savedExpiry: number?)
	local tier = VIPVerifier.checkOwnership(player)
	local isVIP = tier > VIPConstants.TIER_NONE
	local expiresAt = savedExpiry or 0

	_writeVIPState(player, isVIP, tier, expiresAt)
	log:debug("Resolved VIP state for {}: Tier {}", player.Name, tier)

	-- Note: External data module should read from VIPService:getTier() 
	-- here to handle Replica/ProfileService sync.
end

--[[
    Public API: Check if a player is VIP.
]]
function VIPService.isVIP(player: Player): boolean
	local isVIP, _, _ = _getVIPState(player)
	return isVIP
end

--[[
    Public API: Get a player's current VIP tier.
]]
function VIPService.getTier(player: Player): number
	local _, tier, _ = _getVIPState(player)
	return tier
end

--[[
    Public API: Get the cash earn multiplier based on tier.
]]
function VIPService.getEarnMultiplier(player: Player): number
	local tier = VIPService.getTier(player)
	if tier == VIPConstants.TIER_PREMIUM then
		return VIPConstants.EARN_MULTIPLIER_PREMIUM
	elseif tier == VIPConstants.TIER_STANDARD then
		return VIPConstants.EARN_MULTIPLIER_STANDARD
	end
	return 1
end

--[[
    Public API: Get the shop discount based on tier.
]]
function VIPService.getShopDiscount(player: Player): number
	local tier = VIPService.getTier(player)
	if tier == VIPConstants.TIER_PREMIUM then
		return VIPConstants.SHOP_DISCOUNT_PREMIUM
	elseif tier == VIPConstants.TIER_STANDARD then
		return VIPConstants.SHOP_DISCOUNT_STANDARD
	end
	return 0
end

--[[
    Public API: Rolls the wheel multiplier.
]]
function VIPService.rollWheelMultiplier(): MultiplierResult
	return VIPRoller.roll(_bakedWheelTable)
end

--[[
    Public API: Exposes the queuing system from GiftingManager.
]]
function VIPService.queueGiftTarget(granter: Player, target: Player): boolean
	return VIPGiftingManager.queueTarget(granter, target)
end

--[[
    Public API: Invoked by your receipt processor when a gift is purchased.
]]
function VIPService.processGiftReceipt(granterUserId: number): boolean
	return VIPGiftingManager.processReceipt(granterUserId, function(targetPlayer: Player)
		-- Overwrite the target's buffer cache with the new standard VIP status
		_writeVIPState(targetPlayer, true, VIPConstants.TIER_STANDARD, 0)
	end)
end

return VIPService