--!strict
-- ServerScriptService/Server/Services/Player/ProductService.luau

--[[
	ProductService

	Central authority for all Roblox product interactions.
	Owns gamepass ownership checks and developer product receipt handling.

	Responsibilities:
	  - Resolving gamepass ownership for every player on join (via start())
	  - Firing GamepassOwned on join so services can initialise correctly
	  - Wiring PromptGamePassPurchaseFinished for mid-session purchases
	  - Owning ProcessReceipt and dispatching to registered dev product handlers
	  - Exposing ownsGamepass() for one-off synchronous cache reads

	Does NOT:
	  - Know what VIP means — it fires a signal, VIPService reacts
	  - Know what a cash pack grants — EconomyService registers a handler
	  - Touch player data directly — downstream services own that

	─── How other services connect ─────────────────────────────────────
	  VIPService.init():
	    ProductService.GamepassOwned:Connect(function(player, entry)
	        if entry.key == "VIP" then ... end
	    end)

	  EconomyService.init():
	    ProductService.registerHandler("cashPack", function(player, productId)
	        EconomyService.EarnCash(player, 500, { source = Source.ROBUX_EXCHANGE })
	        return Enum.ProductPurchaseDecision.PurchaseGranted
	    end)
]]

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared

local ProductConstants = require(Shared.Constants.Player.ProductConstants)
local Logger           = require(Shared.Util.Logger)
local Signal           = require(Shared.Packages.Signal)
local SessionService   = require(ServerScriptService.Server.Services.Core.DataStore.SessionService)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local taskSpawn = task.spawn
local pcall     = pcall

-- ─── Types ───────────────────────────────────────────────────────────────────
type GamepassEntry   = ProductConstants.GamepassEntry
type DevProductEntry = ProductConstants.DevProductEntry

-- Resolved gamepass signal payload — includes the registry key so subscribers
-- don't need to do their own ID lookup.
export type GamepassSignalPayload = {
	key   : string,       -- registry key, e.g. "VIP"
	entry : GamepassEntry,
}

-- ─── State ───────────────────────────────────────────────────────────────────
local log = Logger.new("ProductService")

-- Per-player ownership cache. Populated on join, cleared on leave.
-- Key is the registry key string (e.g. "VIP"), value is always true.
-- Only entries the player OWNS appear — absent key means not owned.
local _ownershipCache: { [Player]: { [string]: true } } = {}

-- Dev product handlers registered by other services.
-- Key = handlerKey from DevProductRegistry.
local _handlers: { [string]: (player: Player, productId: number) -> Enum.ProductPurchaseDecision } = {}

-- ─── Module ──────────────────────────────────────────────────────────────────
local ProductService = {}

-- ─── Private ─────────────────────────────────────────────────────────────────

-- Checks a single gamepass and updates the cache. Yields.
local function _checkOneGamepass(player: Player, key: string, entry: GamepassEntry)
	local ok, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.id)
	end)

	if not ok then
		log:warn("UserOwnsGamePassAsync failed for {} (pass: {})", player.Name, entry.name)
		return
	end

	if owned then
		local cache = _ownershipCache[player]
		if cache then
			cache[key] = true
		end
	end
end

-- Resolves all gamepasses for a player in parallel, then fires GamepassOwned
-- for each one they own. Called after PlayerReady so profile is guaranteed loaded.
local function _resolveOwnership(player: Player)
	_ownershipCache[player] = {}

	-- Spawn one thread per gamepass so checks run in parallel.
	local threads = 0
	local done = 0

	for key, entry in ProductConstants.GamepassRegistry do
		threads += 1
		taskSpawn(function()
			_checkOneGamepass(player, key, entry)
			done += 1
		end)
	end

	-- Yield until all parallel checks finish.
	-- Each _checkOneGamepass yields once (the API call) so this resolves quickly.
	while done < threads do
		task.wait()
	end

	-- Fire signals for everything owned.
	local cache = _ownershipCache[player]
	if cache == nil then
		-- Player left during resolution.
		return
	end

	for key in cache do
		local entry = ProductConstants.GamepassRegistry[key]
		log:debug("{} owns gamepass: {}", player.Name, entry.name)
		ProductService.GamepassOwned:Fire(player, { key = key, entry = entry })
	end

	log:debug("Ownership resolution complete for {}", player.Name)
