--!strict
-- ReplicatedStorage/Shared/Constants/Player/VIPConstants.luau

--[[
	VIPConstants

	Single source of truth for all VIP configuration.
	You either have VIP or you don't — no tiers.
]]

local VIPConstants = {}

-- ─── Economy ──────────────────────────────────────────────────────────────────

-- Applied to all cash earnings (wheel, quests, arcade, icons).
VIPConstants.EARN_MULTIPLIER  = 1.5   -- 1.5× all cash earnings

-- Applied to Robux-priced shop items only.
VIPConstants.SHOP_DISCOUNT    = 0.20  -- 20% off

-- ─── Wheel Spin ───────────────────────────────────────────────────────────────
-- Weights are relative — they do not need to sum to 100.
-- Consumed by VIPRoller. Will move to WheelConstants when WheelService is built.

VIPConstants.WHEEL_MULTIPLIERS = table.freeze({
	{ multiplier = 2,  weight = 90 },
	{ multiplier = 3,  weight = 5  },
	{ multiplier = 5,  weight = 4  },
	{ multiplier = 10, weight = 1  },
})

-- ─── Gifting ──────────────────────────────────────────────────────────────────
-- UserIds allowed to gift VIP to other players (typically the game owner).

VIPConstants.GIFT_AUTHORISED_USER_IDS = table.freeze({
	123867333,
	1064864125,
})

-- ─── UI Reference ─────────────────────────────────────────────────────────────
-- Not used programmatically. Read by the VIP purchase screen to render perks.

VIPConstants.PERKS = table.freeze({
	"1.5× earn multiplier on all cash",
	"Wheel spin multiplier",
	"20% off all Robux shop items",
	"Access to VIP huts in the Floating Gardens",
	"Rent your own boat",
	"Exclusive balloon, kite, and nametag cosmetics",
	"Edit your in-game display name",
})

return table.freeze(VIPConstants)
