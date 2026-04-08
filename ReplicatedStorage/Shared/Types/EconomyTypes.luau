-- ReplicatedStorage/Shared/Types/EconomyTypes.lua
--
-- All types used by EconomyService and its callers.
-- Import this in any module that deals with economy data.

local EconomyTypes = {}

-- ─── Currency Types ───────────────────────────────────────────────────────────

export type CurrencyType = "Cash" | "Gems"

-- ─── Transaction ─────────────────────────────────────────────────────────────
-- Immutable record of a single economy operation.
-- Stored in memory per-player for debugging.

export type Transaction = {
	id          : string,        -- unique ID: userId_timestamp_counter
	currencyType: CurrencyType,
	amount      : number,        -- positive = earn, negative = spend
	balanceBefore: number,
	balanceAfter : number,
	source      : string,        -- EconomyConstants.Source value
	metadata    : { [string]: any }?,  -- optional extra context (quest ID, item ID, etc.)
	timestamp   : number,        -- os.time()
}

-- ─── Transaction Result ───────────────────────────────────────────────────────
-- Returned by every earn/spend call. Always check .ok before using .balance.

export type TransactionResult = {
	ok           : boolean,
	balance      : number,       -- new balance after transaction (or current if failed)
	amountActual : number,       -- actual amount applied (may differ if capped)
	reason       : string?,      -- failure reason if ok == false
	transaction  : Transaction?, -- the record if ok == true
}

-- ─── Multiplier Context ───────────────────────────────────────────────────────
-- Passed to earnCash so callers can control which multipliers apply.

export type EarnContext = {
	applyVIP     : boolean?,   -- default true
	applySale    : boolean?,   -- default true
	applyCustom  : number?,    -- additional one-off multiplier (e.g. wheel bonus)
	source       : string,     -- required — one of EconomyConstants.Source
	metadata     : { [string]: any }?,
}

-- ─── Spend Context ────────────────────────────────────────────────────────────

export type SpendContext = {
	source   : string,
	metadata : { [string]: any }?,
}

-- ─── Player Economy Snapshot ─────────────────────────────────────────────────
-- What gets written to Replica and read by the client.

export type EconomySnapshot = {
	Cash        : number,
	Gems        : number,
	TotalEarned : number,
	TotalSpent  : number,
}

return EconomyTypes
