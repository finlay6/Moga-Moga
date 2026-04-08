--!strict
-- ServerScriptService/Server/Util/VIPRoller.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIPTypes = require(ReplicatedStorage.Shared.Types.VIPTypes)

-- ─── Types ────────────────────────────────────────────────────────────────────

type MultiplierResult = VIPTypes.MultiplierResult
type RawWeightEntry = { multiplier: number, weight: number }

-- Wrapper for the raw buffer to pass the size and total weight around easily
export type BakedBufferTable = {
	buf: buffer,
	count: number,
	totalWeight: number
}

-- ─── Upvalues ─────────────────────────────────────────────────────────────────

local buffer_create   = buffer.create
local buffer_writef64 = buffer.writef64
local buffer_readf64  = buffer.readf64
local math_random     = math.random

-- ─── Module ───────────────────────────────────────────────────────────────────

local VIPRoller = {}

--[[
	Bakes a raw configuration table into a contiguous byte buffer.
	Memory Layout (16 bytes per entry):
	[Offset 0-7]  f64: Multiplier
	[Offset 8-15] f64: Cumulative Weight
]]
function VIPRoller.bake(config: { RawWeightEntry }): BakedBufferTable
	local count = #config

	-- Allocate exactly 16 bytes per entry
	local buf = buffer_create(count * 16)
	local totalWeight = 0

	for i = 1, count do
		local entry = config[i]
		totalWeight += entry.weight

		-- i - 1 gives us a 0-based index. Multiply by 16 bytes per entry.
		local offset = (i - 1) * 16

		buffer_writef64(buf, offset, entry.multiplier)
		buffer_writef64(buf, offset + 8, totalWeight)
	end

	return {
		buf = buf,
		count = count,
		totalWeight = totalWeight
	}
end

--[[
	Performs a weighted roll against a baked buffer table.
	Extracts both the multiplier and dynamically calculates the original weight.
]]
function VIPRoller.roll(baked: BakedBufferTable): MultiplierResult
	local buf = baked.buf
	local count = baked.count
	local totalWeight = baked.totalWeight

	-- Generate a random float between 0 and totalWeight
	local roll = math_random() * totalWeight

	-- Linear search through cumulative weights in the buffer
	for i = 1, count do
		local offset = (i - 1) * 16
		local cumulativeWeight = buffer_readf64(buf, offset + 8)

		if roll <= cumulativeWeight then
			local multiplier = buffer_readf64(buf, offset)
			local originalWeight: number

			-- Calculate original weight for logging/analytics
			if i == 1 then 
				originalWeight = cumulativeWeight
			else 
				local prevCumulative = buffer_readf64(buf, (i - 2) * 16 + 8)
				originalWeight = cumulativeWeight - prevCumulative
			end

			return {
				multiplier = multiplier,
				weight     = originalWeight,
			}
		end
	end

	-- Fallback: Should be unreachable if the buffer is baked correctly
	return { multiplier = 1, weight = 0 }
end

return VIPRoller