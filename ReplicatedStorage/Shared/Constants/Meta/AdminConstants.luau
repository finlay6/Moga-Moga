--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ReplicatedStorage/Shared/Constants/Meta/AdminConstants.luau

--[[
	AdminConstants

	Single source of truth for:
	  - Rank levels and their display / nametag configuration
	  - The hardcoded staff list (userId → rank)

	─── Adding a rank ──────────────────────────────────────────────────
	1. Add an entry to RANKS keyed by a unique RankLevel number.
	2. Assign that level to a user in STAFF_LIST.

	─── Adding a staff member ──────────────────────────────────────────
	1. Add an AdminEntry to STAFF_LIST.
	2. Their rank must exist in RANKS.

	─── Badge image IDs ────────────────────────────────────────────────
	Replace the placeholder strings with real rbxassetid:// values.
	Empty string = no badge shown for that rank.
]]

local AdminTypes = require(ReplicatedStorage.Shared.Types.AdminTypes)

type RankInfo   = AdminTypes.RankInfo
type AdminEntry = AdminTypes.AdminEntry

local AdminConstants = {
	RANK = {} :: {[string]: number},
	RANKS = {} :: {[number]: RankInfo},
	STAFF_LIST = {} :: { AdminEntry }
}

-- ─── Rank Levels ──────────────────────────────────────────────────────────────
-- These numbers are the source of truth. Do not reorder them —
-- AdminService uses > comparisons for permission checks.

AdminConstants.RANK = {
	NONE      = 0,
	VIP       = 1,    -- mirrored from VIPService for nametag purposes
	MODERATOR = 10,
	ADMIN     = 50,
	DEVELOPER = 90,
	OWNER     = 100,
}

-- ─── Rank Definitions ─────────────────────────────────────────────────────────

AdminConstants.RANKS = {
	[0] = {
		level        = 0,
		label        = "",
		badgeImageId = "",
		badgeColor   = Color3.fromRGB(255, 255, 255),
		nameColor    = Color3.fromRGB(255, 255, 255),
		canEditName  = false,
	},
	[1] = {
		level        = 1,
		label        = "VIP",
		badgeImageId = "rbxassetid://0",   -- replace with VIP star asset
		badgeColor   = Color3.fromRGB(255, 215, 0),
		nameColor    = Color3.fromRGB(255, 215, 0),
		canEditName  = true,
	},
	[10] = {
		level        = 10,
		label        = "Moderator",
		badgeImageId = "rbxassetid://0",   -- replace with shield asset
		badgeColor   = Color3.fromRGB(100, 200, 255),
		nameColor    = Color3.fromRGB(100, 200, 255),
		canEditName  = true,
	},
	[50] = {
		level        = 50,
		label        = "Admin",
		badgeImageId = "rbxassetid://0",   -- replace with star asset
		badgeColor   = Color3.fromRGB(255, 100, 100),
		nameColor    = Color3.fromRGB(255, 100, 100),
		canEditName  = true,
	},
	[90] = {
		level        = 90,
		label        = "Developer",
		badgeImageId = "rbxthumb://type=Asset&id=9197710521%s&w=420&h=420",   -- replace with wrench asset
		badgeColor   = Color3.fromRGB(180, 100, 255),
		nameColor    = Color3.fromRGB(180, 100, 255),
		canEditName  = true,
	},
	[100] = {
		level        = 100,
		label        = "Owner",
		badgeImageId = "rbxthumb://type=Asset&id=11835491319%s&w=420&h=420",   -- replace with crown asset
		badgeColor   = Color3.fromRGB(255, 165, 0),
		nameColor    = Color3.fromRGB(255, 165, 0),
		canEditName  = true,
	},
}

-- ─── Staff List ───────────────────────────────────────────────────────────────
-- Add every staff member here. UserId is the only authoritative identifier.

AdminConstants.STAFF_LIST = {
	{ userId = 123867333,  name = "Owner", rank = AdminConstants.RANK.OWNER},
	{ userId = 1064864125, name = "SilentFish20", rank = AdminConstants.RANK.OWNER },
}

-- ─── Permission Thresholds ────────────────────────────────────────────────────
-- Minimum rank level required for each capability.
-- AdminService.can(player, capability) reads these.

AdminConstants.PERMISSIONS = {
	KICK_PLAYERS      = AdminConstants.RANK.MODERATOR,
	BAN_PLAYERS       = AdminConstants.RANK.ADMIN,
	GRANT_CASH        = AdminConstants.RANK.ADMIN,
	GRANT_VIP         = AdminConstants.RANK.ADMIN,
	TELEPORT_PLAYERS  = AdminConstants.RANK.MODERATOR,
	VIEW_PLAYER_DATA  = AdminConstants.RANK.MODERATOR,
	SHUTDOWN_SERVER   = AdminConstants.RANK.DEVELOPER,
}

return table.freeze(AdminConstants)
