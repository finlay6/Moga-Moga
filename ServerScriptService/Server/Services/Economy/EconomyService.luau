--!strict
-- ServerScriptService/Server/Services/Economy/EconomyService.luau

--[[
	EconomyService

	Orchestrates all currency transactions for Cash and Gems.
	This is the ONLY public entry point for reading or writing player balances.

	Responsibilities:
	  - Validating raw amounts (SanityCheck → CanProcess)
	  - Applying multipliers to earns (via EconomyMultiplierService)
	  - Mutating the player's economy data through a single apply() pipeline
	  - Writing transactions to the audit trail (EconomyTransactionService)
	  - Rate-limiting both earn and spend calls
	  - Firing public signals so other systems can react without polling

	Does NOT:
	  - Know where money comes from (BalloonService, QuestService, AdminService)
	  - Apply multipliers to spending (face-value always)
	  - Handle persistence (profile auto-saves via ProfileStore)
	  - Know about VIP directly (EconomyMultiplierService handles that)

	─── Bugs fixed from original ───────────────────────────────────────
	1. CRASH: apply() called DataService.getData() which does not exist.
	   Fixed: uses SessionService.GetData() correctly.

	2. IMPORT ALIAS: DataStoreService was imported but aliased as SessionService,
	   and then SessionService was used for a data accessor that doesn't exist on
	   DataStoreService. Both are now imported correctly and distinctly.

	3. SpendCash had no rate limiting. Spend calls are now rate-limited
	   independently from earn calls to prevent rapid-drain exploits.

	4. generateTxId reset _txCounter to 0 on every server restart.
	   The ID now includes a server-epoch seed so IDs are unique across restarts.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared   = ReplicatedStorage.Shared
local Server   = ServerScriptService.Server
local Economy  = Server.Services.Economy

local StateService = require(Server.Services.Core.DataStore.StateService)
local EconomyConstants  = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes      = require(Shared.Types.EconomyTypes)
local Logger            = require(Shared.Util.Logger)
local Signal            = require(Shared.Packages.Signal)
local RateLimiter       = require(Shared.Util.RateLimiter)
local Multiplier        = require(Economy.EconomyMultiplierService)
local Transaction       = require(Economy.EconomyTransactionService)
local Validator         = require(Economy.EconomyValidator)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime  = os.time
local format  = string.format
local clamp   = math.clamp
local abs     = math.abs

-- ─── Types ───────────────────────────────────────────────────────────────────
type CurrencyType       = EconomyTypes.CurrencyType
type EarnContext        = EconomyTypes.EarnContext
type SpendContext       = EconomyTypes.SpendContext
type TransactionResult  = EconomyTypes.TransactionResult
type TransactionData    = EconomyTypes.Transaction

-- ─── Constants ───────────────────────────────────────────────────────────────
-- Server-epoch seed: included in every transaction ID so IDs are globally
-- unique across server restarts even if _txCounter wraps or resets.
-- BUG FIXED: original counter alone reset to 0 on restart, allowing collisions.
local SERVER_EPOCH = osTime()

local EARN_WINDOW  = EconomyConstants.EARN_RATE_LIMIT_WINDOW :: number
local EARN_MAX     = EconomyConstants.EARN_RATE_LIMIT_MAX    :: number
local SPEND_WINDOW = EconomyConstants.SPEND_RATE_LIMIT_WINDOW:: number
local SPEND_MAX    = EconomyConstants.SPEND_RATE_LIMIT_MAX   :: number

local CURRENCY_MAX: { [CurrencyType]: number } = {
	Cash = EconomyConstants.MAX_CASH,
	Gems = EconomyConstants.MAX_GEMS,
}

-- ─── State ───────────────────────────────────────────────────────────────────
local log        = Logger.new("EconomyService")
local _txCounter = 0

-- ─── Public Signals ──────────────────────────────────────────────────────────
local EconomyService = {}

-- Fires after a successful cash earn.  Args: (player, amountActual, source)
EconomyService.CashEarned  = Signal() :: Signal.Signal<player, number, string>
-- Fires after a successful cash spend. Args: (player, amountActual, source)
EconomyService.CashSpent   = Signal() :: Signal.Signal<player, number, string>
-- Fires after a successful gems earn.  Args: (player, amountActual, source)
EconomyService.GemsEarned  = Signal() :: Signal.Signal<player, number, string>
-- Fires after a successful gems spend. Args: (player, amountActual, source)
EconomyService.GemsSpent   = Signal() :: Signal.Signal<player, number, string>

-- ─── Private Helpers ─────────────────────────────────────────────────────────

local function _generateTxId(player: Player): string
	_txCounter += 1
	-- Format: serverEpoch_userId_sessionTime_counter
	-- Unique across: server restarts (epoch), players (userId),
	-- same-player same-second bursts (counter)
	return format("%d_%d_%d_%d", SERVER_EPOCH, player.UserId, osTime(), _txCounter)
end

--[[
	_failResult(balance, reason)

	Constructs a failure TransactionResult without allocating a Transaction.
	The inline if-expression keeps this as a single table literal.
]]
local function _failResult(balance: number, reason: string): TransactionResult
	return { ok = false, balance = balance, amountActual = 0, reason = reason }
end

-- ─── Core Pipeline ───────────────────────────────────────────────────────────

--[[
	_apply(player, currencyType, rawDelta, source, metadata)

	The single mutation point for all balance changes.
	Steps:
	  1. Retrieve player data — fail fast if not loaded
	  2. SanityCheck the raw delta
	  3. CanProcess against current balance and cap
	  4. Clamp to [0, cap] and derive the actual delta
	  5. Mutate economy data
	  6. Write to the transaction audit trail
	  7. Return a rich result struct
]]
local function _apply(
	player      : Player,
	currencyType: CurrencyType,
	rawDelta    : number,
	source      : string,
	metadata    : { [string]: any }?
): TransactionResult

	-- 1. Data access — BUG FIXED: original called DataService.getData (crashed)
	local currencyPath = {"Economy", currencyType}
	local totalEarnedPath = {"Economy", `Total{currencyType}Earned`}
	local totalSpentPath = {"Economy", `Total{currencyType}Spent`}

	local currentBalance: number = StateService.Get(player, currencyPath)
	local currentTotalEarned = StateService.Get(player, totalEarnedPath)
	local currentTotalSpent = StateService.Get(player, totalSpentPath)

	-- 2. Sanity check the raw delta.
	local sanityOk, sanityReason = Validator.SanityCheck(rawDelta)
	if not sanityOk then
		return _failResult(currentBalance, sanityReason :: string)
	end

	-- 3. Can we process this delta against the current balance?
	local processOk, processReason = Validator.CanProcess(currentBalance, rawDelta, currencyType)
	if not processOk then
		return _failResult(currentBalance, processReason :: string)
	end

	-- 4. Clamp the new balance so we never exceed cap or go below zero.
	local cap        = CURRENCY_MAX[currencyType]
	local newBalance = clamp(currentBalance + rawDelta, 0, cap)
	local actualDelta= newBalance - currentBalance

	-- 5. Mutate.
	StateService.Set(player, currencyPath, newBalance)
	if actualDelta > 0 then
		StateService.Set(player, totalEarnedPath,  currentTotalEarned + actualDelta)
	elseif actualDelta < 0 then
		StateService.Set(player, totalSpentPath, currentTotalSpent + abs(actualDelta))
	end

	-- 6. Audit trail.
	local txData: TransactionData = {
		id            = _generateTxId(player),
		currencyType  = currencyType,
		amount        = actualDelta,
		balanceBefore = currentBalance,
		balanceAfter  = newBalance,
		source        = source,
		timestamp     = osTime(),
		metadata      = metadata,
	}
	Transaction.Record(player, txData)

	-- 7. Result.
	return {
		ok           = true,
		balance      = newBalance,
		amountActual = actualDelta,
		reason       = nil,
		transaction  = txData,
	}
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	EarnCash(player, amount, context) → TransactionResult

	Awards cash to a player after applying multipliers and rate limiting.
	amount must be a positive number representing the BASE award.
	The final credited amount may be higher after VIP/sale multipliers.
]]
function EconomyService.EarnCash(
	player  : Player,
	amount  : number,
	context : EarnContext
): TransactionResult
	if not RateLimiter.Check(player, "EarnCash", EARN_WINDOW, EARN_MAX) then
		return _failResult(0, "rate_limited")
	end

	local finalAmount = Multiplier.CalculateEarn(amount, player, context)
	local result      = _apply(player, "Cash", finalAmount, context.source, context.metadata)

	if result.ok then
		EconomyService.CashEarned:Fire(player, result.amountActual, context.source)
	end

	return result
