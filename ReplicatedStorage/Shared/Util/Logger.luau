--[[
    Logger
    
    A structured logging utility for consistent, levelled, tagged output
    across all Services and Controllers.

    Usage:
        local Logger = require(ReplicatedStorage.Shared.Util.Logger)
        local log = Logger.new("CafeService")

        log:debug("Initialising menu items")
        log:info("Player {} ordered a {}", player.Name, itemName)
        log:warn("Stock running low for item {}", itemId)
        log:error("Transaction failed for player {}: {}", player.Name, reason)
        log:fatal("DataService failed to load — shutting down player {}", player.Name)

    Log Levels (in order of severity):
        DEBUG   — fine-grained detail, dev only
        INFO    — general lifecycle events
        WARN    — something unexpected but recoverable
        ERROR   — something failed, needs attention
        FATAL   — critical failure, unrecoverable

    To silence logs in production, set Logger.Config.MinLevel to Logger.Level.WARN
    or higher. Logs below that level are no-ops with zero overhead.
]]

local RunService = game:GetService("RunService")

-- ─── Types ───────────────────────────────────────────────────────────────────

export type LogLevel = number

export type LoggerInstance = {
	tag: string,
	debug: (self: LoggerInstance, template: string, ...any) -> (),
	info:  (self: LoggerInstance, template: string, ...any) -> (),
	warn:  (self: LoggerInstance, template: string, ...any) -> (),
	error: (self: LoggerInstance, template: string, ...any) -> (),
	fatal: (self: LoggerInstance, template: string, ...any) -> (),
}

-- ─── Config ──────────────────────────────────────────────────────────────────

local Logger = {}

Logger.Level = {
	DEBUG = 1,
	INFO  = 2,
	WARN  = 3,
	ERROR = 4,
	FATAL = 5,
}

-- Change this to Logger.Level.WARN (or higher) before releasing to production
-- to silence DEBUG and INFO logs entirely with zero performance cost
Logger.Config = {
	MinLevel     = Logger.Level.DEBUG,
	ShowLevel    = true,   -- prefix output with [LEVEL]
	ShowTag      = true,   -- prefix output with [Tag]
	ShowContext  = true,   -- prefix output with [Server] or [Client]
	ShowTime     = false,  -- prefix output with elapsed time (useful for sequences)
}

-- ─── Internal ────────────────────────────────────────────────────────────────

local LEVEL_LABELS = {
	[Logger.Level.DEBUG] = "DEBUG",
	[Logger.Level.INFO]  = "INFO",
	[Logger.Level.WARN]  = "WARN",
	[Logger.Level.ERROR] = "ERROR",
	[Logger.Level.FATAL] = "FATAL",
}

local CONTEXT = RunService:IsServer() and "Server" or "Client"

-- Formats a template string, substituting {} placeholders with arguments
-- e.g. format("Player {} ordered {}", "Alex", "latte") -> "Player Alex ordered latte"
local function format(template: string, ...: any): string
	local args = { ... }
	local index = 0
	return (template:gsub("{}", function()
		index += 1
		local arg = args[index]
		if arg == nil then
			return "{}"
		end
		return tostring(arg)
	end))
end

local function buildPrefix(level: LogLevel, tag: string): string
	local parts = {}

	if Logger.Config.ShowTime then
		table.insert(parts, string.format("[%.2fs]", os.clock()))
	end

	if Logger.Config.ShowContext then
		table.insert(parts, string.format("[%s]", CONTEXT))
	end

	if Logger.Config.ShowLevel then
		table.insert(parts, string.format("[%s]", LEVEL_LABELS[level]))
	end

	if Logger.Config.ShowTag then
		table.insert(parts, string.format("[%s]", tag))
	end

	if #parts == 0 then
		return ""
	end

	return table.concat(parts, " ") .. " "
end

local function emit(level: LogLevel, tag: string, template: string, ...: any)
	if level < Logger.Config.MinLevel then
		return
	end

	local message = buildPrefix(level, tag) .. format(template, ...)

	if level == Logger.Level.DEBUG or level == Logger.Level.INFO then
		print(message)
	elseif level == Logger.Level.WARN then
		warn(message)
	elseif level == Logger.Level.ERROR or level == Logger.Level.FATAL then
		-- error() with level 0 avoids pointing to Logger internals as the source
		-- task.spawn isolates it so it doesn't halt the calling thread
		task.spawn(error, message, 0)
	end
end

-- ─── LoggerInstance ──────────────────────────────────────────────────────────

local LoggerInstanceMeta = {}
LoggerInstanceMeta.__index = LoggerInstanceMeta

function LoggerInstanceMeta:debug(template: string, ...: any)
	emit(Logger.Level.DEBUG, self.tag, template, ...)
end

function LoggerInstanceMeta:info(template: string, ...: any)
	emit(Logger.Level.INFO, self.tag, template, ...)
end

function LoggerInstanceMeta:warn(template: string, ...: any)
	emit(Logger.Level.WARN, self.tag, template, ...)
end

function LoggerInstanceMeta:error(template: string, ...: any)
	emit(Logger.Level.ERROR, self.tag, template, ...)
end

function LoggerInstanceMeta:fatal(template: string, ...: any)
	emit(Logger.Level.FATAL, self.tag, template, ...)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Creates a new logger instance bound to a tag (typically the module name)
function Logger.new(tag: string): LoggerInstance
	assert(type(tag) == "string" and #tag > 0, "Logger.new requires a non-empty string tag")

	return setmetatable({
		tag = tag,
	}, LoggerInstanceMeta)
end

return Logger