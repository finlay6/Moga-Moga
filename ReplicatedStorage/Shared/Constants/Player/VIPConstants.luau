-- ReplicatedStorage/Shared/Constants/VIPConstants.lua
--!strict

--[[
	VIPConstants

	Single source of truth for all VIP-related configuration.
	Every number, ID, and rule lives here.
	Services and UI read from here — nothing is hardcoded elsewhere.
]]

local VIPConstants = {}

-- ─── Shop Discount ────────────────────────────────────────────────────────────
-- Applied to Robux-priced shop items only.
-- EconomyService.getDisplayPrice reads this via VIPConstants.

VIPConstants.SHOP_DISCOUNT = 0.20   -- 20% off for standard VIP

-- ─── Earn Multiplier ─────────────────────────────────────────────────────────
-- Applied to all cash earnings (wheel, icons, quests, arcade).
-- EconomyService reads EconomyConstants.VIP_EARN_MULTIPLIER which should
-- point at this value, or call VIPService.getEarnMultiplier directly.

VIPConstants.EARN_MULTIPLIER = 1.5   -- 1.5x all cash earnings

-- ─── Wheel Spin Multiplier ────────────────────────────────────────────────────
-- The wheel has its own VIP multiplier table separate from flat earn bonus.
-- WheelService calls VIPService.rollWheelMultiplier(player) which uses this.
-- Weights are relative — they don't need to sum to 100.

VIPConstants.WHEEL_MULTIPLIERS = table.freeze({
	--	{ multiplier, weight }
	{ multiplier = 2,  weight = 90 },   -- 90% chance of 2x
	{ multiplier = 3,  weight = 5  },   -- 5%  chance of 3x
	{ multiplier = 5,  weight = 4  },   -- 4%  chance of 5x
	{ multiplier = 10, weight = 1  },   -- 1%  chance of 10x
})

-- ─── Icon Multiplier ──────────────────────────────────────────────────────────
-- Floating icons use the same multiplier table as the wheel.
-- If you want a different table for icons, define it here.

VIPConstants.ICON_USES_WHEEL_TABLE = true   -- true = same table as wheel
VIPConstants.ICON_MULTIPLIERS = VIPConstants.WHEEL_MULTIPLIERS   -- override if false above

-- ─── Gifting ──────────────────────────────────────────────────────────────────
-- Which UserIds are allowed to gift VIP to other players.
-- Typically just the game owner. Checked by VIPService.giftVIP.

VIPConstants.GIFT_AUTHORISED_USER_IDS = table.freeze({
	123867333,
	1064864125
})

-- ─── Perks Reference ─────────────────────────────────────────────────────────
-- Not used programmatically — this is a reference table for UI to display
-- the list of perks in the VIP purchase screen.

VIPConstants.PERKS = table.freeze({
	"Earn multiplier on all cash earnings",
	"Wheel spin multiplier",
	"20% discount on all Robux shop items",
	"Access to VIP huts in the Floating Gardens",
	"Rent your own boat",
	"Exclusive balloon, kite, and nametag cosmetics",
	"Edit your in-game display name",
})

return table.freeze(VIPConstants)