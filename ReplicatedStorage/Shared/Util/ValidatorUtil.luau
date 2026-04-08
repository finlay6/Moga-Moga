--!strict

local floor   = math.floor
local abs     = math.abs
local huge    = math.huge
local tinsert = table.insert
local tconcat = table.concat
local tcreate = table.create
local tfreeze = table.freeze
local tostring = tostring
local type = type

local ValidatorUtil = {}

-- ─── Result Type ─────────────────────────────────────────────────────────────

export type Result = { ok: true } | { ok: false, reason: string }
export type Rule<T> = (value: T) -> Result

-- Reuse a single frozen pass result — zero allocation on the happy path
local PASS: Result = table.freeze({ ok = true } :: any)

local function pass(): Result
	return PASS
end

local function fail(reason: string): Result
	return { ok = false, reason = reason }
end

-- ─── Primitives ───────────────────────────────────────────────────────────────

function ValidatorUtil.isString(v: any): Result
	return if type(v) == "string" then pass() else fail("expected string, got " .. type(v))
end

function ValidatorUtil.isNumber(v: any): Result
	return if type(v) == "number" then pass() else fail("expected number, got " .. type(v))
end

function ValidatorUtil.isBoolean(v: any): Result
	return if type(v) == "boolean" then pass() else fail("expected boolean, got " .. type(v))
end

function ValidatorUtil.isTable(v: any): Result
	return if type(v) == "table" then pass() else fail("expected table, got " .. type(v))
end

function ValidatorUtil.isFunction(v: any): Result
	return if type(v) == "function" then pass() else fail("expected function, got " .. type(v))
end

function ValidatorUtil.notNil(v: any): Result
	return if v ~= nil then pass() else fail("value must not be nil")
end

function ValidatorUtil.isNil(v: any): Result
	return if v == nil then pass() else fail("expected nil, got " .. type(v))
end

-- ─── String Rules ─────────────────────────────────────────────────────────────

function ValidatorUtil.nonEmptyString(v: any): Result
	if type(v) ~= "string" then return fail("expected string") end
	return if #(v :: string) > 0 then pass() else fail("string must not be empty")
end

function ValidatorUtil.stringMinLength(min: number): Rule<any>
	return function(v: any)
		if type(v) ~= "string" then return fail("expected string") end
		return if #(v :: string) >= min then pass()
			else fail("string must be at least " .. min .. " characters")
	end
end

function ValidatorUtil.stringMaxLength(max: number): Rule<any>
	return function(v: any)
		if type(v) ~= "string" then return fail("expected string") end
		return if #(v :: string) <= max then pass()
			else fail("string must be at most " .. max .. " characters")
	end
end

function ValidatorUtil.stringLength(min: number, max: number): Rule<any>
	return function(v: any)
		if type(v) ~= "string" then return fail("expected string") end
		local len = #(v :: string)
		return if len >= min and len <= max then pass()
			else fail("string length must be " .. min .. "–" .. max .. " characters")
	end
end

function ValidatorUtil.matchesPattern(pattern: string): Rule<any>
	return function(v: any)
		if type(v) ~= "string" then return fail("expected string") end
		return if (v :: string):match(pattern) then pass()
			else fail("string does not match required pattern")
	end
end

-- ─── Number Rules ─────────────────────────────────────────────────────────────

function ValidatorUtil.isInteger(v: any): Result
	if type(v) ~= "number" then return fail("expected number") end
	return if (v :: number) == floor(v :: number) then pass() else fail("expected integer")
end

function ValidatorUtil.isPositive(v: any): Result
	if type(v) ~= "number" then return fail("expected number") end
	return if (v :: number) > 0 then pass() else fail("value must be positive")
end

function ValidatorUtil.isNonNegative(v: any): Result
	if type(v) ~= "number" then return fail("expected number") end
	return if (v :: number) >= 0 then pass() else fail("value must be non-negative")
end

function ValidatorUtil.isPositiveInteger(v: any): Result
	if type(v) ~= "number" then return fail("expected number") end
	local n = v :: number
	return if n > 0 and n == floor(n) then pass() else fail("expected positive integer")
end

function ValidatorUtil.isNonNegativeInteger(v: any): Result
	if type(v) ~= "number" then return fail("expected number") end
	local n = v :: number
	return if n >= 0 and n == floor(n) then pass() else fail("expected non-negative integer")
end

function ValidatorUtil.isFinite(v: any): Result
	if type(v) ~= "number" then return fail("expected number") end
	local n = v :: number
	return if n == n and n ~= huge and n ~= -huge then pass() else fail("value must be finite")
