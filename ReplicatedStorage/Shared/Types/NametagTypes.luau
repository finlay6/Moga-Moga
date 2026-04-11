--!strict
-- ReplicatedStorage/Shared/Types/NametagTypes.luau

local NametagTypes = {}

-- ─── NametagData ──────────────────────────────────────────────────────────────
-- The resolved display state for one player's nametag.
-- Built by NametagService and applied to the BillboardGui.

export type NametagData = {
	displayName  : string,   -- custom name if set, otherwise player.Name
	country      : string,   -- country string, e.g. "United States"
	rankLabel    : string,   -- e.g. "Admin", "VIP", "" for regular players
	badgeImageId : string,   -- asset id for badge icon, "" = hide badge frame
	badgeColor   : Color3,
	nameColor    : Color3,
	isStaff      : boolean,  -- drives the star visibility
}

-- ─── NametagProfile ───────────────────────────────────────────────────────────
-- The persisted slice of player data that NametagService reads from the profile.
-- Matches DataTemplate.Customisation fields used by this service.

export type NametagProfile = {
	displayName : string,
	country     : string,
}

return NametagTypes
