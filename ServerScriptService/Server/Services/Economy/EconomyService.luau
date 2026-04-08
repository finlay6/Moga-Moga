-- ServerScriptService/Server/Core/EconomyService.lua
--!strict

--[[
    EconomyService

    The single authoritative gateway for all currency operations.
    Nothing outside this module writes Cash or Gems directly.

    Responsibilities:
        - earnCash / spendCash / earnGems / spendGems
        - Transaction validation (caps, minimums, rate limits)
        - VIP and sale multiplier application
        - Per-player transaction history (in memory, not persisted)
        - Signals to other services (quest progress, data save triggers)
        - Replica writes so the client sees changes immediately
        - Balance queries (getBalance, canAfford, getSnapshot)

    Does NOT:
        - Save to DataStore (DataService owns that)
        - Handle Robux purchases (MarketplaceService receipt → calls earnCash)
        - Touch UI directly (Replica handles client sync)
        - Know about specific systems (uses Source strings for context)
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

-- ─── Path helpers ─────────────────────────────────────────────────────────────
-- Adjust these to match your actual folder layout.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Server     = ServerScriptService.Server
local Shared     = ReplicatedStorage.Shared

-- ─── Dependencies ─────────────────────────────────────────────────────────────

local Native           = require(Shared.Util.Native)
local Logger           = require(Shared.Util.Logger)
local ValidatorUtil    = require(Shared.Util.ValidatorUtil)
local TimeUtil         = require(Shared.Util.TimeUtil)
local TableUtil        = require(Shared.Util.TableUtil)
local StringUtil       = require(Shared.Util.StringUtil)

local EconomyConstants = require(Shared.Constants.EconomyConstants)
local EconomyTypes     = require(Shared.Types.EconomyTypes)

local DataService      = require(Server.Core.DataService)

-- Signal+ — adjust path to wherever you placed it
local Signal           = require(Shared.Packages.Signal)

-- Replica — adjust path to wherever you placed it
-- We assume you have a playerReplica per player exposed by DataService.
-- If your Replica setup differs, adjust the _writeToReplica helper below.
local Replica          = require(Shared.Packages.Replica)

-- ─── Types ────────────────────────────────────────────────────────────────────

type Transaction       = EconomyTypes.Transaction
type TransactionResult = EconomyTypes.TransactionResult
type EarnContext       = EconomyTypes.EarnContext
type SpendContext       = EconomyTypes.SpendContext
type EconomySnapshot   = EconomyTypes.EconomySnapshot
type CurrencyType      = EconomyTypes.CurrencyType

-- ─── Cached natives ───────────────────────────────────────────────────────────

local floor   = Native.floor
local max     = Native.max
local min     = Native.min
local osTime  = Native.time
local tinsert = Native.tinsert
local tremove = Native.tremove
local format  = Native.format

-- ─── Module ───────────────────────────────────────────────────────────────────

local EconomyService = {}

-- ─── Public Signals ───────────────────────────────────────────────────────────
--
-- Other services subscribe to these. QuestService listens to CashEarned
-- for quest progress. DataService listens to any mutation to schedule saves.
-- Nothing outside this module fires them.

EconomyService.CashEarned   = Signal.new() -- (player: Player, amount: number, source: string)
EconomyService.CashSpent    = Signal.new() -- (player: Player, amount: number, source: string)
EconomyService.GemsEarned   = Signal.new() -- (player: Player, amount: number, source: string)
EconomyService.GemsSpent    = Signal.new() -- (player: Player, amount: number, source: string)
EconomyService.BalanceChanged = Signal.new() -- (player: Player, snapshot: EconomySnapshot)

-- ─── Private State ────────────────────────────────────────────────────────────

-- Transaction history per player — in memory only, cleared on leave
local _history: { [Player]: { Transaction } }  = {}

-- Rate limiting buckets — { count, windowStart }
local _earnBuckets:  { [Player]: { count: number, windowStart: number } } = {}
local _spendBuckets: { [Player]: { count: number, windowStart: number } } = {}

-- Transaction counter for unique ID generation
local _txCounter = 0

local log = Logger.new("EconomyService")

-- ─── Internal Helpers ─────────────────────────────────────────────────────────

local function _generateTxId(player: Player): string
	_txCounter += 1
	return format("%d_%d_%d", player.UserId, osTime(), _txCounter)
end

local function _clampToInt(value: number): number
	return floor(max(0, value))
end

local function _getSaleMultiplier(): number
	local sale = EconomyConstants.Sale
	if not sale.IsActive then return 1 end
	local now = osTime()
	if sale.StartsAt > 0 and now < sale.StartsAt then return 1 end
	if sale.EndsAt   > 0 and now > sale.EndsAt   then return 1 end
	return sale.EarnMultiplier
end

local function _getVIPMultiplier(player: Player): number
	-- VIPService should expose a simple isVIP(player) check.
	-- We call it defensively — if VIPService isn't loaded yet, default to 1.
	local ok, VIPService = pcall(require, Server.Core.VIPService)
	if ok and VIPService and VIPService.isVIP(player) then
		return EconomyConstants.VIP_EARN_MULTIPLIER
	end
	return 1
end

local function _checkRateLimit(
	player: Player,
	buckets: { [Player]: { count: number, windowStart: number } },
	windowSeconds: number,
	maxCalls: number
): boolean
	local now = osTime()
	local bucket = buckets[player]

	if bucket == nil then
		buckets[player] = { count = 1, windowStart = now }
		return true
	end

	if now - bucket.windowStart >= windowSeconds then
		bucket.count = 1
		bucket.windowStart = now
		return true
	end

	bucket.count += 1

	if bucket.count > maxCalls then
		log:warn(
			"Rate limit exceeded for {} — {} calls in {}s (max {})",
			player.Name, bucket.count, windowSeconds, maxCalls
		)
		return false
	end

	return true
end

local function _recordTransaction(player: Player, tx: Transaction)
	local history = _history[player]
	if history == nil then return end

	tinsert(history, tx)

	-- Trim to limit
	while #history > EconomyConstants.TRANSACTION_HISTORY_LIMIT do
		tremove(history, 1)
	end
end

-- Writes the player's current economy values to their Replica.
-- Adjust the path keys to match your Replica schema.
local function _writeToReplica(player: Player, profile)
	local economy = profile.Economy
	-- Replica path depends on your DataService.getReplica(player) setup.
	-- This is intentionally kept as a stub — wire it to your Replica instance.
	local replica = DataService.getReplica(player)
	if replica then
		replica:SetValue({ "Economy", "Cash" },        economy.Cash)
		replica:SetValue({ "Economy", "Gems" },        economy.Gems)
		replica:SetValue({ "Economy", "TotalEarned" }, economy.TotalEarned)
		replica:SetValue({ "Economy", "TotalSpent" },  economy.TotalSpent)
	end
end

local function _buildSnapshot(economy): EconomySnapshot
	return {
		Cash        = economy.Cash,
		Gems        = economy.Gems,
		TotalEarned = economy.TotalEarned,
		TotalSpent  = economy.TotalSpent,
	}
end

-- ─── Core Transaction Engine ──────────────────────────────────────────────────
--
-- All earn/spend functions flow through here.
-- Returns a TransactionResult — callers MUST check .ok.

local function _applyTransaction(
	player        : Player,
	currencyType  : CurrencyType,
	rawAmount     : number,        -- positive = earn, negative = spend
	source        : string,
	metadata      : { [string]: any }?
): TransactionResult

	-- 1. Load profile
	local profile = DataService.getData(player)
	if profile == nil then
		return {
			ok           = false,
			balance      = 0,
			amountActual = 0,
			reason       = "profile_not_loaded",
		}
	end

	local economy = profile.Economy

	-- 2. Read current balance
	local currentBalance: number = economy[currencyType] or 0
	local cap: number = if currencyType == "Cash"
		then EconomyConstants.MAX_CASH
		else EconomyConstants.MAX_GEMS

	-- 3. Calculate new balance with clamping
	local newBalance: number
	local amountActual: number

	if rawAmount >= 0 then
		-- Earning: cap at maximum
		newBalance    = min(currentBalance + rawAmount, cap)
		amountActual  = newBalance - currentBalance
	else
		-- Spending: floor at 0
		newBalance    = max(currentBalance + rawAmount, 0)
		amountActual  = newBalance - currentBalance  -- will be negative or zero

		-- Reject if they can't afford it
		if currentBalance + rawAmount < 0 then
			return {
				ok           = false,
				balance      = currentBalance,
				amountActual = 0,
				reason       = "insufficient_funds",
			}
		end
	end

	-- 4. Apply the change
	economy[currencyType] = newBalance

	-- 5. Update lifetime totals (always integers)
	if amountActual > 0 then
		economy.TotalEarned = _clampToInt(economy.TotalEarned + amountActual)
	elseif amountActual < 0 then
		economy.TotalSpent = _clampToInt(economy.TotalSpent + (-amountActual))
	end

	-- 6. Build and record transaction
	local tx: Transaction = {
		id            = _generateTxId(player),
		currencyType  = currencyType,
		amount        = amountActual,
		balanceBefore = currentBalance,
		balanceAfter  = newBalance,
		source        = source,
		metadata      = metadata,
		timestamp     = osTime(),
	}

	_recordTransaction(player, tx)

	-- 7. Push to Replica so client sees the change immediately
	_writeToReplica(player, profile)

	-- 8. Fire balance changed signal
	EconomyService.BalanceChanged:Fire(player, _buildSnapshot(economy))

	log:debug(
		"{} {} {} → {} ({})",
		player.Name,
		if amountActual >= 0 then "earned" else "spent",
		math.abs(amountActual),
		currencyType,
		newBalance,
		source
	)

	return {
		ok           = true,
		balance      = newBalance,
		amountActual = amountActual,
		transaction  = tx,
	}
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
    earnCash(player, amount, context)

    Awards cash to a player. Applies VIP and sale multipliers unless opted out.
    The amount parameter is the BASE amount before multipliers.

    Returns TransactionResult — always check .ok.
    .amountActual tells you how much was actually awarded after multipliers and cap.

    Example:
        local result = EconomyService.earnCash(player, 100, {
            source = EconomyConstants.Source.QUEST_REWARD,
            metadata = { questId = 1 },
        })
        if result.ok then
            print("Awarded", result.amountActual, "cash. New balance:", result.balance)
        end
]]
function EconomyService.earnCash(
	player  : Player,
	amount  : number,
	context : EarnContext
): TransactionResult

	-- Validate
	ValidatorUtil.validate(amount, ValidatorUtil.isPositiveInteger, "earnCash.amount")
	ValidatorUtil.validate(context.source, ValidatorUtil.nonEmptyString, "earnCash.source")

	if amount > EconomyConstants.MAX_TRANSACTION_AMOUNT then
		log:warn("earnCash: amount {} exceeds MAX_TRANSACTION_AMOUNT for {}", amount, player.Name)
		amount = EconomyConstants.MAX_TRANSACTION_AMOUNT
	end

	-- Rate limit check
	if not _checkRateLimit(
		player, _earnBuckets,
		EconomyConstants.EARN_RATE_LIMIT_WINDOW,
		EconomyConstants.EARN_RATE_LIMIT_MAX
	) then
		return {
			ok           = false,
			balance      = EconomyService.getCashBalance(player),
			amountActual = 0,
			reason       = "rate_limited",
		}
	end

	-- Build multiplier
	local multiplier = 1.0

	if context.applyVIP ~= false then
		multiplier *= _getVIPMultiplier(player)
	end

	if context.applySale ~= false then
		multiplier *= _getSaleMultiplier()
	end

	if context.applyCustom then
		multiplier *= context.applyCustom
	end

	-- Apply multiplier and floor to integer — currency is always whole numbers
	local finalAmount = _clampToInt(amount * multiplier)

	local result = _applyTransaction(player, "Cash", finalAmount, context.source, context.metadata)

	if result.ok then
		EconomyService.CashEarned:Fire(player, result.amountActual, context.source)
	end

	return result
