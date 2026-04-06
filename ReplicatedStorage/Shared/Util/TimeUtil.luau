--!strict

local Native = require(script.Parent.Native)

local floor    = Native.floor
local abs      = Native.abs
local osTime   = Native.time
local osClock  = Native.clock
local osDate   = Native.date
local format   = Native.format
local tconcat  = Native.tconcat
local tcreate  = Native.tcreate
local tinsert  = Native.tinsert

-- ─── Constants ────────────────────────────────────────────────────────────────

local SECOND = 1
local MINUTE = 60
local HOUR   = 3600
local DAY    = 86400
local WEEK   = 604800
local MONTH  = 2592000
local YEAR   = 31536000

-- ─── Types ────────────────────────────────────────────────────────────────────

export type Duration = {
	days        : number,
	hours       : number,
	minutes     : number,
	seconds     : number,
	totalSeconds: number,
}

export type FormatOptions = {
	showDays   : boolean?,
	showHours  : boolean?,
	showMinutes: boolean?,
	showSeconds: boolean?,
	compact    : boolean?,
	padded     : boolean?,
	separator  : string?,
}

local TimeUtil = {}

TimeUtil.SECOND = SECOND
TimeUtil.MINUTE = MINUTE
TimeUtil.HOUR   = HOUR
TimeUtil.DAY    = DAY
TimeUtil.WEEK   = WEEK
TimeUtil.MONTH  = MONTH
TimeUtil.YEAR   = YEAR

-- ─── Core ─────────────────────────────────────────────────────────────────────

function TimeUtil.now(): number
	return osTime()
end

function TimeUtil.clockNow(): number
	return osClock()
end

function TimeUtil.sinceEpoch(timestamp: number): number
	return osTime() - timestamp
end

function TimeUtil.untilTimestamp(timestamp: number): number
	return timestamp - osTime()
end

function TimeUtil.isFuture(timestamp: number): boolean
	return timestamp > osTime()
end

function TimeUtil.isPast(timestamp: number): boolean
	return timestamp <= osTime()
end

-- ─── Cooldown ─────────────────────────────────────────────────────────────────

function TimeUtil.isCooldownActive(lastUsed: number, cooldownSeconds: number): boolean
	return osTime() - lastUsed < cooldownSeconds
end

function TimeUtil.cooldownRemaining(lastUsed: number, cooldownSeconds: number): number
	local rem = cooldownSeconds - (osTime() - lastUsed)
	return if rem > 0 then rem else 0
end

-- ─── Day Checks ───────────────────────────────────────────────────────────────

function TimeUtil.isSameDay(a: number, b: number): boolean
	local da = osDate("*t", a) :: any
	local db = osDate("*t", b) :: any
	return da.year == db.year and da.month == db.month and da.day == db.day
end

function TimeUtil.isToday(timestamp: number): boolean
	return TimeUtil.isSameDay(timestamp, osTime())
end

function TimeUtil.startOfDay(timestamp: number?): number
	local t = osDate("*t", timestamp or osTime()) :: any
	t.hour, t.min, t.sec = 0, 0, 0
	return os.time(t)
end

function TimeUtil.endOfDay(timestamp: number?): number
	return TimeUtil.startOfDay(timestamp) + DAY - 1
end

function TimeUtil.nextMidnight(timestamp: number?): number
	return TimeUtil.startOfDay(timestamp) + DAY
end

function TimeUtil.secondsUntilMidnight(): number
	return TimeUtil.nextMidnight() - osTime()
end

-- ─── Decompose ────────────────────────────────────────────────────────────────

function TimeUtil.decompose(totalSeconds: number): Duration
	totalSeconds = floor(abs(totalSeconds))
	local days    = floor(totalSeconds / DAY)
	local hours   = floor((totalSeconds % DAY) / HOUR)
	local minutes = floor((totalSeconds % HOUR) / MINUTE)
	local seconds = totalSeconds % MINUTE
	return {
		days         = days,
		hours        = hours,
		minutes      = minutes,
		seconds      = seconds,
		totalSeconds = totalSeconds,
	}
end

-- ─── Formatting ───────────────────────────────────────────────────────────────

