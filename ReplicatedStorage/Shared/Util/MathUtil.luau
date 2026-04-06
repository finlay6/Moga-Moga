--!strict
--!native

local Native = require(script.Parent.Native)

local floor  = Native.floor
local ceil   = Native.ceil
local abs    = Native.abs
local sqrt   = Native.sqrt
local max    = Native.max
local min    = Native.min
local random = Native.random
local huge   = Native.huge
local pi     = Native.pi
local sin    = Native.sin
local cos    = Native.cos
local clamp  = Native.clamp
local band   = Native.band
local lshift = Native.lshift
local rshift = Native.rshift
local countlz = Native.countlz
local tfreeze = Native.tfreeze

local MathUtil = {}

export type Range = { min: number, max: number }

-- ─── Interpolation ────────────────────────────────────────────────────────────

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function MathUtil.inverseLerp(a: number, b: number, value: number): number
	if a == b then return 0 end
	return (value - a) / (b - a)
end

function MathUtil.remap(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return outMin + (outMax - outMin) * ((value - inMin) / (inMax - inMin))
end

-- ─── Clamping / Rounding ──────────────────────────────────────────────────────

function MathUtil.clamp(value: number, lo: number, hi: number): number
	return clamp(value, lo, hi)
end

function MathUtil.clamp01(value: number): number
	return clamp(value, 0, 1)
end

function MathUtil.round(value: number, places: number?): number
	if not places or places == 0 then
		return floor(value + 0.5)
	end
	local factor = 10 ^ places
	return floor(value * factor + 0.5) / factor
end

function MathUtil.roundToNearest(value: number, step: number): number
	return floor(value / step + 0.5) * step
end

function MathUtil.floorToNearest(value: number, step: number): number
	return floor(value / step) * step
end

function MathUtil.ceilToNearest(value: number, step: number): number
	return ceil(value / step) * step
end

-- ─── Sign / Type ──────────────────────────────────────────────────────────────

function MathUtil.sign(value: number): number
	return if value > 0 then 1 elseif value < 0 then -1 else 0
end

function MathUtil.isNaN(n: number): boolean
	return n ~= n
end

function MathUtil.isFinite(n: number): boolean
	return n == n and n ~= huge and n ~= -huge
end

-- ─── Bit Tricks (via bit32) ───────────────────────────────────────────────────

-- Returns true if n is an exact power of two
function MathUtil.isPowerOfTwo(n: number): boolean
	if n <= 0 then return false end
	return band(n, n - 1) == 0
end

-- Smallest power of two >= n
function MathUtil.nextPowerOfTwo(n: number): number
	if n <= 1 then return 1 end
	-- 32 - countlz gives floor(log2(n-1)) + 1
	return lshift(1, 32 - countlz(n - 1))
end

-- Floor log base 2 of a positive integer
function MathUtil.ilog2(n: number): number
	assert(n > 0, "ilog2: n must be positive")
	return 31 - countlz(n)
end

-- Fast integer power by squaring — avoids ^ for integer exponents
function MathUtil.ipow(base: number, exp: number): number
	local result = 1
	while exp > 0 do
		if band(exp, 1) == 1 then
			result *= base
		end
		base *= base
		exp = rshift(exp, 1)
	end
	return result
end

-- ─── Random ───────────────────────────────────────────────────────────────────

function MathUtil.randomFloat(lo: number, hi: number): number
	return lo + random() * (hi - lo)
end

function MathUtil.randomInt(lo: number, hi: number): number
	return random(lo, hi)
end

function MathUtil.randomSign(): number
	return if random() < 0.5 then -1 else 1
end

function MathUtil.randomBool(probability: number?): boolean
	return random() < (probability or 0.5)
end

function MathUtil.randomRange(r: Range): number
	return r.min + random() * (r.max - r.min)
end

-- ─── Easing ───────────────────────────────────────────────────────────────────

function MathUtil.smoothStep(edge0: number, edge1: number, x: number): number
	local t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function MathUtil.smootherStep(edge0: number, edge1: number, x: number): number
	local t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

function MathUtil.easeInQuad(t: number): number
	return t * t
end

function MathUtil.easeOutQuad(t: number): number
	return t * (2 - t)
end

function MathUtil.easeInOutQuad(t: number): number
	return if t < 0.5 then 2 * t * t else -1 + (4 - 2 * t) * t
end

function MathUtil.easeInCubic(t: number): number
	return t * t * t
end

function MathUtil.easeOutCubic(t: number): number
	local u = 1 - t
	return 1 - u * u * u
end

function MathUtil.easeInOutCubic(t: number): number
	return if t < 0.5 then 4 * t * t * t else (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
end

function MathUtil.easeOutBounce(t: number): number
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t -= 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t -= 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t -= 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end

function MathUtil.easeInBounce(t: number): number
	return 1 - MathUtil.easeOutBounce(1 - t)
end

-- ─── Angle ────────────────────────────────────────────────────────────────────

function MathUtil.deltaAngle(from: number, to: number): number
	local d = (to - from) % 360
	return if d > 180 then d - 360 else d
end

function MathUtil.lerpAngle(a: number, b: number, t: number): number
	return a + MathUtil.deltaAngle(a, b) * t
end

function MathUtil.radians(degrees: number): number
	return degrees * (pi / 180)
end

function MathUtil.degrees(radians: number): number
	return radians * (180 / pi)
end

-- ─── Range Checks ────────────────────────────────────────────────────────────

function MathUtil.inRange(value: number, lo: number, hi: number): boolean
	return value >= lo and value <= hi
end

function MathUtil.approximately(a: number, b: number, epsilon: number?): boolean
	return abs(a - b) <= (epsilon or 1e-9)
end

function MathUtil.pingPong(t: number, length: number): number
	local v = t % (length * 2)
	return length - abs(v - length)
end

-- ─── Economy Math ─────────────────────────────────────────────────────────────
-- Kept here because integer economy math belongs in one place.
-- All results floored to integers — never store currency as a float.

function MathUtil.applyPercent(value: number, percent: number): number
	return floor(value * percent / 100)
end

function MathUtil.taxed(value: number, taxPercent: number): number
	return value - MathUtil.applyPercent(value, taxPercent)
end

function MathUtil.percentOf(part: number, whole: number): number
	return (part / whole) * 100
end

-- ─── Number Theory ────────────────────────────────────────────────────────────

function MathUtil.gcd(a: number, b: number): number
	a, b = abs(a), abs(b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

function MathUtil.lcm(a: number, b: number): number
	return abs(a * b) / MathUtil.gcd(a, b)
end

return tfreeze(MathUtil)