--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EconomyConstants = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes = require(Shared.Types.EconomyTypes)

local tcreate = table.create
local tremove = table.remove
local tinsert = table.insert

-- ─── Types ────────────────────────────────────────────────────────────────────
type Transaction = EconomyTypes.Transaction

-- ─── Private State ────────────────────────────────────────────────────────────
local HISTORY_LIMIT = EconomyConstants.TRANSACTION_HISTORY_LIMIT
local FREE_POOL: { Transaction } = tcreate(HISTORY_LIMIT * 5) -- Global pool
local PLAYER_HISTORY: { [Player]: { Transaction } } = {}

-- ─── Private Helpers ─────────────────────────────────────────────────────────

-- "Allocates" a transaction table by either grabbing from pool or creating new
local function acquireTransaction(): Transaction
	local tx = tremove(FREE_POOL)
	if tx then
		return tx
	end

	-- Fallback if pool is empty (initial startup)
	return {
		id = "",
		currencyType = "Cash",
		amount = 0,
		balanceBefore = 0,
		balanceAfter = 0,
		source = "",
		timestamp = 0,
		metadata = nil,
	} :: Transaction
end

-- Returns a transaction to the pool for reuse
local function releaseTransaction(tx: Transaction)
	tx.metadata = nil -- Clear references to prevent memory leaks
	tinsert(FREE_POOL, tx)
end

-- ─── Module ──────────────────────────────────────────────────────────────────
local EconomyTransactionService = {}

--- Records a new transaction using pooled memory.
function EconomyTransactionService.Record(player: Player, data: Transaction)
	local history = PLAYER_HISTORY[player]
	if not history then
		history = tcreate(HISTORY_LIMIT)
		PLAYER_HISTORY[player] = history
	end

	-- If at limit, recycle the oldest transaction
	if #history >= HISTORY_LIMIT then
		local oldest = tremove(history, 1)
		if oldest then releaseTransaction(oldest) end
	end

	-- Acquire a "clean" table and fill it
	local tx = acquireTransaction()
	tx.id = data.id
	tx.currencyType = data.currencyType
	tx.amount = data.amount
	tx.balanceBefore = data.balanceBefore
	tx.balanceAfter = data.balanceAfter
	tx.source = data.source
	tx.timestamp = data.timestamp
	tx.metadata = data.metadata

	tinsert(history, tx)
end

--- Returns the history for a player (read-only).
function EconomyTransactionService.GetHistory(player: Player): { Transaction }
	return PLAYER_HISTORY[player] or {}
end

--- Completely wipes and pools history when a player leaves.
function EconomyTransactionService.Cleanup(player: Player)
	local history = PLAYER_HISTORY[player]
	if not history then return end

	for _, tx in history do
		releaseTransaction(tx)
	end

	PLAYER_HISTORY[player] = nil
end

return EconomyTransactionService