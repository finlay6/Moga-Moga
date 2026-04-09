--!strict
-- ReplicatedStorage/Shared/Types/VIPTypes.luau

--[[
	VIPTypes

	Single source of truth for all VIP-related type contracts.
	Used by VIPService, EconomyMultiplierService, and any client replicas.
	No logic lives here.
]]

local VIPTypes = {}

-- ─── Tier Constants ───────────────────────────────────────────────────────────
-- Re-exported as a type so callers can annotate tier parameters without
-- importing VIPConstants at the type level.
export type Tier = number -- 0 = None, 1 = Standard, 2 = Premium
-- ─── VIPStatus ────────────────────────────────────────────────────────────────
-- The canonical per-player VIP snapshot.
-- Lives in the server-side status cache and is written into profile.Data.VIP
-- on every resolve so it survives session end.
export type VIPStatus = {
	isVIP      : boolean,
	expiresAt  : number,   -- Unix timestamp; 0 = permanent (gamepass-based)
	grantedAt  : number,   -- Unix timestamp of first confirmation this session
}

-- ─── MultiplierResult ─────────────────────────────────────────────────────────
-- Returned by rollWheelMultiplier / rollIconMultiplier.
-- weight is the raw probability weight of this outcome — used for logging only.
export type MultiplierResult = {
	multiplier : number,
	weight     : number,
}

-- ─── WeightEntry ──────────────────────────────────────────────────────────────
-- One entry in a raw multiplier config table (VIPConstants.WHEEL_MULTIPLIERS etc.)
export type WeightEntry = {
	multiplier : number,
	weight     : number,
}

-- ─── BakedTable ───────────────────────────────────────────────────────────────
-- Pre-processed form of a WeightEntry array.
-- Built once at startup by VIPRoller.bake; never rebuilt per roll.
export type BakedTable = {
	entries     : { { m: number, c: number } }, -- m = multiplier, c = cumulative weight
	totalWeight : number,
}

-- ─── GiftQueueEntry ───────────────────────────────────────────────────────────
-- Held server-side between queueGiftTarget and processGiftReceipt.
-- Keyed by granter UserId.
export type GiftQueueEntry = {
	granterId  : number,
	targetId   : number,
	targetName : string,
	queuedAt   : number, -- os.time() when the queue entry was created
}

return VIPTypes
