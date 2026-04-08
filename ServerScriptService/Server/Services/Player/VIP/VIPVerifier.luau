--!strict
-- ServerScriptService/Server/Util/VIPRoller.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIPTypes = require(ReplicatedStorage.Shared.Types.VIPTypes)

-- ─── Types ────────────────────────────────────────────────────────────────────

type MultiplierResult = VIPTypes.MultiplierResult
type RawWeightEntry = { multiplier: number, weight: number }
type BakedEntry = { m: number, c: number } -- Optimized keys: m=multiplier, c=cumulative
export type BakedTable = {
	entries: { BakedEntry },
	totalWeight: number
}

-- ─── Upvalues ─────────────────────────────────────────────────────────────────

local table_create = table.create
local table_insert = table.insert
local math_random  = math.random

-- ─── Module ───────────────────────────────────────────────────────────────────

local VIPRoller = {}

--[[
    Bakes a raw configuration table into a cumulative lookup table.
    Uses fixed memory allocation via table.create.
]]
function VIPRoller.bake(config: { RawWeightEntry }): BakedTable
	local size = #config
	local bakedEntries = table_create(size)
	local totalWeight = 0

	for i = 1, size do
		local entry = config[i]
		totalWeight += entry.weight

		-- We use optimized short-key objects for the baked table
		bakedEntries[i] = {
			m = entry.multiplier,
			c = totalWeight
		}
	end

	return {
		entries = bakedEntries,
		totalWeight = totalWeight
	}
end

--[[
    Performs a weighted roll against a baked table.
    Logic extracted from VIPService to ensure separation of concerns.
]]
function VIPRoller.roll(baked: BakedTable): MultiplierResult
	local entries = baked.entries
	local totalWeight = baked.totalWeight

	-- Generate a random float between 0 and totalWeight
	local roll = math_random() * totalWeight

	-- Linear search through cumulative weights 
	for i = 1, #entries do
		local entry = entries[i]
		if roll <= entry.c then
			-- Calculate original weight for logging/analytics [cite: 70, 71]
			local originalWeight = if i == 1 
				then entry.c 
				else entry.c - entries[i - 1].c

			return {
				multiplier = entry.m,
				weight     = originalWeight,
			}
		end
	end

	-- Fallback: Should be unreachable if table is baked correctly
	return { multiplier = 1, weight = 0 }
end

return VIPRoller