end

--[[
    spendCash(player, amount, context)

    Deducts cash from a player. Fails cleanly if they can't afford it.
    Does NOT apply multipliers — spending is always face value.

    Always check result.ok — if false, the transaction did not happen.
]]
function EconomyService.spendCash(
	player  : Player,
	amount  : number,
	context : SpendContext
): TransactionResult

	ValidatorUtil.validate(amount, ValidatorUtil.isPositiveInteger, "spendCash.amount")
	ValidatorUtil.validate(context.source, ValidatorUtil.nonEmptyString, "spendCash.source")

	if not _checkRateLimit(
		player, _spendBuckets,
		EconomyConstants.SPEND_RATE_LIMIT_WINDOW,
		EconomyConstants.SPEND_RATE_LIMIT_MAX
	) then
		return {
			ok           = false,
			balance      = EconomyService.getCashBalance(player),
			amountActual = 0,
			reason       = "rate_limited",
		}
	end

	local result = _applyTransaction(player, "Cash", -amount, context.source, context.metadata)

	if result.ok then
		EconomyService.CashSpent:Fire(player, math.abs(result.amountActual), context.source)
	end

	return result
end

--[[
    earnGems / spendGems — same pattern as cash but for premium currency.
    VIP multiplier does NOT apply to gems by default.
]]
function EconomyService.earnGems(
	player  : Player,
	amount  : number,
	context : EarnContext
): TransactionResult

	ValidatorUtil.validate(amount, ValidatorUtil.isPositiveInteger, "earnGems.amount")
	ValidatorUtil.validate(context.source, ValidatorUtil.nonEmptyString, "earnGems.source")

	-- Gems don't get multipliers by default — override with applyCustom if needed
	local result = _applyTransaction(player, "Gems", amount, context.source, context.metadata)

	if result.ok then
		EconomyService.GemsEarned:Fire(player, result.amountActual, context.source)
	end

	return result
