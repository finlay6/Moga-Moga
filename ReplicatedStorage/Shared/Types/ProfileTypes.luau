--!strict
-- ReplicatedStorage/Shared/Types/ProfileTypes.luau

--[[
	ProfileTypes

	Types that describe the shape of a player's persisted data (profile.Data)
	and the ProfileStore Profile object.

	These are used by DataStoreService, SessionService, and StateService.
	They are kept here rather than in DataStoreService so that Shared modules
	(e.g. StateService, DataMigrationService) can import them without creating
	a dependency on ServerScriptService.
]]

local ProfileTypes = {}

-- ─── ProfileData ──────────────────────────────────────────────────────────────
-- Must match your DataTemplate exactly.
-- Declared as a structural type — Reconcile() will fill any missing fields.

export type EconomyData = {
	Cash       : number,
	Gems       : number,
	TotalEarned: number,
	TotalSpent : number,
}

export type MetaData = {
	DataVersion    : number,
	CreatedAt      : number,  -- first ever join (Unix)
	LastSeenAt     : number,  -- last disconnect (Unix)
	SessionStartAt : number,  -- current session join (Unix) — distinct from LastSeenAt
	TotalPlayTime  : number,  -- seconds
	JoinCount      : number,
	LastUpdatedAt  : number,  -- last migration timestamp (Unix)
}

export type VIPData = {
	IsVIP       : boolean,
	Tier        : number,    -- 0 = None, 1 = Standard, 2 = Premium
	ExpiresAt   : number,    -- Unix timestamp, 0 = permanent
	PendingGrant: boolean,   -- true when an offline VIP gift is waiting to apply on next login
}

export type ProfileData = {
	Economy : EconomyData,
	Meta    : MetaData,
	VIP     : VIPData,
	-- Add new top-level sections here as your game grows.
	-- DataMigrationService will handle backfilling via Reconcile.
}

-- ─── Profile ──────────────────────────────────────────────────────────────────
-- The ProfileStore Profile object.
-- Typed structurally so we are not coupled to ProfileStore's internal types.

export type Profile = {
	Data            : ProfileData,
	IsActive        : (self: Profile) -> boolean,
	Reconcile       : (self: Profile) -> (),
	EndSession      : (self: Profile) -> (),
	AddUserId       : (self: Profile, userId: number) -> (),
	Save            : (self: Profile) -> (),
	OnSessionEnd    : RBXScriptSignal,
	OnAfterSave     : RBXScriptSignal,
	SessionLoadCount: number,
}

return ProfileTypes