end

function ValidatorUtil.inRange(lo: number, hi: number): Rule<any>
	return function(v: any)
		if type(v) ~= "number" then return fail("expected number") end
		return if (v :: number) >= lo and (v :: number) <= hi then pass()
			else fail("value must be between " .. lo .. " and " .. hi)
	end
end

function ValidatorUtil.min(lo: number): Rule<any>
	return function(v: any)
		if type(v) ~= "number" then return fail("expected number") end
		return if (v :: number) >= lo then pass() else fail("value must be >= " .. lo)
	end
end

function ValidatorUtil.max(hi: number): Rule<any>
	return function(v: any)
		if type(v) ~= "number" then return fail("expected number") end
		return if (v :: number) <= hi then pass() else fail("value must be <= " .. hi)
	end
end

-- ─── Table / Array Rules ──────────────────────────────────────────────────────

function ValidatorUtil.nonEmptyTable(v: any): Result
	if type(v) ~= "table" then return fail("expected table") end
	return if next(v :: any) ~= nil then pass() else fail("table must not be empty")
end

function ValidatorUtil.isArray(v: any): Result
	if type(v) ~= "table" then return fail("expected table") end
	local t = v :: { any }
	local n = 0
	for _ in t do n += 1 end
	return if n == #t then pass() else fail("expected sequential array")
end

function ValidatorUtil.arrayMinLength(min: number): Rule<any>
	return function(v: any)
		if type(v) ~= "table" then return fail("expected table") end
		return if #(v :: any) >= min then pass()
			else fail("array must have at least " .. min .. " elements")
	end
end

function ValidatorUtil.arrayMaxLength(max: number): Rule<any>
	return function(v: any)
		if type(v) ~= "table" then return fail("expected table") end
		return if #(v :: any) <= max then pass()
			else fail("array must have at most " .. max .. " elements")
	end
end

function ValidatorUtil.hasKeys(keys: { string }): Rule<any>
	return function(v: any)
		if type(v) ~= "table" then return fail("expected table") end
		for _, k in keys do
			if (v :: any)[k] == nil then
				return fail("missing required key: " .. k)
			end
		end
		return pass()
	end
end

-- ─── Enum ─────────────────────────────────────────────────────────────────────

-- Builds a set at rule-creation time so checking is O(1) not O(n)
function ValidatorUtil.oneOf<T>(allowed: { T }): Rule<any>
	local set: { [any]: boolean } = {}
	local list: { string } = tcreate(#allowed)
	for i, v in allowed do
		set[v :: any] = true
		list[i] = tostring(v)
	end
	local listStr = tconcat(list, ", ")
	return function(v: any)
		return if set[v] then pass() else fail("must be one of: " .. listStr)
	end
end

-- ─── Composition ─────────────────────────────────────────────────────────────

function ValidatorUtil.all(rules: { Rule<any> }): Rule<any>
	return function(v: any)
		for _, rule in rules do
			local r = rule(v)
			if not r.ok then return r end
		end
		return pass()
	end
end

function ValidatorUtil.any(rules: { Rule<any> }): Rule<any>
	return function(v: any)
		local reasons: { string } = tcreate(#rules)
		for _, rule in rules do
			local r = rule(v)
			if r.ok then return pass() end
			tinsert(reasons, (r :: any).reason or "unknown")
		end
		return fail("all validations failed: " .. tconcat(reasons, "; "))
	end
end

function ValidatorUtil.optional(rule: Rule<any>): Rule<any>
	return function(v: any)
		if v == nil then return pass() end
		return rule(v)
	end
end

function ValidatorUtil.nullable(rule: Rule<any>): Rule<any>
	return ValidatorUtil.optional(rule)
end

function ValidatorUtil.not_(rule: Rule<any>, reason: string?): Rule<any>
	return function(v: any)
		local r = rule(v)
		return if r.ok
			then fail(reason or "value must not satisfy the rule")
			else pass()
	end
end

-- ─── Assertion Helpers ────────────────────────────────────────────────────────

function ValidatorUtil.assert(result: Result, label: string?)
	if not result.ok then
		local prefix = if label then label .. ": " else ""
		error(prefix .. ((result :: any).reason or "validation failed"), 2)
	end
end

function ValidatorUtil.validate(value: any, rule: Rule<any>, label: string?)
	ValidatorUtil.assert(rule(value), label)
end

function ValidatorUtil.check(value: any, rule: Rule<any>): boolean
	return rule(value).ok
end

return tfreeze(ValidatorUtil)