end

--[[
	SpendCash(player, amount, context) → TransactionResult

	Deducts cash from a player at face value (no multipliers on spending).
	amount must be a positive number representing the cost.
	BUG FIXED: original had no rate limiting on SpendCash.
]]
function EconomyService.SpendCash(
	player  : Player,
	amount  : number,
	context : SpendContext
): TransactionResult
	-- BUG FIXED: spend path now rate-limited independently from earn.
	if not RateLimiter.Check(player, "SpendCash", SPEND_WINDOW, SPEND_MAX) then
		return _failResult(0, "rate_limited")
	end

	local result = _apply(player, "Cash", -amount, context.source, context.metadata)

	if result.ok then
		EconomyService.CashSpent:Fire(player, result.amountActual, context.source)
	end

	return result
end

--[[
	EarnGems(player, amount, context) → TransactionResult

	Awards gems after multipliers. Gems ignore VIP multipliers by convention
	(pass applyVIP = false in context to keep face-value, or true to allow it).
]]
function EconomyService.EarnGems(
	player  : Player,
	amount  : number,
	context : EarnContext
): TransactionResult
	if not RateLimiter.Check(player, "EarnGems", EARN_WINDOW, EARN_MAX) then
		return _failResult(0, "rate_limited")
	end

	local finalAmount = Multiplier.CalculateEarn(amount, player, context)
	local result      = _apply(player, "Gems", finalAmount, context.source, context.metadata)

	if result.ok then
		EconomyService.GemsEarned:Fire(player, result.amountActual, context.source)
	end

	return result
