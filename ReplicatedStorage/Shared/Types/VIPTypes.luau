-- ReplicatedStorage/Shared/Types/VIPTypes.lua
--!strict

--[[
	VIPTypes

	All types used by VIPService and its callers.
]]

local VIPTypes = {}

-- ─── VIP Status ───────────────────────────────────────────────────────────────
-- The canonical per-player VIP state.
-- Written to Replica on join and whenever status changes.

export type VIPStatus = {
	isVIP       : boolean,
	tier        : number,       -- 0 = none, 1 = standard, 2 = premium
	tierLabel   : string,       -- "None" | "VIP" | "VIP Premium"
	expiresAt   : number,       -- Unix timestamp, 0 = no expiry
	grantedAt   : number,       -- Unix timestamp of when VIP was first confirmed
}

-- ─── Multiplier Result ────────────────────────────────────────────────────────
-- Returned by rollWheelMultiplier and getIconMultiplier.
-- Contains the rolled value and the weight it came from for logging.

export type MultiplierResult = {
	multiplier : number,
	weight     : number,   -- the weight of this outcome in the table
}

-- ─── Gift Queue Entry ─────────────────────────────────────────────────────────
-- When the owner initiates a VIP gift, a target is queued server-side
-- before the purchase product is prompted.

export type GiftQueueEntry = {
	granterId    : number,   -- UserId of the admin/owner initiating the gift
	targetId     : number,   -- UserId of the player receiving VIP
	targetName   : string,
	queuedAt     : number,   -- os.time() when queued
}

return VIPTypes