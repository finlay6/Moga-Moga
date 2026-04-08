--!strict
-- ServerScriptService/Server/Services/Player/VIP/VIPRoller.luau

--[[
	VIPRoller

	Weighted random selection from a probability table.
	Used by VIPService to roll wheel multipliers and icon multipliers.

	─── Design ─────────────────────────────────────────────────────────
	bake()  — converts a raw { multiplier, weight }[] config into a
	           pre-processed BakedTable. Called ONCE at startup.
	roll()  — performs a weighted random draw against a BakedTable.
	           Called every time a player spins the wheel or collects an icon.
	           Zero allocation — reads from the pre-baked table, returns a
	           stack-allocated result struct only.

	─── Why table-based (not buffer-based) ─────────────────────────────
	The original codebase had two implementations: a buffer-based one
	(VIPRoller.luau) and a table-based one (VIPVerifier.luau, misnamed).
	We keep the table-based approach because:
	  - VIP multiplier tables have < 20 entries in any realistic configuration.
	  - At that scale, table field access is faster than buffer.readf64 (no
	    C→Lua boundary crossing per read).
	  - The table version is readable without knowing the byte layout.
	  - The buffer version used f64 for weights, costing 8 bytes per field
	    where a Lua number already IS a double — no space saving.
	
	If the table ever grows to hundreds of entries, swap bake() to a buffer
	and roll() to a binary search. At < 20 entries, linear scan is fastest.

	─── Merging the two files ───────────────────────────────────────────
	VIPVerifier.luau was erroneously a copy of VIPRoller, not a verifier.
	VIPVerifier.luau has been replaced with a real ownership checker
	(see VIPVerifier.luau). This file is the single VIPRoller implementation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIPTypes          = require(ReplicatedStorage.Shared.Types.VIPTypes)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local tcreate    = table.create
local mathRandom = math.random

-- ─── Types ───────────────────────────────────────────────────────────────────
type WeightEntry    = VIPTypes.WeightEntry
type BakedTable     = VIPTypes.BakedTable
type MultiplierResult = VIPTypes.MultiplierResult

-- ─── Module ──────────────────────────────────────────────────────────────────
local VIPRoller = {}

--[[
	bake(config) → BakedTable

	Pre-processes a raw weight config into cumulative-weight form.
	Allocates exactly #config entry tables up front via table.create.

	Call this ONCE per config at startup. Never call it inside a roll loop.

	config format:
	  { { multiplier = 2.0, weight = 10 }, { multiplier = 1.5, weight = 30 }, ... }
]]
function VIPRoller.bake(config: { WeightEntry }): BakedTable
	local count       = #config
	local entries     = tcreate(count)
	local totalWeight = 0

	for i = 1, count do
		local entry   = config[i]
		totalWeight  += entry.weight
		-- Short keys (m, c) reduce table field lookup time when roll() is hot.
		entries[i] = { m = entry.multiplier, c = totalWeight }
	end

	return {
		entries     = entries,
		totalWeight = totalWeight,
	}
end

--[[
	roll(baked) → MultiplierResult

	Performs a weighted random draw. O(n) linear scan — fast for small tables.
	Returns the multiplier and its original (non-cumulative) weight.

	The weight field is provided for logging/analytics only.
	Callers (VIPService) apply result.multiplier to the base reward amount.

	Fallback { multiplier = 1, weight = 0 } should be unreachable if the
	config table is non-empty and all weights are positive.
]]
function VIPRoller.roll(baked: BakedTable): MultiplierResult
	local entries     = baked.entries
	local totalWeight = baked.totalWeight
	local roll        = mathRandom() * totalWeight

	for i = 1, #entries do
		local entry = entries[i]
		if roll <= entry.c then
			-- Original weight = cumulative[i] - cumulative[i-1]  (or just c if i == 1)
			local originalWeight: number = if i == 1
				then entry.c
				else entry.c - entries[i - 1].c

			return {
				multiplier = entry.m,
				weight     = originalWeight,
			}
		end
	end

	-- Unreachable with a valid baked table (roll ≤ totalWeight always).
	return { multiplier = 1, weight = 0 }
end

return VIPRoller
