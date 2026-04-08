-- ReplicatedStorage/Shared/Constants/EconomyConstants.lua
--
-- Single source of truth for all economy numbers.
-- Change values here and they propagate everywhere automatically.
-- Nothing in any service or UI hardcodes these values.

local EconomyConstants = {}

-- ─── Currency Caps ────────────────────────────────────────────────────────────

EconomyConstants.MAX_CASH         = 9_999_999   -- Absolute ceiling. No player can exceed this.
EconomyConstants.MAX_GEMS         = 99_999
EconomyConstants.MAX_TRANSACTION_AMOUNT = 100_000  -- Single transaction ceiling (exploit guard)

-- ─── Starting Values ──────────────────────────────────────────────────────────

EconomyConstants.STARTING_CASH    = 100
EconomyConstants.STARTING_GEMS    = 0

-- ─── Rate Limiting ────────────────────────────────────────────────────────────
-- Prevents a compromised client spamming earn calls.
-- These are per-player limits on how many EARN operations can fire per window.

EconomyConstants.EARN_RATE_LIMIT_WINDOW  = 10    -- seconds
EconomyConstants.EARN_RATE_LIMIT_MAX     = 20    -- max earn calls in that window
EconomyConstants.SPEND_RATE_LIMIT_WINDOW = 5
EconomyConstants.SPEND_RATE_LIMIT_MAX    = 10

-- ─── Transaction History ──────────────────────────────────────────────────────
-- Last N transactions stored per player in memory (NOT persisted).
-- Used for debugging, admin inspection, and potential fraud detection.

EconomyConstants.TRANSACTION_HISTORY_LIMIT = 50

-- ─── VIP Multipliers ──────────────────────────────────────────────────────────
-- Applied to earnings only, never to spending costs.
-- Source: VIPConstants.lua — but referenced here for the economy layer.

EconomyConstants.VIP_EARN_MULTIPLIER = 1.5   -- 50% bonus on all cash earnings

-- ─── Active Sale ──────────────────────────────────────────────────────────────
-- Flip IsActive to true and set dates to enable a sale globally.
-- Shop prices are multiplied by (1 - SaleDiscount).
-- Earn multiplier boosts all cash gains.

EconomyConstants.Sale = {
	IsActive       = false,
	SaleDiscount   = 0.10,    -- 10% off all shop purchases when active
	EarnMultiplier = 1.0,     -- 1.0 = no earn bonus during sale (change to e.g. 1.25)
	Label          = "Weekend Sale",
	StartsAt       = 0,       -- Unix timestamp, 0 = ignore
	EndsAt         = 0,
}

-- ─── Robux → Cash Exchange ────────────────────────────────────────────────────
-- Developer products that grant cash. Key = ProductId, Value = cash amount.
-- Receipt handler in DonationService reads this table.

EconomyConstants.RobuxProducts = {
	-- [productId] = cashAmount
	-- e.g. [123456789] = 500,
}

-- ─── Sources (for transaction logging) ───────────────────────────────────────
-- String constants used as the "source" field in transactions.
-- Makes filtering logs and analytics easy.

EconomyConstants.Source = table.freeze({
	QUEST_REWARD     = "quest_reward",
	WHEEL_SPIN       = "wheel_spin",
	ICON_COLLECT     = "icon_collect",
	BOAT_TOUR        = "boat_tour",
	ARCADE           = "arcade",
	SHOP_PURCHASE    = "shop_purchase",
	VIP_PURCHASE     = "vip_purchase",
	ADMIN_GRANT      = "admin_grant",
	ADMIN_DEDUCT     = "admin_deduct",
	ROBUX_EXCHANGE   = "robux_exchange",
	DONATION_TIP     = "donation_tip",
	TOWER_JUMP       = "tower_jump",
	DAILY_BONUS      = "daily_bonus",
	REFUND           = "refund",
})

return table.freeze(EconomyConstants)
