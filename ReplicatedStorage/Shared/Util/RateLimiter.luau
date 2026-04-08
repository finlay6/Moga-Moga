--!strict
local Players = game:GetService("Players")

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local b_create = buffer.create
local b_readf64 = buffer.readf64
local b_writef64 = buffer.writef64
local b_readu32 = buffer.readu32
local b_writeu32 = buffer.writeu32
local osClock = os.clock

-- ─── Constants ────────────────────────────────────────────────────────────────
-- Each "Bucket" takes 12 bytes: 8 for f64 (timestamp), 4 for u32 (count)
local BUCKET_SIZE = 12 
local MAX_SLOTS = 200 -- Adjust based on max player count + buffer
local BUFFER_SIZE = MAX_SLOTS * BUCKET_SIZE

-- ─── State ────────────────────────────────────────────────────────────────────
-- We use one buffer per "Action Type" (e.g. "EconomyEarn", "EconomySpend")
local Storage: { [string]: buffer } = {}
local SlotMap: { [number]: number } = {} -- UserId -> SlotIndex
local NextSlot = 0

-- ─── Private Helpers ─────────────────────────────────────────────────────────

local function getSlot(userId: number): number
	local slot = SlotMap[userId]
	if not slot then
		slot = NextSlot * BUCKET_SIZE
		SlotMap[userId] = slot
		NextSlot = (NextSlot + 1) % MAX_SLOTS -- Circular reuse
	end
	return slot
end

local function getActionBuffer(action: string): buffer
	local b = Storage[action]
	if not b then
		b = b_create(BUFFER_SIZE)
		Storage[action] = b
	end
	return b
end

-- ─── Module ──────────────────────────────────────────────────────────────────

local RateLimiter = {}

--- Checks if an action is allowed for a player.
--- @param player Player The player performing the action.
--- @param action string A unique key for the action (e.g., "CashEarn").
--- @param window number The time window in seconds.
--- @param maxHits number Maximum allowed hits within that window.
--- @return boolean allowed Returns true if within limits, false if throttled.
function RateLimiter.Check(player: Player, action: string, window: number, maxHits: number): boolean
	local userId = player.UserId
	if userId <= 0 then return true end -- Ignore NPCs/System

	local buf = getActionBuffer(action)
	local offset = getSlot(userId)

	local now = osClock()
	local lastReset = b_readf64(buf, offset)
	local count = b_readu32(buf, offset + 8)

	-- Check if window has expired
	if now - lastReset >= window then
		-- Reset bucket
		b_writef64(buf, offset, now)
		b_writeu32(buf, offset + 8, 1)
		return true
	end

	-- Increment count
	count += 1
	if count > maxHits then
		return false
	end

	b_writeu32(buf, offset + 8, count)
	return true
end

--- Cleans up mapping when a player leaves to prevent slot bloat.
function RateLimiter.Cleanup(player: Player)
	SlotMap[player.UserId] = nil
end

-- Initialize cleanup
Players.PlayerRemoving:Connect(RateLimiter.Cleanup)

return RateLimiter