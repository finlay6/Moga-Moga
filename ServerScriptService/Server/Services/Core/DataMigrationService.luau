--!strict

--[[
    DataMigrationService

    Handles schema version migrations for player data.
    Called once per session after a profile is loaded.

    How to add a migration:
        1. Increment CURRENT_VERSION
        2. Add a new function to MIGRATIONS keyed by the version it upgrades TO
        3. The function receives Profile.Data and mutates it in place

    Migrations run in order from the player's current version up to CURRENT_VERSION.
    Each migration only runs once per profile — the DataVersion in Meta tracks progress.

    Example migration (renaming a key):
        [2] = function(data)
            data.Economy.Coins = data.Economy.OldCurrencyName
            data.Economy.OldCurrencyName = nil
        end
]]

local Shared    = game.ReplicatedStorage.Shared
local Logger    = require(Shared.Util.Logger)
local Native = require(Shared.Util.Native)

local osTime = Native.time
local pcall = Native.pcall

local log = Logger.new("DataMigration")

-- ─── Version ─────────────────────────────────────────────────────────────────

-- Bump this whenever you add a new migration below.
-- Must always equal the highest key in MIGRATIONS.
local CURRENT_VERSION = 1

-- ─── Migrations ──────────────────────────────────────────────────────────────

type MigrationFn = (data: { [any]: any }) -> ()

-- Each key is the DataVersion the profile will have AFTER this migration runs.
-- Version 1 is the baseline — no migration needed, it's just the initial template.
local MIGRATIONS: { [number]: MigrationFn } = {

	[1] = function(_data)
		-- Baseline — no migration needed for initial schema
	end,

	-- Example of what a future migration looks like:
	--
	-- [2] = function(data)
	--     -- Rename Economy.Cash to Economy.Coins
	--     data.Economy.Coins = data.Economy.Cash
	--     data.Economy.Cash = nil
	
	--     -- Add a new field that didn't exist before
	--     data.Economy.Gems = data.Economy.Gems or 0
	-- end,
	----
	-- [3] = function(data)
	--     -- Move VIP expiry from a bool to a timestamp
	--     if data.VIP.IsVIP == true then
	--         data.VIP.ExpiresAt = math.huge -- treat existing VIP as permanent
	--     end
	-- end,

}

-- ─── Public ───────────────────────────────────────────────────────────────────

local DataMigrationService = {}

-- Runs all pending migrations on a profile's Data table.
-- Called by DataService immediately after a session starts.
function DataMigrationService.migrate(data: { [any]: any })
	local currentVersion = data.Meta and data.Meta.DataVersion or 0

	if currentVersion == CURRENT_VERSION then
		return -- Already up to date, nothing to do
	end

	if currentVersion > CURRENT_VERSION then
		-- This should never happen in production — would mean a rollback occurred
		log:error(
			"Profile DataVersion ({}) is AHEAD of CURRENT_VERSION ({}) — skipping migrations",
			currentVersion,
			CURRENT_VERSION
		)
		return
	end

	log:info(
		"Migrating profile from version {} to {}",
		currentVersion,
		CURRENT_VERSION
	)

	for version = currentVersion + 1, CURRENT_VERSION do
		local migration = MIGRATIONS[version]
		if migration == nil then
			log:warn("No migration found for version {} — skipping", version)
			continue
		end

		local ok, err = pcall(migration, data)
		if ok then
			data.Meta.DataVersion = version
			data.Meta.LastUpdatedAt = osTime()
			log:debug("Migration to version {} applied successfully", version)
		else
			log:error("Migration to version {} FAILED: {}", version, err)
			-- Stop here — don't apply further migrations on top of a broken state
			break
		end
	end
end

return DataMigrationService