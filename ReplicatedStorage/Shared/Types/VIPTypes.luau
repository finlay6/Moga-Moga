--!strict
-- ReplicatedStorage/Shared/Types/VIPTypes.luau

local VIPTypes = {}

-- ─── VIPStatus ────────────────────────────────────────────────────────────────
-- The canonical per-player VIP snapshot.
-- Cached server-side and written into profile.Data.VIP on every resolve
-- so it survives server restarts.

export type VIPStatus = {
	isVIP     : boolean,
	expiresAt : number,  -- Unix timestamp; 0 = permanent (gamepass-based)
	grantedAt : number,  -- Unix timestamp of when VIP was first confirmed this session
}

-- ─── WeightEntry / BakedTable / MultiplierResult ──────────────────────────────
-- Kept here because VIPRoller is still a VIP subfolder module.
-- When WheelService is built these can move to a shared RollerTypes if needed.

export type WeightEntry = {
	multiplier : number,
	weight     : number,
}

export type BakedEntry = {
	m : number,  -- multiplier
	c : number,  -- cumulative weight
}

export type BakedTable = {
	entries     : { BakedEntry },
	totalWeight : number,
}

export type MultiplierResult = {
	multiplier : number,
	weight     : number,  -- raw (non-cumulative) weight, for logging only
}

-- ─── GiftQueueEntry ───────────────────────────────────────────────────────────
-- Held server-side between queueGiftTarget and processGiftReceipt.
-- Keyed by granter UserId.

export type GiftQueueEntry = {
	granterId  : number,
	targetId   : number,
	targetName : string,
	queuedAt   : number,
}

return VIPTypes
