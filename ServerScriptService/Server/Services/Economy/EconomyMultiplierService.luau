--!strict
-- ServerScriptService/Server/Services/Economy/EconomyMultiplierService.luau

--[[
	EconomyMultiplierService

	Calculates the final earn amount and discounted prices after all
	applicable multipliers / discounts are applied.

	─── Multiplier application order (earn) ────────────────────────────
	  1. VIP multiplier         (per-player, only if the player IS VIP)
	  2. Global sale multiplier (server-wide, only if a sale is live)
	  3. Custom/event multiplier (optional, passed in EarnContext)

	─── Changes from the original ──────────────────────────────────────
	BUG FIXED: CalculateEarn applied VIP_EARN_MULTIPLIER unconditionally to
	EVERY player regardless of VIP status. The check was stubbed out with a
	comment. It now calls VIPService.isVIP(player) and VIPService.getTier(player)
	correctly. Same fix applied to CalculatePrice.

	VIPService is required lazily inside init() to avoid a circular dependency
	at module load (EconomyService → MultiplierService → VIPService →
	EconomyService is the potential cycle). If your loader guarantees ordering,
	you can hoist the require to the top level.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Shared              = ReplicatedStorage.Shared
local EconomyConstants    = require(Shared.Constants.Economy.EconomyConstants)
local EconomyTypes        = require(Shared.Types.EconomyTypes)

-- ─── Upvalues ────────────────────────────────────────────────────────────────
local osTime = os.time
local floor  = math.floor
local max    = math.max

-- ─── Private State ───────────────────────────────────────────────────────────
-- VIPService is injected via init() to avoid circular require chains.
local _VIPService: any = nil

-- ─── Private: Sale Check ─────────────────────────────────────────────────────
local function _isSaleLive(): boolean
	local sale = EconomyConstants.Sale
	if not sale or not sale.IsActive then return false end

	local now      = osTime()
	local startsAt = sale.StartsAt or 0
	local endsAt   = sale.EndsAt   or 0

	if startsAt > 0 and now < startsAt then return false end
	if endsAt   > 0 and now > endsAt   then return false end

	return true
end

-- ─── Module ──────────────────────────────────────────────────────────────────
local EconomyMultiplierService = {}

--[[
	init(vipService)

	Must be called once during server startup with the live VIPService reference.
	Avoids a circular require by injecting the dependency.
]]
function EconomyMultiplierService.init(vipService: any)
	_VIPService = vipService
end

--[[
	CalculateEarn(baseAmount, player, context) → number

	Returns the final integer earn amount after all multipliers.

	Multiplier pipeline:
	  1. Start at 1.0
	  2. × VIP multiplier         (only if player IS VIP and context.applyVIP ~= false)
	  3. × Sale multiplier        (only if sale is live and context.applySale ~= false)
	  4. × context.applyCustom   (optional arbitrary multiplier, e.g. 2.0 for double-cash)

	Result is floored to an integer — currency is always whole numbers.
]]
function EconomyMultiplierService.CalculateEarn(
	baseAmount : number,
	player     : Player,
	context    : EconomyTypes.EarnContext
): number
	local multiplier = 1.0

	-- 1. VIP multiplier — only applied if the player actually has VIP.
	--    BUG FIXED: original applied this to everyone unconditionally.
	if context.applyVIP ~= false and _VIPService ~= nil then
		if _VIPService.isVIP(player) then
			local tier = _VIPService.getTier(player)
			if tier == EconomyConstants.VIP_TIER_PREMIUM then
				multiplier *= EconomyConstants.VIP_EARN_MULTIPLIER_PREMIUM
			elseif tier == EconomyConstants.VIP_TIER_STANDARD then
				multiplier *= EconomyConstants.VIP_EARN_MULTIPLIER_STANDARD
			end
		end
	end

	-- 2. Global sale multiplier.
	if context.applySale ~= false and _isSaleLive() then
		multiplier *= EconomyConstants.Sale.EarnMultiplier
	end

	-- 3. Custom one-off multiplier (e.g. a "Double Cash" server event).
	if context.applyCustom ~= nil then
		multiplier *= context.applyCustom
	end

	return floor(baseAmount * multiplier)
end

--[[
	CalculatePrice(basePrice, player?) → number

	Returns the final integer price after all applicable discounts.

	Discount pipeline:
	  1. Start at 0% discount
	  2. + Global sale discount   (if sale is live)
	  3. + VIP shop discount      (if player is VIP — only if player is supplied)

	Discounts are additive percentages applied to the base price.
	The result is clamped to a minimum of 1 (items can never be free or negative).
]]
function EconomyMultiplierService.CalculatePrice(
	basePrice : number,
	player    : Player?
): number
	local discount = 0.0

	-- 1. Global sale discount.
	if _isSaleLive() then
		discount += EconomyConstants.Sale.SaleDiscount
	end

	-- 2. VIP shop discount.
	--    BUG FIXED: original left this as a comment stub.
	if player ~= nil and _VIPService ~= nil then
		if _VIPService.isVIP(player) then
			discount += _VIPService.getShopDiscount(player)
		end
	end

	-- Clamp to [0, 1] so a misconfigured discount table can't produce
	-- free or negative-price items.
	local clampedDiscount = math.clamp(discount, 0, 1)
	local finalPrice      = basePrice * (1 - clampedDiscount)

	return max(1, floor(finalPrice))
end

return EconomyMultiplierService