end

-- Fires on join (existing ownership) and on purchase.
-- Args: (player, GamepassSignalPayload)
ProductService.GamepassOwned = Signal() :: Signal.Signal<Player, GamepassSignalPayload>

-- Fires for every developer product receipt that is successfully processed.
-- Args: (player, productId)
ProductService.DevProductPurchased = Signal() :: Signal.Signal<Player, number>

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
	ownsGamepass(player, key) → boolean

	Synchronous cache read. Returns true if the player owned the gamepass
	at join time or purchased it this session.

	Returns false if the cache hasn't populated yet (player still loading)
	— do not use this in the join flow, only in mid-session gameplay checks.
]]
function ProductService.ownsGamepass(player: Player, key: string): boolean
	local cache = _ownershipCache[player]
	return cache ~= nil and cache[key] == true
end

--[[
	registerHandler(handlerKey, fn)

	Registers a developer product handler. Called by other services in their
	init() before any player can trigger a purchase.

	fn receives (player, productId) and must return a ProductPurchaseDecision.
]]
function ProductService.registerHandler(
	handlerKey : string,
	fn         : (player: Player, productId: number) -> Enum.ProductPurchaseDecision
)
	assert(_handlers[handlerKey] == nil, `ProductService: handler "{handlerKey}" already registered`)
	_handlers[handlerKey] = fn
	log:debug("Handler registered for key: {}", handlerKey)
end

-- ─── Lifecycle ───────────────────────────────────────────────────────────────

function ProductService.init()
	-- Mid-session purchase: fire GamepassOwned immediately so subscribers
	-- (VIPService) can update the player without a rejoin.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			if not wasPurchased then return end

			for key, entry in ProductConstants.GamepassRegistry do
				if entry.id == passId then
					local cache = _ownershipCache[player]
					if cache then
						cache[key] = true
					end
					log:info("{} purchased gamepass: {}", player.Name, entry.name)
					ProductService.GamepassOwned:Fire(player, { key = key, entry = entry })
					return
				end
			end
		end
	)

	-- Developer product receipt handler.
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if player == nil then
			-- Player left — return NotProcessedYet so Roblox retries on rejoin.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Find which registry entry matches this product.
		for _, entry in ProductConstants.DevProductRegistry do
			if entry.id == receiptInfo.ProductId then
				local handler = _handlers[entry.handlerKey]
				if handler == nil then
					log:error(
						"No handler registered for dev product {} (key: {})",
						entry.name, entry.handlerKey
					)
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end

				local ok, result = pcall(handler, player, receiptInfo.ProductId)
				if not ok then
					log:error("Handler error for {}: {}", entry.name, tostring(result))
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end

				if result == Enum.ProductPurchaseDecision.PurchaseGranted then
					ProductService.DevProductPurchased:Fire(player, receiptInfo.ProductId)
				end

				return result
			end
		end

		log:warn("Unrecognised dev product id: {}", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	log:info("ProductService initialised")
end

function ProductService.start()
	-- Resolve ownership for players already in the server.
	-- Uses SessionService.PlayerReady so profiles are guaranteed loaded.
	SessionService.PlayerReady:Connect(function(player: Player)
		taskSpawn(_resolveOwnership, player)
	end)

	-- Handle players already past the ready gate (Studio fast-load edge case).
	for _, player in Players:GetPlayers() do
		if SessionService.GetData(player) ~= nil then
			taskSpawn(_resolveOwnership, player)
		end
	end

	-- Cleanup on leave.
	Players.PlayerRemoving:Connect(function(player: Player)
		_ownershipCache[player] = nil
	end)

	log:info("ProductService started")
end

return ProductService
