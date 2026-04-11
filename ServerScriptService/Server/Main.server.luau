-- ServerScriptService/Server/Main.server.luau

local ServerScriptService = game:GetService("ServerScriptService")

local Server   = ServerScriptService.Server
local Services = Server.Services
local Core     = Services.Core
local Economy  = Services.Economy
local Player   = Services.Player
local VIP      = Player.VIP
local Meta     = Services.Meta

local SessionService           = require(Core.DataStore.SessionService)
local ProductService           = require(Player.ProductService)
local VIPService               = require(VIP.VIPService)
local AdminService             = require(Meta.AdminService)
local NametagService           = require(Player.NametagService)
local EconomyMultiplierService = require(Economy.EconomyMultiplierService)
local EconomyService           = require(Economy.EconomyService)

-- ─── Step 1: init() ───────────────────────────────────────────────────────────
-- Wire signals, bake tables, register handlers.
-- No player data is accessed here.
-- Order:
--   ProductService first — others connect to its signals in their own init()
--   VIPService — connects to ProductService.GamepassOwned
--   AdminService — receives VIPService to mirror VIP as rank 1
--   EconomyMultiplierService — receives VIPService for earn calculations
--   EconomyService, NametagService — no cross-service deps in init()

ProductService.init()
VIPService.init()
AdminService.init(VIPService)
EconomyMultiplierService.init(VIPService)
EconomyService.init()
NametagService.init()

-- ─── Step 2: Open the gate ───────────────────────────────────────────────────
-- SessionService.init() starts accepting players.
-- PlayerReady fires after each profile is loaded, migrated, and meta-stamped.

SessionService.init()

-- ─── Step 3: start() ─────────────────────────────────────────────────────────
-- Connect to SessionService.PlayerReady and resolve per-player state.

ProductService.start()
VIPService.start()
AdminService.start()
NametagService.start()
