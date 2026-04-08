--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = ServerScriptService.Server
local Services = Server.Services
local Core = Services.Core
local SessionService = require(Core.DataStore.SessionService)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)

local log = Logger.new("StateService")

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local split = string.split
local tonumber = tonumber

-- ─── Types ───────────────────────────────────────────────────────────────────
type Dict = { [string | number]: any }

-- ─── Private Helpers ─────────────────────────────────────────────────────────

-- Converts "Economy.Cash" or "Inventory.1" into a usable key
local function formatKey(key: string): string | number
	return tonumber(key) or key
end

-- Traverses the table and returns the parent node and the final key
-- Use this for both Getting and Setting to keep logic DRY
local function navigateToPath(root: any, path: string): (Dict?, (string | number)?)
	local keys = split(path, ".")
	local length = #keys
	local current = root

	for i = 1, length - 1 do
		local key = formatKey(keys[i])
		current = current[key]

		if type(current) ~= "table" then
			return nil, nil
		end
	end

	return current, formatKey(keys[length])
end

-- ─── Service ──────────────────────────────────────────────────────────────────

local StateService = {}

--- Updates a value at a specific path.
function StateService.Set(player: Player, path: string, value: any)
	local profile = SessionService.GetData(player)
	if not profile then return end

	local node, finalKey = navigateToPath(profile, path)

	if node and finalKey then
		node[finalKey] = value
		-- Here is where you'd trigger your Sera serialisation or Signals
	else
		log:error("Could not resolve path: {}", path)
	end
end

--- Retrieves a value from a specific path.
function StateService.Get(player: Player, path: string): any
	local profile = SessionService.GetProfile(player)
	if not profile then return nil end

	local node, finalKey = navigateToPath(profile.Data, path)

	return if node and finalKey then node[finalKey] else nil
end

return StateService