end

function EconomyService.spendGems(
	player  : Player,
	amount  : number,
	context : SpendContext
): TransactionResult

	ValidatorUtil.validate(amount, ValidatorUtil.isPositiveInteger, "spendGems.amount")
	ValidatorUtil.validate(context.source, ValidatorUtil.nonEmptyString, "spendGems.source")

	local result = _applyTransaction(player, "Gems", -amount, context.source, context.metadata)

	if result.ok then
		EconomyService.GemsSpent:Fire(player, math.abs(result.amountActual), context.source)
	end

	return result
end

-- ─── Balance Queries ──────────────────────────────────────────────────────────

--[[
    getCashBalance(player) → number

    Returns current cash balance. Returns 0 if profile not loaded.
    Use this for read-only checks — never write through this.
]]
function EconomyService.getCashBalance(player: Player): number
	local profile = DataService.getData(player)
	if profile == nil then return 0 end
	return profile.Economy.Cash or 0
end

function EconomyService.getGemsBalance(player: Player): number
	local profile = DataService.getData(player)
	if profile == nil then return 0 end
	return profile.Economy.Gems or 0
end

--[[
    canAfford(player, amount, currencyType?) → boolean

    Quick check before attempting a purchase.
    currencyType defaults to "Cash".

    Example:
        if not EconomyService.canAfford(player, 500) then
            -- show "not enough coins" UI
            return
        end
        EconomyService.spendCash(player, 500, { source = Source.SHOP_PURCHASE })
]]
function EconomyService.canAfford(
	player       : Player,
	amount       : number,
	currencyType : CurrencyType?
): boolean
	local cType = currencyType or "Cash"
	if cType == "Cash" then
		return EconomyService.getCashBalance(player) >= amount
	else
		return EconomyService.getGemsBalance(player) >= amount
	end
