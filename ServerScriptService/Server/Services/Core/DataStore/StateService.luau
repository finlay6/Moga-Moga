--!strict
-- ServerScriptService/Server/Services/Core/DataStore/StateService.luau

--[[
	StateService

	Dot-path read/write API over a player's profile data.
	All writes go through a single function so replication, dirty-flagging,
	and debugging hooks have exactly one place to live.

	Paths use dot notation:  "Economy.Cash"   "Meta.JoinCount"   "VIP.Tier"
	Numeric keys are supported: "Inventory.1"  "Slots.3"

	─── Why this module exists ─────────────────────────────────────────
	Without a centralised write path every service mutates profile.Data
	directly, making it impossible to add replication without touching
	every callsite. StateService is that single choke-point.

	─── What to do in the onChange signal ─────────────────────────────
	Wire your Replica/replication layer here.
	Example (ReplicaService / Plasma / your own system):

		StateService.onChange:Connect(function(player, path, value)
		    local replica = ReplicaService.getPlayerReplica(player)
		    if replica then
		        replica:SetValue(pathToArray(path), value)
		    end
		end)

	─── What NOT to do ─────────────────────────────────────────────────
	Do NOT bypass StateService for profile.Data mutations in gameplay code.
	Direct mutations are fine inside DataMigrationService (it runs before
	any service reads the data) and nowhere else.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared       = ReplicatedStorage.Shared
local Constants = Shared.Constants
local Server       = ServerScriptService.Server
local Core         = Server.Services.Core

local Logger        = require(Shared.Util.Logger)
local Signal        = require(Shared.Packages.Signal)
local SessionService= require(Core.DataStore.SessionService)
local DataStoreConstants = require(Constants.Core.DataStoreConstants)

local MAX_PATH_DEPTH = DataStoreConstants.MAX_PATH_DEPTH

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local strSplit  = string.split
local toNumber  = tonumber

-- ─── Types ───────────────────────────────────────────────────────────────────
type Node = { [string | number]: any }

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("StateService")

-- ─── Private: Path Navigation ────────────────────────────────────────────────

-- Converts a single path segment to either a number (for array keys)
-- or leaves it as a string (for dict keys).
local function _segmentToKey(segment: string): string | number
	return toNumber(segment) or segment
end

-- Helper to validate path format and depth
local function _isValidPath(segments: {string}): boolean
    local depth = #segments
    
    -- Limit depth to ensure it's not empty
    if depth == 0 or depth > MAX_PATH_DEPTH then
        return false
    end

    for _, segment in ipairs(segments) do
        -- If segment is empty, it means there was a ".." or leading/trailing dot
        if segment == "" then
            return false
        end
    end

    return true
end

--[[
	_navigate(root, path)

	Walks `root` along `path` and returns the parent node plus the final key.
	Returns (nil, nil) if any intermediate segment does not exist or is not a table.

	Kept as a single function shared by Get and Set to guarantee identical
	traversal semantics — no risk of the two drifting.
]]
local function _navigate(root: any, path: string): (Node?, string | number | nil)
    local segments = strSplit(path, ".")
    
    -- Abstraction: Validate before processing
    if not _isValidPath(segments) then
        return nil, nil
    end

    local depth   = #segments
    local current = root

    for i = 1, depth - 1 do
        local key = _segmentToKey(segments[i])
        local next = current[key]
        
        if type(next) ~= "table" then
            return nil, nil
        end
        current = next
    end

    return current :: Node, _segmentToKey(segments[depth])
end

-- ─── Module ──────────────────────────────────────────────────────────────────
local StateService = {}

--[[
	onChange : Signal<Player, string, any>

	Fires after every successful Set call.
	Arguments: (player, path, newValue)

	Wire your replication layer to this signal.
	Keep handlers non-yielding — they run synchronously inside Set.
]]
StateService.onChange = Signal() :: Signal.Signal<Player, string, any>

--[[
	Set(player, path, value)

	Writes `value` to `path` in the player's profile data.
	Fires StateService.onChange after the write so replication can react.

	No-ops silently if:
	  - The player's data is not loaded yet (profile not in SessionService)
	  - The path resolves to a non-existent intermediate node

	BUG FIXED (original): Set and Get used different SessionService access
	functions (_GetData vs _GetProfile + .Data), creating two code paths that
	could diverge if hooks were added to one but not the other. Both now use
	SessionService.GetData exclusively.
]]
function StateService.Set(player: Player, path: string, value: any)
	local data = SessionService.GetData(player)
	if data == nil then
		log:warn("Set({}, {}) — player data not ready", player.Name, path)
		return
	end

	local node, key = _navigate(data, path)
	if node == nil or key == nil then
		log:error("Set failed — path '{}' could not be resolved for {}", path, player.Name)
		return 
	end

	node[key] = value
	StateService.onChange:Fire(player, path, value)
end

--[[
	Get(player, path) → any

	Reads a value from `path` in the player's profile data.
	Returns nil if the data is not loaded or the path does not exist.
]]
function StateService.Get(player: Player, path: string): any
	local data = SessionService.GetData(player)
	if data == nil then
		return nil
	end

	local node, key = _navigate(data, path)
	if node == nil or key == nil then
		log:error("Get failed — path '{}' could not be resolved for {}", path, player.Name)
		return nil
	end

	return node[key]
end

--[[
	Increment(player, path, delta)

	Convenience wrapper for numeric fields.
	Equivalent to Set(player, path, Get(player, path) + delta).
	No-ops if the current value is not a number.
]]
function StateService.Increment(player: Player, path: string, delta: number)
	local current = StateService.Get(player, path)
	if type(current) ~= "number" then
		log:error(
			"Increment failed — '{}' is {} (expected number) for {}",
			path, type(current), player.Name
		)
		return
	end
	StateService.Set(player, path, current + delta)
end

return StateService
