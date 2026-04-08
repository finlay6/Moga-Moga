--!strict
-- ServerScriptService/Server/Services/Economy/EconomyValidator.luau

--[[
	EconomyValidator

	Pure validation logic for economy transactions.
	No state, no side-effects — every function is a predicate.

	Called by EconomyService.apply before any mutation occurs.

	─── Design notes ───────────────────────────────────────────────────
	The original implementation stored MAX_CASH, MAX_GEMS, and MAX_TRANSACTION_AMOUNT
	in a 12-byte buffer and read them back via buffer.readu32. That added
	buffer read overhead, reduced readability, and provided zero benefit —
	these are module-level constants loaded once at startup. Plain locals
	are strictly faster (no buffer API call) and vastly more readable.

	QuickCheck was removed. It returned a shared mutable scratch table, which
	is only safe if the caller consumes the result before any other coroutine
	runs. That assumption is one task.wait() away from being violated. All
	callers now use CanProcess directly and destructure the two return values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared

local EconomyConstants  = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes      = require(Shared.Types.EconomyTypes)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local abs  = math.abs

-- ─── Constants ───────────────────────────────────────────────────────────────
-- Cached once at module load. No per-call overhead, no buffer indirection.
local MAX_CASH              = EconomyConstants.MAX_CASH              :: number
local MAX_GEMS              = EconomyConstants.MAX_GEMS              :: number
local MAX_TRANSACTION_AMOUNT= EconomyConstants.MAX_TRANSACTION_AMOUNT:: number

-- Pre-built cap lookup so CanProcess doesn't branch on the currency string.
local CURRENCY_CAP: { [EconomyTypes.CurrencyType]: number } = {
	Cash = MAX_CASH,
	Gems = MAX_GEMS,
}

-- ─── Module ──────────────────────────────────────────────────────────────────
local EconomyValidator = {}

--[[
	SanityCheck(amount) → (ok: boolean, reason: string?)

	Validates the raw amount BEFORE multipliers are applied.
	Catches zero, negative, and absurdly large values.

	BUG FIXED (original): SanityCheck existed but was never called by
	EconomyService.apply. It is now called as the first step in the pipeline.

	Returns (true, nil) on pass; (false, reason) on failure.
]]
function EconomyValidator.SanityCheck(amount: number): (boolean, string?)
	local magnitude = abs(amount)

	if magnitude <= 0 then
		return false, "amount_zero_or_negative"
	end

	if magnitude > MAX_TRANSACTION_AMOUNT then
		return false, "exceeds_max_transaction"
	end

	return true, nil
end

--[[
	CanProcess(currentBalance, delta, currencyType) → (ok: boolean, reason: string?)

	Validates whether a signed delta can be applied to a given balance.

	  Spending (delta < 0): checks the player can afford it.
	  Earning  (delta > 0): checks the player has not hit their balance cap.

	Returns (true, nil) on pass; (false, reason) on failure.
]]
function EconomyValidator.CanProcess(
	currentBalance : number,
	delta          : number,
	currencyType   : EconomyTypes.CurrencyType
): (boolean, string?)

	if delta < 0 then
		-- Spend check: balance after spending must not go negative.
		if currentBalance + delta < 0 then
			return false, "insufficient_funds"
		end
		return true, nil
	end

	-- Earn check: balance must be below the cap to receive anything.
	local cap = CURRENCY_CAP[currencyType]
	if cap == nil then
		-- Unknown currency type — this is a programming error, not a player error.
		return false, "unknown_currency_type"
	end

	if currentBalance >= cap then
		return false, "at_balance_cap"
	end

	return true, nil
end

return EconomyValidator