function TimeUtil.format(totalSeconds: number, opts: FormatOptions?): string
	local o   = opts or {}
	local d   = TimeUtil.decompose(totalSeconds)
	local sep = o.separator or ":"
	local pad = o.padded ~= false
	local parts: { string } = tcreate(4)

	local function fmt(value: number, width: number?): string
		return if pad and width then format("%0" .. width .. "d", value) else tostring(value)
	end

	if o.compact then
		if     d.days > 0    then return format("%dd %dh %dm", d.days, d.hours, d.minutes)
		elseif d.hours > 0   then return format("%dh %dm", d.hours, d.minutes)
		elseif d.minutes > 0 then return format("%dm %ds", d.minutes, d.seconds)
		else                       return format("%ds", d.seconds)
		end
	end

	if o.showDays ~= false and d.days > 0 then
		tinsert(parts, fmt(d.days))
	end
	if o.showHours ~= false and (d.days > 0 or d.hours > 0) then
		tinsert(parts, fmt(d.hours, 2))
	end
	if o.showMinutes ~= false then
		tinsert(parts, fmt(d.minutes, 2))
	end
	if o.showSeconds ~= false then
		tinsert(parts, fmt(d.seconds, 2))
	end

	return tconcat(parts, sep)
end

function TimeUtil.formatVerbose(totalSeconds: number): string
	local d = TimeUtil.decompose(totalSeconds)
	local parts: { string } = tcreate(4)

	local function add(value: number, singular: string, plural: string)
		if value > 0 then
			tinsert(parts, value .. " " .. (if value == 1 then singular else plural))
		end
	end

	add(d.days,    "day",    "days")
	add(d.hours,   "hour",   "hours")
	add(d.minutes, "minute", "minutes")
	add(d.seconds, "second", "seconds")

	if #parts == 0 then return "0 seconds" end
	if #parts == 1 then return parts[1] end
	return tconcat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

function TimeUtil.formatRelative(timestamp: number): string
	local diff = osTime() - timestamp
	local a    = abs(diff)
	local past = diff >= 0

	local function label(value: number, unit: string): string
		local r = floor(value)
		local u = if r == 1 then unit else unit .. "s"
		return if past then r .. " " .. u .. " ago" else "in " .. r .. " " .. u
	end

	if     a < MINUTE then return if past then "just now" else "in a moment"
	elseif a < HOUR   then return label(a / MINUTE, "minute")
	elseif a < DAY    then return label(a / HOUR,   "hour")
	elseif a < WEEK   then return label(a / DAY,    "day")
	elseif a < MONTH  then return label(a / WEEK,   "week")
	elseif a < YEAR   then return label(a / MONTH,  "month")
	else                   return label(a / YEAR,   "year")
	end
end

function TimeUtil.formatClock(totalSeconds: number): string
	return TimeUtil.format(totalSeconds, {
		showDays = false, showHours = true,
		showMinutes = true, showSeconds = true,
		padded = true, separator = ":",
	})
end

function TimeUtil.formatShortClock(totalSeconds: number): string
	local d = TimeUtil.decompose(totalSeconds)
	return if d.hours > 0
		then format("%d:%02d:%02d", d.hours, d.minutes, d.seconds)
		else format("%d:%02d", d.minutes, d.seconds)
end

-- ─── Arithmetic ───────────────────────────────────────────────────────────────

function TimeUtil.addSeconds(ts: number, n: number): number return ts + n end
function TimeUtil.addMinutes(ts: number, n: number): number return ts + n * MINUTE end
function TimeUtil.addHours(ts: number, n: number): number   return ts + n * HOUR end
function TimeUtil.addDays(ts: number, n: number): number    return ts + n * DAY end
function TimeUtil.addWeeks(ts: number, n: number): number   return ts + n * WEEK end

function TimeUtil.toSeconds(d: {
	days: number?,
	hours: number?,
	minutes: number?,
	seconds: number?,
	}): number
	return ((d.days or 0) * DAY)
		+ ((d.hours or 0) * HOUR)
		+ ((d.minutes or 0) * MINUTE)
		+ (d.seconds or 0)
end

return table.freeze(TimeUtil)