end

--[[
    getSnapshot(player) → EconomySnapshot?

    Returns a full economy snapshot — Cash, Gems, TotalEarned, TotalSpent.
    Returns nil if profile not loaded.
    Used by admin tools and diagnostic panels.
]]
function EconomyService.getSnapshot(player: Player): EconomySnapshot?
	local profile = DataService.getData(player)
	if profile == nil then return nil end
	return _buildSnapshot(profile.Economy)
end

--[[
    getDisplayPrice(basePrice, player?) → number

    Returns the price a player should see and pay, accounting for active sales
    and any VIP discounts. If player is nil, returns the base sale price only.

    Shop UIs call this to display the correct price.
    spendCash is still called with the result of this function as the amount.
]]
function EconomyService.getDisplayPrice(basePrice: number, player: Player?): number
	ValidatorUtil.validate(basePrice, ValidatorUtil.isPositiveInteger, "getDisplayPrice.basePrice")

	local price = basePrice
	local sale  = EconomyConstants.Sale

	-- Apply active sale discount
	if sale.IsActive then
		local now = osTime()
		local saleActive = (sale.StartsAt == 0 or now >= sale.StartsAt)
			and (sale.EndsAt == 0 or now <= sale.EndsAt)

		if saleActive then
			price = _clampToInt(price * (1 - sale.SaleDiscount))
		end
	end

	-- VIP discount (if a player is provided and they are VIP)
	if player then
		local ok, VIPService = pcall(require, Server.Core.VIPService)
		if ok and VIPService and VIPService.isVIP(player) then
			local vipDiscount = require(Shared.Constants.VIPConstants).SHOP_DISCOUNT
			price = _clampToInt(price * (1 - vipDiscount))
		end
	end

	return math.max(1, price) -- Price can never be zero or negative
end

-- ─── Transaction History ──────────────────────────────────────────────────────

