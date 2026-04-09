local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local ProductConstants = require(Shared.Constants.Player.ProductConstants)
local GamepassRegistry = ProductConstants.GamepassRegistry
local Signal = require(Shared.Packages.Signal)

local VIPOwnershipResolved = Signal() :: Signal.Signal<Player>

local function _gamePassPurchaseFinished(player: Player, passId: number, wasPurchased: boolean)
    if not wasPurchased then return end
    if passId == GamepassRegistry.GAMEPASS_ID_STANDARD or passId == GamepassRegistry.GAMEPASS_ID_PREMIUM then
        VIPOwnershipResolved:Fire(player)
    end
end

local ProductService = {}

ProductService.VIPOwnershipResolved = VIPOwnershipResolved

function ProductService.init()
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(_gamePassPurchaseFinished)
end


return ProductService