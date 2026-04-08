--!strict
-- ReplicatedStorage/Shared/Types/EconomyTypes.luau

--[[
	EconomyTypes

	Single source of truth for every type used across the Economy layer.
	No logic lives here — purely structural contracts.
]]

local EconomyTypes = {}

-- ─── Currency ─────────────────────────────────────────────────────────────────

-- The set of valid currency identifiers.
-- Stored as a string union so Luau can type-check callsites.
export type CurrencyType = "Cash" | "Gems"

-- ─── Contexts ─────────────────────────────────────────────────────────────────

-- Passed to EarnCash / EarnGems.
-- Controls which multipliers are applied and what gets written to the audit trail.
export type EarnContext = {
	source      : string,   -- human-readable origin: "balloon", "daily_reward", "admin"
	applyVIP    : boolean?, -- default true — set false to bypass VIP multiplier
	applySale   : boolean?, -- default true — set false to bypass global sale
	applyCustom : number?,  -- optional one-off multiplier (e.g. 2.0 for double-cash event)
	metadata    : { [string]: any }?, -- arbitrary extra data written into the Transaction
}

-- Passed to SpendCash / SpendGems.
export type SpendContext = {
	source   : string,
	metadata : { [string]: any }?,
}

-- ─── Transaction ──────────────────────────────────────────────────────────────

-- One entry in a player's audit trail.
-- Written by EconomyTransactionService, read by admin tools / analytics.
export type Transaction = {
	id            : string,             -- server-unique identifier
	currencyType  : CurrencyType,
	amount        : number,             -- signed delta (positive = earn, negative = spend)
	balanceBefore : number,
	balanceAfter  : number,
	source        : string,
	timestamp     : number,             -- os.time()
	metadata      : { [string]: any }?,
}

-- ─── Results ──────────────────────────────────────────────────────────────────

-- Returned by every public EconomyService write call.
export type TransactionResult = {
	ok          : boolean,
	balance     : number,             -- balance after the transaction (or current balance on failure)
	amountActual: number,             -- real delta applied (may differ from requested if clamped)
	reason      : string?,            -- failure reason key — nil on success
	transaction : Transaction?,       -- populated only on success
}

return EconomyTypes