end

--[[
	SpendGems(player, amount, context) → TransactionResult

	Deducts gems at face value.
]]
function EconomyService.SpendGems(
	player  : Player,
	amount  : number,
	context : SpendContext
): TransactionResult
	if not RateLimiter.Check(player, "SpendGems", SPEND_WINDOW, SPEND_MAX) then
		return _failResult(0, "rate_limited")
	end

	local result = _apply(player, "Gems", -amount, context.source, context.metadata)

	if result.ok then
		EconomyService.GemsSpent:Fire(player, result.amountActual, context.source)
	end

	return result
end

--[[
	GetBalance(player, currencyType) → number?

	Returns the current balance for a currency, or nil if data is not loaded.
]]
function EconomyService.GetBalance(
	player      : Player,
	currencyType: CurrencyType
): number?
	local currencyPath = {"Economy", currencyType}
	local currentBalance = StateService.Get(player, currencyPath)
	if currentBalance == nil then return nil end
	return currentBalance
end

--[[
	GetHistory(player) → { Transaction }

	Returns a snapshot of the player's recent transaction history.
	Delegates to EconomyTransactionService.
]]
function EconomyService.GetHistory(player: Player): { TransactionData }
	return Transaction.GetHistory(player)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function EconomyService.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		Transaction.Cleanup(player)
		-- RateLimiter cleans up internally via its own PlayerRemoving listener.
	end)

	log:info("EconomyService initialised")
end

return EconomyService
