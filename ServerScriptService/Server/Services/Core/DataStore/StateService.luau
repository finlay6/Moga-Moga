--!strict
-- ServerScriptService/Server/Services/Core/DataStore/StateService.luau

--[[
	StateService

	The single gate for all player data reads and writes.
	Every balance change, VIP update, and setting toggle goes through here.

	Centralising writes in one place means:
	  - Replica updates happen automatically (wire onChange once, done)
	  - Dirty-flagging, analytics hooks, and admin logging all live here
	  - No service can accidentally bypass replication

	─── Path format ────────────────────────────────────────────────────
	Dot-separated string. Numeric segments address array indices.
	  "Economy.Cash"         → data.Economy.Cash
	  "VIP.IsVIP"            → data.VIP.IsVIP
	  "Arcade.Highscores.1"  → data.Arcade.Highscores[1]

	─── Rules ──────────────────────────────────────────────────────────
	- ONLY StateService calls SessionService. No other module may.
	- Services define private path-string constants internally.
	  They do not expose raw paths to their callers.

	─── Connecting replication ─────────────────────────────────────────
	Wire this once in your server bootstrap after Replica setup:

	  StateService.OnChange:Connect(function(player, path, value)
	      local replica = ReplicaService.getForPlayer(player)
	      if replica then
	          replica:Set(pathToArray(path), value)
	      end
	  end)
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared         = ReplicatedStorage.Shared
local Server         = ServerScriptService.Server
local Core           = Server.Services.Core

local Logger         = require(Shared.Util.Logger)
local Signal         = require(Shared.Packages.Signal)
local SessionService = require(Core.DataStore.SessionService)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local strSplit = string.split
local toNumber = tonumber

-- ─── Types ───────────────────────────────────────────────────────────────────
type Node = { [string | number]: any }

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("StateService")

-- ─── Private: Path Navigation ────────────────────────────────────────────────

local function _segmentToKey(segment: string): string | number
	return toNumber(segment) or segment
end

-- Walks `root` along `path` and returns (parentNode, finalKey).
-- Returns (nil, nil) if any intermediate node is missing or not a table.
local function _resolvePath(root: any, path: string): (Node?, string | number | nil)
	local segments = strSplit(path, ".")
	local depth    = #segments
	local current  = root

	for i = 1, depth - 1 do
		local key  = _segmentToKey(segments[i])
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
	OnChange : Signal<Player, string, any>

	Fires after every successful Set or Increment call.
	Args: (player, path, newValue)

	This is the replication hook. Keep handlers non-yielding.
]]
StateService.OnChange = Signal() :: Signal.Signal<Player, string, any>

--[[
	Set(player, path, value)

	Writes `value` to `path` in the player's profile data.
	Fires OnChange after the write.

	Asserts if the player's data is not loaded — this means a service
	connected to Players.PlayerAdded instead of SessionService.PlayerReady.
	Fix the service, not this assert.
]]
function StateService.Set(player: Player, path: {string}, value: any)
	local data = SessionService.GetData(player)

	if data == nil then
		log:warn("StateService.Set({}) called for {} before profile loaded. Connect to SessionService.PlayerReady instead of Players.PlayerAdded.", path, player.Name)
		return
	end

	local dataType = path[1]
	local dataKey = path[2]
	local dataToChange = data[dataType][dataKey]
	
	if dataToChange == nil then
		return nil
	end
	
	data[dataType][dataKey] = value
	StateService.OnChange:Fire(player, dataKey, value)
	SessionService.UpdatePlayerReplica(player, path, value)
end

--[[
	Get(player, path) → any

	Reads from `path` in the player's profile data.
	Returns nil if the path does not exist.

	Asserts if the player's data is not loaded — same rule as Set.
]]
function StateService.Get(player: Player, path: {string}): any
	local data = SessionService.GetData(player)

	if data == nil then
		log:error("StateService.Get({}) called for {} before profile loaded. Connect to SessionService.PlayerReady instead of Players.PlayerAdded.", path, player.Name)
		return nil
	end

	local dataType = path[1]
	local dataKey = path[2]
	
	local dataToGet = data[dataType][dataKey]
	
	
	if dataToGet == nil then
		return nil
	end

	return dataToGet
end

return StateService
