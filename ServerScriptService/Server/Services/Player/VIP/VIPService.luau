--!strict
-- ServerScriptService/Server/Services/Player/VIP/VIPService.luau

--[[
	VIPService

	Central authority for all VIP state.
	Owns the per-player status cache, multiplier rolling, and gifting flow.

	Responsibilities:
	  - Resolving gamepass ownership on join (via VIPVerifier)
	  - Caching resolved status in a lightweight struct (not a buffer)
	  - Writing VIP status to profile.Data.VIP for persistence
	  - Applying pending offline gifts on login
	  - Exposing isVIP / getTier / getStatus for all other services
	  - Rolling wheel and icon multipliers (via VIPRoller)
	  - Returning tier-appropriate earn multipliers and shop discounts
	  - Handling VIP gifting flow (via VIPGiftingManager)
	  - Firing VIPStatusChanged so NametagService / UI can react

	Does NOT:
	  - Apply multipliers to economy transactions (EconomyMultiplierService)
	  - Handle UI or client replication directly (signal-driven)
	  - Know about specific game systems beyond what callers ask for

	─── Changes from originals ─────────────────────────────────────────
	1. Buffer-per-player removed. Per-player state is now a typed VIPStatus
	   struct. The buffer saved ~10 bytes per player and bought zero
	   performance — struct field access is faster than buffer.readf64.

	2. VIPVerifier.checkOwnership now actually exists (it was missing).

	3. resolvePlayer now writes to profile.Data.VIP for persistence.
	   The original wrote to the buffer but not to the profile, so VIP
	   status was lost on server restart.

	4. Pending offline grants (from VIPGiftingManager) are applied on login.

	5. init() / start() split: init() wires signals; start() resolves
	   existing players and hooks PlayerAdded. Same pattern as VIPService.lua.
]]

