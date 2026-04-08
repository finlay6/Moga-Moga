--!strict
-- ServerScriptService/Server/Services/Core/DataStore/DataMigrationService.luau

--[[
	DataMigrationService

	Handles sequential schema upgrades for player profile data.
	Called once per session by SessionService, immediately after a profile loads.

	─── How to add a migration ─────────────────────────────────────────
	1. Increment CURRENT_VERSION by 1.
	2. Add a new function to MIGRATIONS keyed by the version it upgrades TO.
	   e.g. adding [3] migrates a profile from version 2 → 3.
	3. The function receives Profile.Data and mutates it in place.
	4. Do NOT return anything from the migration function.

	─── Guarantees ────────────────────────────────────────────────────
	- Each migration runs exactly once per profile.
	- Migrations are applied in strict ascending order.
	- A failed migration halts the chain — no further versions are applied.
	- data.Meta.DataVersion is updated after EACH successful step so a
	  partial migration chain is resumable on the next session.

	─── Example ───────────────────────────────────────────────────────
	[2] = function(data)
	    -- Rename Cash to Coins
	    data.Economy.Coins = data.Economy.Cash
	    data.Economy.Cash  = nil
	    -- Add new Gems field
	    data.Economy.Gems  = data.Economy.Gems or 0
	end,
]]

local Shared  = game:GetService("ReplicatedStorage").Shared
local Logger  = require(Shared.Util.Logger)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime = os.time
local pcall  = pcall

-- ─── Types ───────────────────────────────────────────────────────────────────
type ProfileData   = { [any]: any }
type MigrationFn   = (data: ProfileData) -> ()

-- ─── Constants ───────────────────────────────────────────────────────────────
local log = Logger.new("DataMigrationService")

-- Bump this whenever you add a new entry to MIGRATIONS below.
-- Must always equal the highest key in the table.
local CURRENT_VERSION: number = 1

-- ─── Migration Table ─────────────────────────────────────────────────────────
-- Key = the DataVersion the profile will have AFTER the migration runs.
-- Version 1 is the baseline — new profiles start here, no transform needed.
local MIGRATIONS: { [number]: MigrationFn } = {

	[1] = function(_data: ProfileData)
		-- Baseline schema. No transformation required.
		-- This entry exists so the version-tracking logic works from day one.
	end,

	-- ── Future migrations go here ──────────────────────────────────────────
	--
	-- [2] = function(data)
	--     -- Example: rename Economy.Cash → Economy.Coins
	--     data.Economy.Coins = data.Economy.Cash
	--     data.Economy.Cash  = nil
	--     -- Example: add a new field with a safe default
	--     data.Economy.Gems  = data.Economy.Gems or 0
	-- end,
	--
	-- [3] = function(data)
	--     -- Example: split a bool into a timestamp
	--     if data.VIP and data.VIP.IsVIP == true then
	--         data.VIP.ExpiresAt = 0 -- permanent, gamepass-based
	--     end
	-- end,

}

-- ─── Module ──────────────────────────────────────────────────────────────────
local DataMigrationService = {}

--[[
	migrate(data)

	Runs all pending migrations on a profile's Data table in order.
	Returns true if the profile is now at CURRENT_VERSION, false on failure.

	A false return means SessionService should kick the player — applying
	further gameplay logic on top of a partially-migrated profile is unsafe.
]]
function DataMigrationService.migrate(data: ProfileData): boolean
	-- Guard: data.Meta must exist (Reconcile should have ensured this).
	if type(data.Meta) ~= "table" then
		log:error("migrate() called with no data.Meta — profile is malformed")
		return false
	end

	local profileVersion: number = data.Meta.DataVersion or 0

	-- Already current — fast path, most common case.
	if profileVersion == CURRENT_VERSION then
		return true
	end

	-- This should never happen outside of a server rollback.
	if profileVersion > CURRENT_VERSION then
		log:error(
			"Profile version ({}) is AHEAD of CURRENT_VERSION ({}) — "
			.. "possible server rollback. Skipping migrations to avoid data loss.",
			profileVersion,
			CURRENT_VERSION
		)
		-- Treat as success: the profile is newer than this server, leave it alone.
		return true
	end

	log:info(
		"Migrating profile from version {} → {}",
		profileVersion,
		CURRENT_VERSION
	)

	-- ── Migration loop ────────────────────────────────────────────────────────
	-- Iterates from (profileVersion + 1) up to CURRENT_VERSION inclusive.
	-- Each step is wrapped in pcall so one bad migration doesn't crash the server.
	-- DataVersion is incremented AFTER each successful step — if the server crashes
	-- mid-chain, the next session resumes from the last successful version.
	--
	-- BUG FIXED: the original code had `return true` INSIDE this loop body,
	-- causing it to bail after the very first migration and never apply the rest.
	-- The only returns inside the loop are `return false` on failure.
	-- The success `return true` is OUTSIDE the loop, after all steps complete.

	for version = profileVersion + 1, CURRENT_VERSION do
		local migration: MigrationFn? = MIGRATIONS[version]

		if migration == nil then
			-- A gap in the migration table. Warn but keep going — the version
			-- bump still needs to happen so we don't re-attempt a missing step.
			log:warn("No migration function found for version {} — skipping step", version)
			data.Meta.DataVersion  = version
			data.Meta.LastUpdatedAt = osTime()
			continue
		end

		local ok, err = pcall(migration, data)

		if not ok then
			log:error(
				"Migration to version {} FAILED: {} — halting chain at version {}",
				version,
				tostring(err),
				data.Meta.DataVersion
			)
			-- Return false — SessionService will kick the player.
			-- DataVersion was NOT bumped, so the next session re-attempts this step.
			return false
		end

		-- Commit the version only after a successful step.
		data.Meta.DataVersion   = version
		data.Meta.LastUpdatedAt = osTime()
		log:debug("Migration step {} applied successfully", version)
	end

	log:info("Migration complete — profile is now at version {}", CURRENT_VERSION)
	return true
end

return DataMigrationService
