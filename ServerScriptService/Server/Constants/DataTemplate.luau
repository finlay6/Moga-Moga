-- ServerScriptService/Server/Constants/DataTemplate.luau

--[[
	DataTemplate

	The canonical default data structure for a player profile.
	ProfileStore uses this as the template for new profiles.
	Reconcile() will fill any missing fields when a profile loads.

	Rules:
	  - Every key that will ever exist in player data must be listed here
	  - Never store instances, player objects, or non-serialisable values
	  - All monetary values are integers (never floats)
	  - Timestamps are Unix time via os.time()
]]

local DataTemplate = {

	-- ─── Meta ────────────────────────────────────────────────────────────────

	Meta = {
		CreatedAt      = 0,
		LastSeenAt     = 0,
		LastUpdatedAt  = 0,
		SessionStartAt = 0,   -- set each join, cleared on leave; used for TotalPlayTime
		TotalPlayTime  = 0,
		JoinCount      = 0,
		DataVersion    = 1,
	},

	-- ─── Economy ─────────────────────────────────────────────────────────────

	Economy = {
		Cash            = 0,
		Gems            = 0,
		TotalCashEarned = 0,
		TotalCashSpent  = 0,
		TotalGemsEarned = 0,
		TotalGemsSpent  = 0,
	},

	-- ─── VIP ─────────────────────────────────────────────────────────────────

	VIP = {
		IsVIP        = false,
		ExpiresAt    = 0,      -- Unix timestamp, 0 = permanent
		PendingGrant = false,  -- set true by offline gifting; applied on next login
	},

	-- ─── Progression ─────────────────────────────────────────────────────────

	Progression = {
		Level         = 1,
		XP            = 0,
		XPToNextLevel = 100,
		Prestige      = 0,
	},

	-- ─── Customisation ───────────────────────────────────────────────────────

	Customisation = {
		DisplayName = "",          -- custom in-game name; "" = use player.Name
		Country     = "",          -- set on first join via nametag prompt
		NameColour  = "White",
		ActiveTitle = "",
		ActiveBadge = "",
		UnlockedTitles = {},
		UnlockedBadges = {},
	},

	-- ─── Settings ────────────────────────────────────────────────────────────

	Settings = {
		MusicEnabled         = true,
		SFXEnabled           = true,
		MusicVolume          = 0.5,
		SFXVolume            = 0.5,
		NotificationsEnabled = true,
		GraphicsQuality      = "Auto",
	},

	-- ─── Cafe ────────────────────────────────────────────────────────────────

	Cafe = {
		TotalOrdersPlaced  = 0,
		TotalSpentInCafe   = 0,
		FavouriteItem      = "",
		LoyaltyPoints      = 0,
		LoyaltyLevel       = 0,
	},

	-- ─── Balloon ─────────────────────────────────────────────────────────────

	Balloon = {
		TotalJourneys    = 0,
		TotalJourneyTime = 0,
		RoutesCompleted  = {},
		LastJourneyAt    = 0,
	},

	-- ─── Arcade ──────────────────────────────────────────────────────────────

	Arcade = {
		TotalGamesPlayed = 0,
		TotalCoinsEarned = 0,
		Highscores       = {},
		GamesPlayed      = {},
		LastPlayedAt     = 0,
	},

	-- ─── SpinWheel ───────────────────────────────────────────────────────────

	SpinWheel = {
		TotalSpins         = 0,
		LastSpinAt         = 0,
		FreeSpinsAvailable = 1,
		PaidSpinsAvailable = 0,
	},

	-- ─── Social ──────────────────────────────────────────────────────────────

	Social = {
		TotalVisits      = 0,
		IsPublicProfile  = true,
	},

	-- ─── Quests ──────────────────────────────────────────────────────────────

	Quests = {
		ActiveQuests    = {},
		CompletedQuests = {},
		TotalCompleted  = 0,
	},

	-- ─── Analytics ───────────────────────────────────────────────────────────

	Analytics = {
		MostVisitedArea  = "",
		SessionLengths   = {},
		FirstPurchaseAt  = 0,
	},

}

return DataTemplate
