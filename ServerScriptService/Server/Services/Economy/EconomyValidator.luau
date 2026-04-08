--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EconomyConstants = require(Shared.Constants.Economy.EconomyConstants)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local b_create = buffer.create
local b_writeu32 = buffer.writeu32
local b_readu32 = buffer.readu32
local t_clear = table.clear

-- ─── Constants & Buffer Layout ───────────────────────────────────────────────
-- [0] Max Cash (u32) | [4] Max Gems (u32) | [8] Max Single Tx (u32)
local SETTINGS_BUF = b_create(12)
b_writeu32(SETTINGS_BUF, 0, EconomyConstants.MAX_CASH)
b_writeu32(SETTINGS_BUF, 4, EconomyConstants.MAX_GEMS)
b_writeu32(SETTINGS_BUF, 8, EconomyConstants.MAX_TRANSACTION_AMOUNT)

-- ─── Validation Result Pool ──────────────────────────────────────────────────
-- Instead of returning {ok = false, reason = "foo"}, we reuse this table.
-- WARNING: Callers must use the data immediately or copy it if yielding.
local RESULT_SCRATCH = {
	ok = false,
	reason = ""
}

-- ─── Module ──────────────────────────────────────────────────────────────────
local EconomyValidator = {}

--- Checks if a raw amount is within the "Sanity" limits of the system.
function EconomyValidator.IsAmountSanityCheck(amount: number): (boolean, string?)
	local absolute = math.abs(amount)
	local maxTx = b_readu32(SETTINGS_BUF, 8)

	if absolute <= 0 then
		return false, "amount_zero_or_negative"
	end

	if absolute > maxTx then
		return false, "exceeds_max_transaction"
	end

	return true, nil
end

--- Checks if a player's balance can handle a transaction (Cap check or Afford check).
function EconomyValidator.CanProcess(currentBalance: number, delta: number, currencyType: string): (boolean, string?)
	-- 1. Spending Check
	if delta < 0 then
		if currentBalance + delta < 0 then
			return false, "insufficient_funds"
		end
		return true, nil
	end

	-- 2. Earning / Cap Check
	local cap = if currencyType == "Cash" 
		then b_readu32(SETTINGS_BUF, 0) 
		else b_readu32(SETTINGS_BUF, 4)

	if currentBalance >= cap then
		return false, "at_balance_cap"
	end

	return true, nil
end

--- A high-performance wrapper that returns the pooled result table.
function EconomyValidator.QuickCheck(currentBalance: number, delta: number, currencyType: string): any
	t_clear(RESULT_SCRATCH)

	local ok, reason = EconomyValidator.CanProcess(currentBalance, delta, currencyType)

	RESULT_SCRATCH.ok = ok
	RESULT_SCRATCH.reason = reason or ""

	return RESULT_SCRATCH
end

return EconomyValidator