--!strict
-- ServerScriptService/Server/Services/Economy/EconomyTransactionService.luau

--[[
	EconomyTransactionService

	Maintains a capped audit trail of recent transactions per player.
	Uses an object pool to avoid GC pressure on a hot code path.

	─── Changes from the original ──────────────────────────────────────
	1. Ring buffer replaces table.remove(history, 1).
	   The original used tremove on index 1, which is O(n) — it shifts every
	   remaining element down on each overwrite. A ring buffer is O(1): we
	   just advance a head pointer and overwrite the slot in place.

	2. Pool is actually pre-populated.
	   The original called table.create(N) which only pre-allocates CAPACITY,
	   it does not fill the array with values. tremove on an empty array returns
	   nil, so acquireTransaction fell through to allocating a new table every
	   call during warm-up. The pool now starts with POOL_SIZE real entries.

	3. GetHistory returns a snapshot copy, not a direct reference.
	   The ring buffer's internal array has holes and a non-zero head pointer.
	   Returning it raw would expose unordered, possibly nil-containing slots.
	   GetHistory reconstructs a clean ordered slice (oldest → newest) on demand.
	   This is a read path — it's not called on every transaction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage.Shared

local EconomyConstants  = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes      = require(Shared.Types.EconomyTypes)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local tcreate = table.create
local tinsert = table.insert
local tremove = table.remove

-- ─── Types ───────────────────────────────────────────────────────────────────
type Transaction = EconomyTypes.Transaction

-- ─── Constants ───────────────────────────────────────────────────────────────
local HISTORY_LIMIT: number = EconomyConstants.TRANSACTION_HISTORY_LIMIT
local POOL_SIZE    : number = HISTORY_LIMIT * 8  -- enough for several full server cycles

-- ─── Private: Object Pool ─────────────────────────────────────────────────────
-- Transaction tables are pooled so Record() never allocates on the hot path
-- after warm-up. The pool is pre-populated at module load.

local _pool: { Transaction } = tcreate(POOL_SIZE)

local function _makeEmpty(): Transaction
	return {
		id            = "",
		currencyType  = "Cash",
		amount        = 0,
		balanceBefore = 0,
		balanceAfter  = 0,
		source        = "",
		timestamp     = 0,
		metadata      = nil,
	}
end

-- Pre-populate the pool so the first POOL_SIZE transactions never allocate.
for i = 1, POOL_SIZE do
	_pool[i] = _makeEmpty()
end

local function _acquire(): Transaction
	-- tremove on the last element is O(1) — no element shifting.
	return tremove(_pool) or _makeEmpty()
end

local function _release(tx: Transaction)
	tx.metadata = nil -- drop any table references to prevent leaks
	tinsert(_pool, tx)
end

-- ─── Private: Ring Buffer ─────────────────────────────────────────────────────
-- Each player gets a RingBuffer. Slots are pre-allocated with empty Transaction
-- objects from the pool so Record() only overwrites fields, never allocates.

type RingBuffer = {
	slots : { Transaction }, -- fixed-size array of HISTORY_LIMIT slots
	head  : number,          -- index of the NEXT write (0-based mod HISTORY_LIMIT)
	size  : number,          -- number of valid entries (0..HISTORY_LIMIT)
}

local function _makeRingBuffer(): RingBuffer
	local slots = tcreate(HISTORY_LIMIT)
	for i = 1, HISTORY_LIMIT do
		slots[i] = _acquire()
	end
	return { slots = slots, head = 0, size = 0 }
end

-- Writes into the ring, overwriting the oldest slot when full.
-- All field assignments happen on a pre-existing table — zero allocation.
local function _ringWrite(ring: RingBuffer, data: Transaction)
	-- head is 0-based; Lua arrays are 1-based, so +1 for indexing.
	local slot = ring.slots[ring.head + 1]

	slot.id            = data.id
	slot.currencyType  = data.currencyType
	slot.amount        = data.amount
	slot.balanceBefore = data.balanceBefore
	slot.balanceAfter  = data.balanceAfter
	slot.source        = data.source
	slot.timestamp     = data.timestamp
	slot.metadata      = data.metadata

	ring.head = (ring.head + 1) % HISTORY_LIMIT
	if ring.size < HISTORY_LIMIT then
		ring.size += 1
	end
end

-- Returns a clean ordered snapshot: oldest entry first, newest last.
local function _ringSnapshot(ring: RingBuffer): { Transaction }
	local count    = ring.size
	local snapshot = tcreate(count)

	if count == 0 then
		return snapshot
	end

	-- The oldest entry is at (head - size) mod HISTORY_LIMIT (0-based).
	local startIdx = (ring.head - count) % HISTORY_LIMIT

	for i = 0, count - 1 do
		local slot = ring.slots[((startIdx + i) % HISTORY_LIMIT) + 1]
		-- Shallow copy so callers can't corrupt the ring's internal tables.
		snapshot[i + 1] = {
			id            = slot.id,
			currencyType  = slot.currencyType,
			amount        = slot.amount,
			balanceBefore = slot.balanceBefore,
			balanceAfter  = slot.balanceAfter,
			source        = slot.source,
			timestamp     = slot.timestamp,
			metadata      = slot.metadata,
		}
	end

	return snapshot
end

-- ─── Private State ────────────────────────────────────────────────────────────
local _rings: { [Player]: RingBuffer } = {}

-- ─── Module ──────────────────────────────────────────────────────────────────
local EconomyTransactionService = {}

--[[
	Record(player, data)

	Writes a transaction into the player's ring buffer.
	O(1) — no allocation on the hot path after warm-up.
]]
function EconomyTransactionService.Record(player: Player, data: Transaction)
	local ring = _rings[player]
	if ring == nil then
		ring = _makeRingBuffer()
		_rings[player] = ring
	end
	_ringWrite(ring, data)
end

--[[
	GetHistory(player) → { Transaction }

	Returns an ordered snapshot of the player's recent transactions (oldest first).
	Returns an empty table if no transactions have been recorded.

	The returned tables are copies — mutating them does not affect internal state.
]]
function EconomyTransactionService.GetHistory(player: Player): { Transaction }
	local ring = _rings[player]
	if ring == nil then
		return {}
	end
	return _ringSnapshot(ring)
end

--[[
	Cleanup(player)

	Returns all ring buffer slots back to the pool and removes the player's entry.
	Called by EconomyService on PlayerRemoving.
]]
function EconomyTransactionService.Cleanup(player: Player)
	local ring = _rings[player]
	if ring == nil then return end

	for _, slot in ring.slots do
		_release(slot)
	end

	_rings[player] = nil
end

return EconomyTransactionService