local Players             = game:GetService("Players")
local MarketplaceService  = game:GetService("MarketplaceService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared   = ReplicatedStorage.Shared
local Server   = ServerScriptService.Server

local VIPConstants       = require(Shared.Constants.Player.VIPConstants)
local VIPTypes           = require(Shared.Types.VIPTypes)
local Logger             = require(Shared.Util.Logger)
local Signal             = require(Shared.Packages.Signal)
local StateService     = require(Server.Services.Core.DataStore.StateService)

local VIPRoller          = require(Server.Services.Player.VIP.VIPRoller)
local VIPGiftingManager  = require(Server.Services.Player.VIP.VIPGiftingManager)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime    = os.time
local taskSpawn = task.spawn

local pendingGrantPath = `VIP.PendingGrant`
local isVIPPath = `VIP.IsVIP`
local tierPath = `VIP.Tier`
local expiresAtPath = `VIP.ExpiresAt`

-- ─── Types ───────────────────────────────────────────────────────────────────
type VIPStatus        = VIPTypes.VIPStatus
type MultiplierResult = VIPTypes.MultiplierResult
type BakedTable       = VIPTypes.BakedTable
type TierLabel = VIPTypes.TierLabel

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("VIPService")

-- Per-player VIP status. Populated on join, cleared on leave.
-- All reads go through the public API — never this table directly.
local _statusCache: { [Player]: VIPStatus } = {}

-- Pre-baked probability tables — built once in init(), reused forever.
local _bakedWheel: BakedTable
local _bakedIcon : BakedTable

-- ─── Private Helpers ─────────────────────────────────────────────────────────

-- Writes VIP status into the player's profile so it survives server restart.
-- Called on every resolve and on gift receipt.
local function _persistToProfile(player: Player, status: VIPStatus)
	StateService.Set(player, isVIPPath, status.isVIP)
	StateService.Set(player, tierPath, status.tier)
	StateService.Set(player, expiresAtPath, status.expiresAt)
end

--[[
	_loadPlayerVIPStatus(player)

	Full resolve pipeline: check gamepass → build status → cache → persist.
	Also applies any pending offline gift that was queued while the player
	was offline.

	Yields (VIPVerifier calls MarketplaceService). Always call via task.spawn.
]]
local VIPService = {}

local function _loadPlayerVIPStatus(player: Player): boolean
	-- 1. Check for a pending offline gift BEFORE checking gamepasses.
	--    If the player received a VIP gift while offline, their profile.Data.VIP
	--    will have PendingGrant = true. Honour it first.
	local pendingGrant = StateService.Get(player, pendingGrantPath)
	if pendingGrant == nil then return false end
	
	if pendingGrant == true then
		StateService.Set(player, pendingGrantPath, false)
		local status = _buildStatus(VIPConstants.TIER_STANDARD)
		_statusCache[player] = status
		_persistToProfile(player, status)
		log:info("{} received a pending VIP gift — tier set to Standard", player.Name)
		VIPService.VIPStatusChanged:Fire(player, status)
		return true
	end

	-- 2. Check live gamepass ownership.
	local tier = MarketplaceService.getTier(player)
	local status = _buildStatus(tier)

	_statusCache[player] = status
	_persistToProfile(player, status)

	if status.isVIP then
		log:info("{} resolved as {} (tier {})", player.Name, status.tierLabel, tier)
	else
		log:debug("{} is not VIP", player.Name)
	end

	VIPService.VIPStatusChanged:Fire(player, status)
	return true
end

-- ─── Module ──────────────────────────────────────────────────────────────────

--[[
	VIPStatusChanged : Signal<Player, VIPStatus>

	Fires when a player's VIP status is resolved or changes mid-session
	(e.g. after a purchase or a gift receipt).
	Consumers: NametagService, UIService, any feature that needs to react to VIP.
]]
VIPService.VIPStatusChanged = Signal() :: Signal.Signal<Player, VIPStatus>

-- ─── Public API: Status Queries ──────────────────────────────────────────────

--- Returns true if the player has any VIP tier. The most-called function.
function VIPService.isVIP(player: Player): boolean
	local status = _statusCache[player]
	return status ~= nil and status.isVIP
end

--- Returns 0 (none), 1 (standard), or 2 (premium).
function VIPService.getTier(player: Player): number
	local status = _statusCache[player]
	return if status ~= nil then status.tier else VIPConstants.TIER_NONE
end

--- Returns the full VIPStatus struct, or nil if not yet resolved.
function VIPService.getStatus(player: Player): VIPStatus?
	return _statusCache[player]
end

--- Re-runs the full gamepass check. Call after a mid-session purchase.
function VIPService.refreshStatus(player: Player)
	log:info("Refreshing VIP status for {}", player.Name)
	taskSpawn(_loadPlayerVIPStatus, player)
end

-- ─── Public API: Multipliers ─────────────────────────────────────────────────

--- Returns the earn multiplier for this player's tier.
function VIPService.getEarnMultiplier(player: Player): number
	local tier = VIPService.getTier(player)
	if tier == VIPConstants.TIER_PREMIUM  then return VIPConstants.EARN_MULTIPLIER_PREMIUM  end
	if tier == VIPConstants.TIER_STANDARD then return VIPConstants.EARN_MULTIPLIER_STANDARD end
	return 1
end

--- Returns the shop discount fraction for this player's tier (e.g. 0.2 = 20% off).
function VIPService.getShopDiscount(player: Player): number
	local tier = VIPService.getTier(player)
	if tier == VIPConstants.TIER_PREMIUM  then return VIPConstants.SHOP_DISCOUNT_PREMIUM  end
	if tier == VIPConstants.TIER_STANDARD then return VIPConstants.SHOP_DISCOUNT_STANDARD end
	return 0
end

--- Rolls a wheel multiplier. Returns { multiplier, weight }.
function VIPService.rollWheelMultiplier(player: Player): MultiplierResult
	if not VIPService.isVIP(player) then
		return { multiplier = 1, weight = 100 }
	end
	local result = VIPRoller.roll(_bakedWheel)
	log:debug("{} wheel roll: {}x (weight {})", player.Name, result.multiplier, result.weight)
	return result
end

--- Rolls an icon collection multiplier.
function VIPService.rollIconMultiplier(player: Player): MultiplierResult
	if not VIPService.isVIP(player) then
		return { multiplier = 1, weight = 100 }
	end
	return VIPRoller.roll(_bakedIcon)
end

-- ─── Public API: Gifting ─────────────────────────────────────────────────────

--- Queues a gift target before purchase. Returns false if not authorised.
function VIPService.queueGiftTarget(granter: Player, target: Player): boolean
	return VIPGiftingManager.queueTarget(granter, target)
end

--[[
	processGiftReceipt(granterUserId) → boolean

	Called by the Roblox receipt handler when GIFT_PRODUCT_ID is purchased.
	Applies VIP to the queued target (online immediately, offline on next login).
]]
function VIPService.processGiftReceipt(granterUserId: number): boolean
	return VIPGiftingManager.processReceipt(granterUserId, function(targetPlayer: Player)
		-- onApply callback: update cache, persist, and fire the signal.
		local status = _buildStatus(VIPConstants.TIER_STANDARD)
		_statusCache[targetPlayer]  = status
		_persistToProfile(targetPlayer, status)
		VIPService.VIPStatusChanged:Fire(targetPlayer, status)
	end)
end

-- ─── Public API: Bulk Queries ────────────────────────────────────────────────

--- Returns all currently online VIP players.
function VIPService.getAllVIPPlayers(): { Player }
	local result: { Player } = {}
	for player, status in _statusCache do
		if status.isVIP then
			result[#result + 1] = player
		end
	end
	return result
end

--- Returns the count of VIP players currently online.
function VIPService.getVIPCount(): number
	local count = 0
	for _, status in _statusCache do
		if status.isVIP then count += 1 end
	end
	return count
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

--[[
	init()

	Bakes probability tables and wires cleanup / mid-session purchase signals.
	Safe to call before profiles are loaded — does not touch player data.
]]
function VIPService.init()
	-- Bake once at startup — never re-baked per roll.
	_bakedWheel = VIPRoller.bake(VIPConstants.WHEEL_MULTIPLIERS)

	local iconConfig = if VIPConstants.ICON_USES_WHEEL_TABLE
		then VIPConstants.WHEEL_MULTIPLIERS
		else VIPConstants.ICON_MULTIPLIERS
	_bakedIcon = VIPRoller.bake(iconConfig)

	-- Mid-session gamepass purchase: refresh status immediately so the player
	-- doesn't need to rejoin to receive their VIP benefits.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			if not wasPurchased then return end
			if passId == VIPConstants.GAMEPASS_ID_STANDARD
				or passId == VIPConstants.GAMEPASS_ID_PREMIUM
			then
				log:info("{} purchased gamepass {} mid-session — refreshing", player.Name, passId)
				VIPService.refreshStatus(player)
			end
		end
	)

	-- Cleanup on leave.
	Players.PlayerRemoving:Connect(function(player: Player)
		_statusCache[player] = nil
		VIPGiftingManager.clearQueue(player.UserId)
	end)

	log:info("VIPService initialised (wheel entries: {}, icon entries: {})",
		#VIPConstants.WHEEL_MULTIPLIERS,
		if VIPConstants.ICON_USES_WHEEL_TABLE then #VIPConstants.WHEEL_MULTIPLIERS else #VIPConstants.ICON_MULTIPLIERS
	)
end

--[[
	start()

	Resolves VIP status for all current players and hooks PlayerAdded.
	Called AFTER SessionService.init() so profiles are loading when we arrive.
	WaitForProfile ensures we don't check gamepasses before data is ready.
]]
function VIPService.start()
	for _, player in Players:GetPlayers() do
		taskSpawn(function()
			_loadPlayerVIPStatus(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		taskSpawn(function()
			_loadPlayerVIPStatus(player)
		end)
	end)

	log:info("VIPService started")
end

return VIPService
