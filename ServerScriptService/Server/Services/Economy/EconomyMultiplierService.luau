--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local EconomyConstants = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes = require(Shared.Types.EconomyTypes)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime = os.time
local floor = math.floor

-- ─── Private Helpers ─────────────────────────────────────────────────────────

-- Check if a sale is currently active based on timestamps
local function isSaleLive(): boolean
	local sale = EconomyConstants.Sale
	if not sale.IsActive then return false end

	local now = osTime()
	local startsAt = sale.StartsAt
	local endsAt = sale.EndsAt

	if startsAt > 0 and now < startsAt then return false end
	if endsAt > 0 and now > endsAt then return false end

	return true
end

-- ─── Module ──────────────────────────────────────────────────────────────────

local EconomyMultiplierService = {}

--- Calculates the final EARN amount for a player.
--- @param baseAmount number The raw amount before multipliers.
--- @param player Player The player receiving the currency.
--- @param context EconomyTypes.EarnContext The context controlling multipliers.
--- @return number The final floored integer amount.
function EconomyMultiplierService.CalculateEarn(baseAmount: number, player: Player, context: EconomyTypes.EarnContext): number
	local multiplier = 1.0

	-- 1. Apply VIP Multiplier (Earnings only)
	if context.applyVIP ~= false then
		-- In a real scenario, you'd check your VIPService here.
		-- Using a pcall/require pattern similar to what we discussed earlier.
		local VIP_MULT = EconomyConstants.VIP_EARN_MULTIPLIER
		multiplier *= VIP_MULT
	end

	-- 2. Apply Global Sale Multiplier
	if context.applySale ~= false and isSaleLive() then
		multiplier *= EconomyConstants.Sale.EarnMultiplier
	end

	-- 3. Apply Custom context multiplier (e.g., "Double Cash" powerup)
	if context.applyCustom then
		multiplier *= context.applyCustom
	end

	return floor(baseAmount * multiplier)
end

--- Calculates the discounted price for a purchase.
--- @param basePrice number The sticker price in the shop.
--- @param player Player? Optional player for personal discounts (like VIP).
--- @return number The final floored price.
function EconomyMultiplierService.CalculatePrice(basePrice: number, player: Player?): number
	local discount = 0.0

	-- 1. Apply Global Sale Discount
	if isSaleLive() then
		discount += EconomyConstants.Sale.SaleDiscount
	end

	-- 2. Apply VIP Discount (if applicable)
	if player then
		-- Logic for checking if player has a discount perk
		-- discount += 0.10 
	end

	local finalPrice = basePrice * (1 - discount)
	return math.max(1, floor(finalPrice)) -- Items should never be free or negative
end

return EconomyMultiplierService