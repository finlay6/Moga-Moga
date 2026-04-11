--!strict
-- ReplicatedStorage/Shared/Constants/Player/ProductConstants.luau

--[[
	ProductConstants

	Single source of truth for every Roblox gamepass and developer product
	this game sells. ProductService reads these tables — nothing else should
	reference raw product IDs directly.

	─── Adding a gamepass ──────────────────────────────────────────────
	1. Add an entry to GamepassRegistry with a unique string key.
	2. Any service that cares connects to ProductService.GamepassPurchased
	   and checks entry.key.

	─── Adding a developer product ─────────────────────────────────────
	1. Add an entry to DevProductRegistry.
	2. ProductService dispatches ProcessReceipt to the registered handler key.
	   Register the actual handler function in ProductService.registerHandler().
]]

export type GamepassEntry = {
	id   : number,
	name : string,  -- human-readable, used in logs
}

export type DevProductEntry = {
	id          : number,
	name        : string,
	handlerKey  : string,  -- key used to look up the handler in ProductService
}

local ProductConstants = {
	GamepassRegistry = {} :: { [string]: GamepassEntry },
	DevProductRegistry = {} :: { [string]: DevProductEntry },
}

-- ─── Gamepasses ───────────────────────────────────────────────────────────────

ProductConstants.GamepassRegistry = {
	VIP = {
		id   = 000000001,  -- replace with real ID from Creator Hub
		name = "VIP",
	},
}

-- ─── Developer Products ───────────────────────────────────────────────────────
-- Add cash packs, gift products, etc. here.
-- Example:
--   CASH_PACK_SMALL = { id = 000000010, name = "100 Cash", handlerKey = "cashPack" },

ProductConstants.DevProductRegistry = {}

return table.freeze(ProductConstants)
