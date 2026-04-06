local RunService = game:GetService("RunService")

local Native = require(script.Parent.Native)

local format   = Native.format
local tconcat  = Native.tconcat
local tcreate  = Native.tcreate
local tinsert  = Native.tinsert
local tfreeze = Native.tfreeze
local osClock  = Native.clock
local spawn    = Native.spawn
local bcreate  = Native.bcreate
local bwritef64 = Native.bwritef64
local breadf64  = Native.breadf64

-- ─── Config ───────────────────────────────────────────────────────────────────

local Level = tfreeze({
	DEBUG = 1,
	INFO  = 2,
	WARN  = 3,
	ERROR = 4,
	FATAL = 5,
})

local Config = {
	MinLevel    = Level.DEBUG,
	ShowLevel   = true,
	ShowTag     = true,
	ShowContext = true,
	ShowTime    = false,
}

-- ─── Internal ─────────────────────────────────────────────────────────────────

local LABELS = tfreeze({
	[Level.DEBUG] = "🛠️ DEBUG",
	[Level.INFO]  = "✅ INFO",
	[Level.WARN]  = "⚠️ WARN",
	[Level.ERROR] = "❌ ERROR",
	[Level.FATAL] = "💀 FATAL",
})

local CONTEXT = if RunService:IsServer() then "Server" else "Client"

-- Pre-allocated scratch buffer for the ShowTime prefix path.
-- Holds one f64 clock value — avoids a heap allocation per emit
-- on the uncommon ShowTime path.
local _clockBuf = bcreate(8)

local function interpolate(template: string, args: { any }): string
	local i = 0
	return (template:gsub("{}", function()
		i += 1
		local v = args[i]
		return if v ~= nil then tostring(v) else "{}"
	end))
end

local function buildPrefix(level: number, tag: string): string
	if not Config.ShowLevel and not Config.ShowTag
		and not Config.ShowContext and not Config.ShowTime then
		return ""
	end

	local parts: { string } = tcreate(4)

	if Config.ShowTime then
		bwritef64(_clockBuf, 0, osClock())
		tinsert(parts, format("[%.3fs]", breadf64(_clockBuf, 0)))
	end

	if Config.ShowContext then tinsert(parts, "[" .. CONTEXT .. "]") end
	if Config.ShowLevel   then tinsert(parts, "[" .. LABELS[level] .. "]") end
	if Config.ShowTag     then tinsert(parts, "[" .. tag .. "]") end

	return tconcat(parts, " ") .. " "
end

local function emit(level: number, tag: string, template: string, args: { any })
	if level < Config.MinLevel then return end

	local message = buildPrefix(level, tag) .. interpolate(template, args)

	if level <= Level.INFO then
		print(message)
	elseif level == Level.WARN then
		warn(message)
	else
		spawn(error, message, 0)
	end
end

-- ─── LoggerInstance ──────────────────────────────────────────────────────────

export type LoggerInstance = {
	tag  : string,
	debug: (self: LoggerInstance, template: string, ...any) -> (),
	info : (self: LoggerInstance, template: string, ...any) -> (),
	warn : (self: LoggerInstance, template: string, ...any) -> (),
	error: (self: LoggerInstance, template: string, ...any) -> (),
	fatal: (self: LoggerInstance, template: string, ...any) -> (),
}

local Meta = {}
Meta.__index = Meta

function Meta:debug(template: string, ...: any)
	emit(Level.DEBUG, self.tag, template, { ... })
end

function Meta:info(template: string, ...: any)
	emit(Level.INFO, self.tag, template, { ... })
end

function Meta:warn(template: string, ...: any)
	emit(Level.WARN, self.tag, template, { ... })
end

function Meta:error(template: string, ...: any)
	emit(Level.ERROR, self.tag, template, { ... })
end

function Meta:fatal(template: string, ...: any)
	emit(Level.FATAL, self.tag, template, { ... })
end

-- ─── Public API ───────────────────────────────────────────────────────────────

local Logger = {}

Logger.Level  = Level
Logger.Config = Config

function Logger.new(tag: string): LoggerInstance
	assert(type(tag) == "string" and #tag > 0,
		"Logger.new: tag must be a non-empty string")
	return setmetatable({ tag = tag }, Meta) :: any
end

function Logger.setLevel(level: number)
	assert(level >= Level.DEBUG and level <= Level.FATAL,
		"Logger.setLevel: invalid level")
	Config.MinLevel = level
end

function Logger.silenceDebug()
	Config.MinLevel = Level.WARN
end

return tfreeze(Logger)