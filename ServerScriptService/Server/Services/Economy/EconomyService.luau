--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local EconomyConstants = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes = require(Shared.Types.EconomyTypes)

local Server = ServerScriptService.Server
local Core = Server.Services.Core
local Economy = Server.Services.Economy
local Utils = Shared.Util

-- ─── Sub-Modules ─────────────────────────────────────────────────────────────
local Multiplier = require(Economy.EconomyMultiplierService)
local Transaction = require(Economy.EconomyTransactionService)
local Validator = require(Economy.EconomyValidator)
local RateLimiter = require(Utils.RateLimiter)
local SessionService = require(Core.DataStore.DataStoreService)
local Signal = require(Shared.Packages.Signal)
local Logger = require(Shared.Util.Logger)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime = os.time
local format = string.format
local log = Logger.new("EconomyService")

-- ─── Module ──────────────────────────────────────────────────────────────────
local EconomyService = {}

EconomyService.CashEarned = Signal()
EconomyService.GemsEarned = Signal()

-- Transaction counter for unique IDs
local _txCounter = 0

-- ─── Private Helpers ─────────────────────────────────────────────────────────

local function generateTxId(player: Player): string
	_txCounter += 1
	return format("%d_%d_%d", player.UserId, osTime(), _txCounter)
end

-- ─── Core Orchestration ──────────────────────────────────────────────────────

local function apply(player: Player, cType: EconomyTypes.CurrencyType, rawAmount: number, source: string, metadata: any?): EconomyTypes.TransactionResult
	local data = DataService.getData(player)
	if not data then return { ok = false, balance = 0, amountActual = 0, reason = "no_data" } end

	local economy = data.Economy
	local currentBalance = economy[cType]

	-- 1. Validate (Cap & Affordability)
	local ok, reason = Validator.CanProcess(currentBalance, rawAmount, cType)
	if not ok then
		return { ok = false, balance = currentBalance, amountActual = 0, reason = reason }
	end

	-- 2. Calculate Final Amount
	local newBalance = math.clamp(currentBalance + rawAmount, 0, (cType == "Cash" and EconomyConstants.MAX_CASH or EconomyConstants.MAX_GEMS))
	local actualDelta = newBalance - currentBalance

	-- 3. Mutate State
	economy[cType] = newBalance
	if actualDelta > 0 then
		economy.TotalEarned += actualDelta
	elseif actualDelta < 0 then
		economy.TotalSpent += math.abs(actualDelta)
	end

	-- 4. Audit Trail (Uses pooled memory)
	local txData: EconomyTypes.Transaction = {
		id = generateTxId(player),
		currencyType = cType,
		amount = actualDelta,
		balanceBefore = currentBalance,
		balanceAfter = newBalance,
		source = source,
		timestamp = osTime(),
		metadata = metadata,
	}
	Transaction.Record(player, txData)

	return {
		ok = true,
		balance = newBalance,
		amountActual = actualDelta,
		transaction = txData
	}
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function EconomyService.EarnCash(player: Player, amount: number, context: EconomyTypes.EarnContext)
	-- Rate Limit Check
	if not RateLimiter.Check(player, "EarnCash", EconomyConstants.EARN_RATE_LIMIT_WINDOW, EconomyConstants.EARN_RATE_LIMIT_MAX) then
		return { ok = false, balance = 0, amountActual = 0, reason = "rate_limited" }
	end

	-- Multiplier Logic
	local finalAmount = Multiplier.CalculateEarn(amount, player, context)

	local result = apply(player, "Cash", finalAmount, context.source, context.metadata)
	if result.ok then
		EconomyService.CashEarned:Fire(player, result.amountActual, context.source)
	end

	return result
end

function EconomyService.SpendCash(player: Player, amount: number, context: EconomyTypes.SpendContext)
	-- Spending is face-value (negative delta)
	local result = apply(player, "Cash", -amount, context.source, context.metadata)
	return result
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function EconomyService:init()
	Players.PlayerRemoving:Connect(function(player)
		Transaction.Cleanup(player)
		-- RateLimiter handles its own cleanup via PlayerRemoving internally
	end)

	log:info("EconomyService Orchestrator Initialised")
end

return EconomyService