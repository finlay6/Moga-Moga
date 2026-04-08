--!strict

local format  = string.format
local find    = string.find
local match   = string.match
local gmatch  = string.gmatch
local gsub    = string.gsub
local sub     = string.sub
local rep     = string.rep
local reverse = string.reverse
local upper   = string.upper
local lower   = string.lower
local byte    = string.byte
local floor   = math.floor
local abs     = math.abs
local tcreate = table.create
local tinsert = table.insert
local tconcat = table.concat
local tfreeze = table.freeze
local tonumber = tonumber
local tostring = tostring
local ceil = math.ceil

local StringUtil = {}

export type TruncateOptions = {
	ellipsis: string?,
	preserveWords: boolean?,
}

-- ─── Trim ─────────────────────────────────────────────────────────────────────

function StringUtil.trim(s: string): string
	return match(s, "^%s*(.-)%s*$") :: string
end

function StringUtil.trimStart(s: string): string
	return match(s, "^%s*(.-)$") :: string
end

function StringUtil.trimEnd(s: string): string
	return match(s, "^(.-)%s*$") :: string
end

-- ─── Predicates ───────────────────────────────────────────────────────────────

function StringUtil.startsWith(s: string, prefix: string): boolean
	return sub(s, 1, #prefix) == prefix
end

function StringUtil.endsWith(s: string, suffix: string): boolean
	return suffix == "" or sub(s, -#suffix) == suffix
end

function StringUtil.contains(s: string, substr: string): boolean
	return find(s, substr, 1, true) ~= nil
end

function StringUtil.isEmpty(s: string): boolean
	return #s == 0
end

function StringUtil.isBlank(s: string): boolean
	return match(s, "^%s*$") ~= nil
end

function StringUtil.isAlpha(s: string): boolean
	return match(s, "^%a+$") ~= nil
end

function StringUtil.isAlphanumeric(s: string): boolean
	return match(s, "^%w+$") ~= nil
end

function StringUtil.isNumeric(s: string): boolean
	return tonumber(s) ~= nil
end

function StringUtil.isInteger(s: string): boolean
	return match(s, "^%-?%d+$") ~= nil
end

-- ─── Case ─────────────────────────────────────────────────────────────────────

function StringUtil.capitalize(s: string): string
	if #s == 0 then return s end
	return upper(sub(s, 1, 1)) .. lower(sub(s, 2))
end

function StringUtil.titleCase(s: string): string
	return (gsub(s, "(%a)([%w_']*)", function(first, rest)
		return upper(first) .. lower(rest)
	end))
end

function StringUtil.camelToSnake(s: string): string
	return lower(gsub(gsub(s, "(%u)", "_%1"), "^_", ""))
end

function StringUtil.snakeToCamel(s: string): string
	return (gsub(s, "_(%a)", upper))
end

function StringUtil.snakeToPascal(s: string): string
	return StringUtil.capitalize(StringUtil.snakeToCamel(s))
end

-- ─── Pad ──────────────────────────────────────────────────────────────────────

function StringUtil.padStart(s: string, targetLen: number, padChar: string?): string
	padChar = padChar or " "
	return rep(padChar :: string, math.max(0, targetLen - #s)) .. s
end

function StringUtil.padEnd(s: string, targetLen: number, padChar: string?): string
	padChar = padChar or " "
	return s .. rep(padChar :: string, math.max(0, targetLen - #s))
end

-- ─── Truncate ─────────────────────────────────────────────────────────────────

function StringUtil.truncate(s: string, maxLen: number, opts: TruncateOptions?): string
	if #s <= maxLen then return s end
	local ellipsis = (opts and opts.ellipsis) or "..."
	local truncated = sub(s, 1, maxLen - #ellipsis)
	if opts and opts.preserveWords then
		local lastSpace = match(truncated, "^(.*%s)%S*$")
		if lastSpace then
			truncated = match(lastSpace, "^(.-)%s*$") :: string
		end
	end
	return truncated .. ellipsis
end

-- ─── Split / Join ─────────────────────────────────────────────────────────────

function StringUtil.split(s: string, delim: string): { string }
	if delim == "" then
		local result: { string } = tcreate(#s)
		for i = 1, #s do result[i] = sub(s, i, i) end
		return result
	end
	local esc = gsub(delim, "([%^%]%.%*%+%-%?%(%)%[%{%}%%])", "%%%1")
	local result: { string } = tcreate(8)
	local n = 0
	for part in gmatch(s, "([^" .. esc .. "]*)") do
		n += 1
		result[n] = part
	end
	return result
end

function StringUtil.join(parts: { string }, delim: string?): string
	return tconcat(parts, delim or "")
end

-- ─── Count / Replace ─────────────────────────────────────────────────────────

function StringUtil.count(s: string, substr: string): number
	if substr == "" then return 0 end
	local n, start = 0, 1
	while true do
		local pos = find(s, substr, start, true)
		if pos == nil then break end
		n += 1
		start = pos + #substr
	end
	return n
end

function StringUtil.replace(s: string, from: string, to: string): string
	local esc    = gsub(from, "([%^%]%.%*%+%-%?%(%)%[%{%}%%])", "%%%1")
	local escTo  = gsub(to,   "%%", "%%%%")
	return (gsub(s, esc, escTo))
end

function StringUtil.replaceFirst(s: string, from: string, to: string): string
	local esc   = gsub(from, "([%^%]%.%*%+%-%?%(%)%[%{%}%%])", "%%%1")
	local escTo = gsub(to,   "%%", "%%%%")
	return (gsub(s, esc, escTo, 1))
end

-- ─── Number Formatting ────────────────────────────────────────────────────────

function StringUtil.formatNumber(value: number, places: number?): string
	local formatted: string
	if places and places > 0 then
		formatted = format("%." .. places .. "f", value)
	else
		formatted = tostring(floor(value))
	end
	local int, dec = match(formatted, "^(%-?%d+)(%.?.*)$")
	int = (int :: string):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return int .. (dec or "")
end

function StringUtil.formatCompact(value: number, places: number?): string
	places = places or 1
	local fmt = "%." .. places .. "f%s"
	local a    = abs(value)
	local sign = if value < 0 then "-" else ""
	if     a >= 1e12 then return sign .. format(fmt, a / 1e12, "T")
	elseif a >= 1e9  then return sign .. format(fmt, a / 1e9,  "B")
	elseif a >= 1e6  then return sign .. format(fmt, a / 1e6,  "M")
	elseif a >= 1e3  then return sign .. format(fmt, a / 1e3,  "K")
	else                  return sign .. tostring(floor(a))
	end
end

function StringUtil.formatOrdinal(n: number): string
	local a = abs(n) % 100
	local suffix: string
	if a >= 11 and a <= 13 then
		suffix = "th"
	else
		local d = a % 10
		suffix = if d == 1 then "st" elseif d == 2 then "nd" elseif d == 3 then "rd" else "th"
	end
	return tostring(n) .. suffix
end

function StringUtil.formatCurrency(value: number, symbol: string?, places: number?): string
	return (symbol or "$") .. StringUtil.formatNumber(value, places or 0)
end

function StringUtil.formatPercent(value: number, places: number?): string
	return StringUtil.formatNumber(value, places or 0) .. "%"
end

function StringUtil.formatBytes(bytes: number): string
	local units = { "B", "KB", "MB", "GB", "TB" }
	local v, i = bytes, 1
	while v >= 1024 and i < #units do
		v /= 1024
		i += 1
	end
	return if i == 1 then format("%d %s", v, units[i]) else format("%.1f %s", v, units[i])
end

-- ─── Template / Interpolation ─────────────────────────────────────────────────

-- Substitutes {key} placeholders from a vars table
function StringUtil.template(s: string, vars: { [string]: any }): string
	return (gsub(s, "{(%w+)}", function(k)
		local v = vars[k]
		return if v ~= nil then tostring(v) else "{" .. k .. "}"
	end))
end

-- Substitutes {} positional placeholders from varargs
function StringUtil.interpolate(s: string, ...: any): string
	local args = { ... }
	local i = 0
	return (gsub(s, "{}", function()
		i += 1
		return if args[i] ~= nil then tostring(args[i]) else "{}"
	end))
end

-- ─── Word Wrap ────────────────────────────────────────────────────────────────

function StringUtil.wrap(s: string, maxWidth: number): { string }
	local words: { string } = {}
	for w in gmatch(StringUtil.trim(s), "%S+") do
		tinsert(words, w)
	end
	local lines: { string } = tcreate(ceil(#s / maxWidth))
	local current = ""
	for _, word in words do
		if #current == 0 then
			current = word
		elseif #current + 1 + #word <= maxWidth then
			current = current .. " " .. word
		else
			tinsert(lines, current)
			current = word
		end
	end
	if #current > 0 then tinsert(lines, current) end
	return lines
end

-- ─── Hashing ──────────────────────────────────────────────────────────────────

-- djb2 — fast, good distribution for short strings
function StringUtil.hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = ((h * 33) + byte(s, i)) % 0x80000000
	end
	return h
end

-- FNV-1a — better avalanche for longer strings
function StringUtil.hashFNV1a(s: string): number
	local h = 0x811c9dc5
	for i = 1, #s do
		h = ((h + byte(s, i)) * 0x01000193) % 0x100000000
	end
	return h
end

-- ─── Misc ─────────────────────────────────────────────────────────────────────

function StringUtil.repeat_(s: string, n: number): string
	return rep(s, n)
end

function StringUtil.reverse(s: string): string
	return reverse(s)
end

function StringUtil.escapePattern(s: string): string
	return (gsub(s, "([%^%]%.%*%+%-%?%(%)%[%{%}%%])", "%%%1"))
end

function StringUtil.stripHtml(s: string): string
	return (gsub(s, "<[^>]+>", ""))
end

return tfreeze(StringUtil)