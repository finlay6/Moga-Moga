--!strict
-- ReplicatedStorage/Shared/Types/AdminTypes.luau

local AdminTypes = {}

-- ─── Rank ─────────────────────────────────────────────────────────────────────
-- Numeric rank level. Higher = more permissions.
-- 0  = regular player
-- 1  = VIP (handled by VIPService, mirrored here for nametag logic)
-- 10 = moderator
-- 50 = admin
-- 90 = developer
-- 100 = owner

export type RankLevel = number

export type RankInfo = {
	level       : RankLevel,
	label       : string,   -- display name, e.g. "Admin"
	badgeImageId: string,   -- asset id for the nametag badge icon, "" = none
	badgeColor  : Color3,   -- tint applied to the badge image label
	nameColor   : Color3,   -- color of the player's name text in the nametag
	canEditName : boolean,  -- can this rank edit their display name?
}

-- ─── AdminEntry ───────────────────────────────────────────────────────────────
-- One entry in the hardcoded staff list (AdminConstants).

export type AdminEntry = {
	userId : number,
	name   : string,   -- human-readable, for logging only
	rank   : RankLevel,
}

-- ─── PlayerRankStatus ─────────────────────────────────────────────────────────
-- Resolved per-player rank snapshot. Cached by AdminService.

export type PlayerRankStatus = {
	userId    : number,
	rankLevel : RankLevel,
	rankInfo  : RankInfo,
	resolvedAt: number,   -- os.time()
}

return AdminTypes