--[[
    getHistory(player, limit?) → { Transaction }

    Returns recent transactions for a player. Most recent first.
    Limit defaults to 20. Used by admin tools and debugging.
]]
function EconomyService.getHistory(player: Player, limit: number?): { Transaction }
	local history = _history[player]
	if history == nil then return {} end

	local n = math.min(limit or 20, #history)
	local result: { Transaction } = {}

	-- Return most recent first
	for i = #history, #history - n + 1, -1 do
		tinsert(result, history[i])
	end

	return result
end

--[[
    getSummary(player) → table

    Returns a human-readable summary of recent activity.
    Useful for admin panels and debugging dashboards.
]]
function EconomyService.getSummary(player: Player): { [string]: any }
	local snapshot = EconomyService.getSnapshot(player)
	local history  = EconomyService.getHistory(player, 10)

	return {
		player   = player.Name,
		snapshot = snapshot,
		recent   = history,
	}
end

-- ─── Admin Functions ─────────────────────────────────────────────────────────
--
-- These bypass rate limiting and VIP multipliers.
-- They should only be called by AdminService after rank validation.

--[[
    adminGrant(player, amount, currencyType?, reason?)

    Directly grants currency to a player. Bypasses all rate limits.
    Call only from AdminService after validating the caller is an admin.
]]
function EconomyService.adminGrant(
	player       : Player,
	amount       : number,
	currencyType : CurrencyType?,
	reason       : string?
): TransactionResult

	local cType = currencyType or "Cash"
	local source = EconomyConstants.Source.ADMIN_GRANT

	log:info("Admin grant: {} {} to {} (reason: {})", amount, cType, player.Name, reason or "none")

	local result = _applyTransaction(player, cType, amount, source, { reason = reason })

	if result.ok then
		if cType == "Cash" then
			EconomyService.CashEarned:Fire(player, result.amountActual, source)
		else
			EconomyService.GemsEarned:Fire(player, result.amountActual, source)
		end
	end

	return result
end

--[[
    adminDeduct(player, amount, currencyType?, reason?)

    Directly deducts currency. Bypasses rate limits. Can bring balance to 0.
]]
function EconomyService.adminDeduct(
	player       : Player,
	amount       : number,
	currencyType : CurrencyType?,
	reason       : string?
): TransactionResult

	local cType = currencyType or "Cash"
	local source = EconomyConstants.Source.ADMIN_DEDUCT

	log:info("Admin deduct: {} {} from {} (reason: {})", amount, cType, player.Name, reason or "none")

	return _applyTransaction(player, cType, -amount, source, { reason = reason })
end

--[[
    adminSetBalance(player, amount, currencyType?)

    Hard-sets a player's balance. USE ONLY FOR DEBUGGING.
    Records the delta as an admin grant or deduct.
]]
function EconomyService.adminSetBalance(
	player       : Player,
	targetAmount : number,
	currencyType : CurrencyType?
): TransactionResult

	local cType   = currencyType or "Cash"
	local current = if cType == "Cash"
		then EconomyService.getCashBalance(player)
		else EconomyService.getGemsBalance(player)

	local delta = targetAmount - current

	if delta == 0 then
		return {
			ok           = true,
			balance      = current,
			amountActual = 0,
		}
	elseif delta > 0 then
		return EconomyService.adminGrant(player, delta, cType, "admin_set_balance")
	else
		return EconomyService.adminDeduct(player, -delta, cType, "admin_set_balance")
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function EconomyService:init()
	-- Wire up player tracking — allocate history tables on join, clean up on leave
	Players.PlayerAdded:Connect(function(player: Player)
		_history[player]      = {}
		_earnBuckets[player]  = nil
		_spendBuckets[player] = nil
		log:debug("Economy state initialised for {}", player.Name)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- Log summary before cleaning up — useful for detecting anomalies
		local snapshot = EconomyService.getSnapshot(player)
		if snapshot then
			log:info(
				"Player {} leaving — Cash: {}, Gems: {}, Earned: {}, Spent: {}",
				player.Name,
				snapshot.Cash,
				snapshot.Gems,
				snapshot.TotalEarned,
				snapshot.TotalSpent
			)
		end

		_history[player]      = nil
		_earnBuckets[player]  = nil
		_spendBuckets[player] = nil
	end)

	-- Handle players who joined before this service initialised
	for _, player in Players:GetPlayers() do
		_history[player]      = {}
		_earnBuckets[player]  = nil
		_spendBuckets[player] = nil
	end

	log:info("EconomyService initialised")
end

function EconomyService:start()
	-- Nothing needed here currently.
	-- Future: could start a periodic analytics flush if you add server-side analytics.
	log:info("EconomyService started")
end

return EconomyService
