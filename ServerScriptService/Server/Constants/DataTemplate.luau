-- ReplicatedStorage/Shared/Constants/DataTemplate.lua

--[[
    DataTemplate
    
    The canonical default data structure for a player profile.
    This is what ProfileStore uses as the template for new players.
    
    Rules:
        - Every key that will EVER exist in player data must be here
        - Nested tables are fine but keep nesting shallow (max 2 deep)
        - Never store instance references, player objects, or non-serialisable values
        - All monetary values are integers (never floats — floating point errors in economies are bad)
        - Timestamps are Unix time via os.time()
]]

local DataTemplate = {

	-- ─── Meta ────────────────────────────────────────────────────────────────
	-- Housekeeping data about the profile itself

	Meta = {
		CreatedAt       = 0,       -- Unix timestamp of first join
		LastSeenAt      = 0,       -- Unix timestamp of last session end
		LastUpdatedAt = 0,       -- Unix timestamp of last update
		TotalPlayTime   = 0,       -- Lifetime playtime in seconds
		JoinCount       = 0,       -- Total number of sessions
		DataVersion     = 1,       -- Schema version, increment when migrating
	},

	-- ─── Economy ─────────────────────────────────────────────────────────────
	-- All currency and transaction-related data
	-- Using integers throughout — never store currency as a float

	Economy = {
		Cash            = 0,       -- Primary in-game currency
		Gems            = 0,       -- Premium currency (spin wheel rewards, etc.)
		TotalCashEarned     = 0,       -- Lifetime cash earned (useful for analytics/prestige)
		TotalCashSpent      = 0,       -- Lifetime cash spent
		TotalGemsEarned = 0,
		TotalGemsSpent = 0
	},

	-- ─── VIP ─────────────────────────────────────────────────────────────────

	VIP = {
		IsVIP           = false,
		Tier            = 0,       -- 0 = none, 1 = basic, 2 = premium etc. expandable
		ExpiresAt       = 0,       -- Unix timestamp, 0 = no expiry / not VIP
		PurchasedAt     = 0,
	},

	-- ─── Progression ─────────────────────────────────────────────────────────
	-- General player progression that doesn't belong to a specific system

	Progression = {
		Level           = 1,
		XP              = 0,
		XPToNextLevel   = 100,     -- Cache this so the client doesn't recompute
		Prestige        = 0,       -- If you ever add a prestige system
	},

	-- ─── Cafe ────────────────────────────────────────────────────────────────
	-- Per-player cafe interaction data
	-- Note: cafe inventory/menu is server-side config, not stored per player

	Cafe = {
		TotalOrdersPlaced   = 0,
		TotalSpentInCafe    = 0,
		FavouriteItem       = "",      -- Item ID of most ordered item
		LoyaltyPoints       = 0,      -- Stamp card style rewards
		LoyaltyLevel        = 0,      -- Tier unlocked via loyalty points
	},

	-- ─── Balloon ─────────────────────────────────────────────────────────────
	-- Journey/experience tracking

	Balloon = {
		TotalJourneys       = 0,
		TotalJourneyTime    = 0,   -- Seconds spent on balloon journeys
		RoutesCompleted     = {},  -- Array of completed route IDs e.g. {"route_sunset", "route_night"}
		LastJourneyAt       = 0,
	},

	-- ─── Arcade ──────────────────────────────────────────────────────────────
	-- Per-minigame stats stored as a flat table keyed by game ID
	-- Avoids needing a new top-level key per minigame

	Arcade = {
		TotalGamesPlayed    = 0,
		TotalCoinsEarned    = 0,   -- Arcade-specific token/coin economy if you want one
		Highscores          = {},  -- { ["minigame_id"] = highscore: number }
		GamesPlayed         = {},  -- { ["minigame_id"] = timesPlayed: number }
		LastPlayedAt        = 0,
	},

	-- ─── SpinWheel ───────────────────────────────────────────────────────────

	SpinWheel = {
		TotalSpins          = 0,
		LastSpinAt          = 0,   -- Unix timestamp for daily spin cooldown
		FreeSpinsAvailable  = 1,   -- Granted on join daily
		PaidSpinsAvailable  = 0,   -- Purchased spins
	},

	-- ─── Customisation ───────────────────────────────────────────────────────
	-- Player cosmetic/identity preferences
	-- Keep IDs as strings so they're human readable in the datastore

	Customisation = {
		DisplayName         = "",      -- Their chosen in-game name if you have one
		NameColour          = "White", -- Colour ID for chat name
		ActiveTitle         = "",      -- Title ID displayed under name e.g. "Café Regular"
		ActiveBadge         = "",      -- Badge/flair ID
		UnlockedTitles      = {},      -- Array of unlocked title IDs
		UnlockedBadges      = {},      -- Array of unlocked badge IDs
	},

	-- ─── Social ──────────────────────────────────────────────────────────────
	-- Lightweight social features, not a full friends system

	Social = {
		TotalVisits         = 0,   -- How many times others have visited their plot/space if applicable
		IsPublicProfile     = true,
	},

	-- ─── Settings ────────────────────────────────────────────────────────────
	-- Player-controlled preferences, persisted across sessions

	Settings = {
		MusicEnabled        = true,
		SFXEnabled          = true,
		MusicVolume         = 0.5,
		SFXVolume           = 0.5,
		NotificationsEnabled = true,
		GraphicsQuality     = "Auto",  -- "Auto" | "Low" | "Medium" | "High"
	},

	-- ─── Quests ──────────────────────────────────────────────────────────────
	-- Light for now, port later — but schema is reserved

	Quests = {
		ActiveQuests        = {},  -- { questId: string, progress: number, startedAt: number }
		CompletedQuests     = {},  -- Array of completed quest IDs
		TotalCompleted      = 0,
	},

	-- ─── Analytics ───────────────────────────────────────────────────────────
	-- Data you never show the player but is invaluable for balancing
	-- and understanding how people actually play

	Analytics = {
		MostVisitedArea     = "",      -- Area ID of where they spend most time
		SessionLengths      = {},      -- Last N session lengths in seconds (cap at ~20 entries)
		FirstPurchaseAt     = 0,       -- Unix timestamp of first cash spend
	},

}

return DataTemplate