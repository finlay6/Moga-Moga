--!strict
-- ServerScriptService/Server/Services/Player/VIP/VIPService/init.luau

--[[
	VIPService

	Central authority for all VIP state.

	Responsibilities:
	  - Caching per-player VIPStatus after ProductService resolves ownership
	  - Writing VIP state to the profile via StateService (private helpers only)
	  - Applying pending offline gifts on login
	  - Exposing isVIP / getStatus / getEarnMultiplier / getShopDiscount
	  - Firing VIPStatusChanged so NametagService / UI can react
	  - Delegating gifting flow to VIPGiftingService

	Does NOT:
	  - Check gamepass ownership (ProductService owns that)
	  - Roll wheel multipliers (will move to WheelService)
	  - Apply multipliers to transactions (EconomyMultiplierService owns that)
	  - Call SessionService directly (StateService is the only gateway)

	─── Join flow ──────────────────────────────────────────────────────
	  SessionService.PlayerReady fires
	    → VIPService checks for a pending offline gift
	    → if none, status defaults to not-VIP and waits for ProductService

	  ProductService.GamepassOwned fires (after parallel ownership checks)
	    → VIPService updates cache and profile for that player

	  Result: no race condition. Profile is always loaded when VIPService
	  reads or writes it.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared  = ReplicatedStorage.Shared
local Server  = ServerScriptService.Server

local VIPConstants       = require(Shared.Constants.Player.VIPConstants)
local VIPTypes           = require(Shared.Types.VIPTypes)
local Logger             = require(Shared.Util.Logger)
local Signal             = require(Shared.Packages.Signal)
local StateService       = require(Server.Services.Core.DataStore.StateService)
local SessionService     = require(Server.Services.Core.DataStore.SessionService)
local ProductService     = require(Server.Services.Player.ProductService)
local VIPUtility         = require(script.VIPUtility)
local VIPGiftingService  = require(Server.Services.Player.VIP.VIPGiftingService)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local taskSpawn = task.spawn

-- ─── Private path constants ───────────────────────────────────────────────────
-- Only VIPService reads or writes these paths. Nothing else touches VIP fields.
local PATH_IS_VIP        = {"VIP", "IsVIP"}
local PATH_EXPIRES_AT    = {"VIP", "ExpiresAt"}
local PATH_PENDING_GRANT = {"VIP", "PendingGrant"}

-- ─── Types ───────────────────────────────────────────────────────────────────
type VIPStatus  = VIPTypes.VIPStatus

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("VIPService")

-- Per-player cache. Populated after PlayerReady + ownership resolution.
-- All reads go through the public API, never this table directly.
local _statusCache: { [Player]: VIPStatus } = {}

-- ─── Module ──────────────────────────────────────────────────────────────────
local VIPService = {}

-- ─── Private helpers ─────────────────────────────────────────────────────────

-- Writes VIP status into the profile via StateService so it survives restarts.
local function _persist(player: Player, status: VIPStatus)
	StateService.Set(player, PATH_IS_VIP,     status.isVIP)
	StateService.Set(player, PATH_EXPIRES_AT, status.expiresAt)
end

-- Applies a resolved status: updates cache, persists, fires signal.
local function _applyStatus(player: Player, status: VIPStatus)
	_statusCache[player] = status
	_persist(player, status)
	VIPService.VIPStatusChanged:Fire(player, status)
end

--[[
	VIPStatusChanged : Signal<Player, VIPStatus>

	Fires whenever a player's VIP status is resolved or updated.
	Consumers: NametagService, any UI that shows VIP state.
]]
VIPService.VIPStatusChanged = Signal() :: Signal.Signal<Player, VIPStatus>

-- ─── Public API ──────────────────────────────────────────────────────────────

--- Returns true if the player currently has VIP.
function VIPService.isVIP(player: Player): boolean
	local status = _statusCache[player]
	return status ~= nil and status.isVIP
end

--- Returns the full VIPStatus, or nil if not yet resolved.
function VIPService.getStatus(player: Player): VIPStatus?
	return _statusCache[player]
end

--- Earn multiplier to apply to all cash earnings for this player.
function VIPService.getEarnMultiplier(player: Player): number
	return if VIPService.isVIP(player) then VIPConstants.EARN_MULTIPLIER else 1
end

--- Shop discount fraction (e.g. 0.2 = 20% off). Returns 0 if not VIP.
function VIPService.getShopDiscount(player: Player): number
	return if VIPService.isVIP(player) then VIPConstants.SHOP_DISCOUNT else 0
end

-- ─── Public API: Bulk queries ────────────────────────────────────────────────

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

--- Returns a count of VIP players currently online.
function VIPService.getVIPCount(): number
	local count = 0
	for _, status in _statusCache do
		if status.isVIP then count += 1 end
	end
	return count
end

-- ─── Public API: Gifting ─────────────────────────────────────────────────────

--- Queues a gift target before the purchase prompt. Returns false if unauthorised.
function VIPService.queueGiftTarget(granter: Player, target: Player): boolean
	return VIPGiftingService.queueTarget(granter, target)
end

--[[
	processGiftReceipt(granterUserId) → boolean

	Called by ProductService's ProcessReceipt when the VIP gift product is purchased.
	Delegates to VIPGiftingService — provides the onApply callback.
]]
function VIPService.processGiftReceipt(granterUserId: number): boolean
	return VIPGiftingService.processReceipt(granterUserId, function(targetPlayer: Player)
		local status = VIPUtility.buildStatus(true)
		_applyStatus(targetPlayer, status)
	end)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function VIPService.init()
	-- When ProductService confirms a player owns the VIP gamepass (on join or purchase),
	-- update the cache and profile.
	ProductService.GamepassOwned:Connect(function(player, payload)
		if payload.key ~= "VIP" then return end

		local status = VIPUtility.buildStatus(true)
		_applyStatus(player, status)
		log:info("{} VIP confirmed ({})", player.Name, payload.entry.name)
	end)

	-- Cleanup on leave.
	Players.PlayerRemoving:Connect(function(player: Player)
		_statusCache[player] = nil
		VIPGiftingService.clearQueue(player.UserId)
	end)

	log:info("VIPService initialised")
end

function VIPService.start()
	-- On PlayerReady: check for a pending offline gift.
	-- Default status is not-VIP — ProductService.GamepassOwned will fire
	-- separately if the player owns the pass, upgrading them at that point.
	SessionService.PlayerReady:Connect(function(player: Player)
		taskSpawn(function()
			local pendingGrant = StateService.Get(player, PATH_PENDING_GRANT)

			if pendingGrant == true then
				StateService.Set(player, PATH_PENDING_GRANT, false)
				local status = VIPUtility.buildStatus(true)
				_applyStatus(player, status)
				log:info("{} received a pending offline VIP gift", player.Name)
				return
			end

			-- No pending gift. Set not-VIP as the default.
			-- GamepassOwned will fire and upgrade them if they own the pass.
			local status = VIPUtility.buildStatus(false)
			_applyStatus(player, status)
		end)
	end)

	log:info("VIPService started")
end

return VIPService
