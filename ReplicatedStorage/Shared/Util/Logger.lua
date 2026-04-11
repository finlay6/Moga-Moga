--!strict
local RunService = game:GetService("RunService")

local format    = string.format
local tconcat   = table.concat
local tclear    = table.clear -- Essential for memory reuse
local osClock   = os.clock
local spawn     = task.spawn

-- ─── Config ───────────────────────────────────────────────────────────────────

local Level = table.freeze({
	DEBUG = 1,
	INFO  = 2,
	WARN  = 3,
	ERROR = 4,
	FATAL = 5,
})

local Config = {
	MinLevel    = Level.DEBUG,
	ShowTime    = false,
}

-- ─── Internal ─────────────────────────────────────────────────────────────────

local LABELS = table.freeze({
	[Level.DEBUG] = "🛠️ DEBUG",
	[Level.INFO]  = "✅ INFO",
	[Level.WARN]  = "🔆 WARN",
	[Level.ERROR] = "❌ ERROR",
	[Level.FATAL] = "💀 FATAL",
})

local CONTEXT = if RunService:IsServer() then "Server" else "Client"

-- Shared memory pool to avoid heap allocations during log emission
local SCRATCH_PARTS: { string } = table.create(8)
local SCRATCH_ARGS: { any }     = table.create(16)

local function interpolate(template: string, args: { any }): string
	local i = 0
	return (template:gsub("{}", function()
		i += 1
		local v = args[i]
		return if v ~= nil then tostring(v) else "{}"
	end))
end

local function emit(level: number, instancePrefix: string, template: string, ...)
	if level < Config.MinLevel then return end
	-- 1. Grab varargs without allocating a new table if possible
	-- In Luau, {...} is a heap allocation. We use table.pack/unpack logic or a pool.
	tclear(SCRATCH_ARGS)
	local argCount = select("#", ...)
	for i = 1, argCount do
		SCRATCH_ARGS[i] = select(i, ...)
	end

	-- 2. Build the message using the pre-allocated scratch table
	tclear(SCRATCH_PARTS)

	if Config.ShowTime then
		table.insert(SCRATCH_PARTS, format("[%.3fs]", osClock()))
	end

	-- instancePrefix already contains [CONTEXT] and [TAG]
	table.insert(SCRATCH_PARTS, instancePrefix)
	table.insert(SCRATCH_PARTS, "[" .. LABELS[level] .. "]")
	table.insert(SCRATCH_PARTS, " ")
	table.insert(SCRATCH_PARTS, interpolate(template, SCRATCH_ARGS))

	local message = tconcat(SCRATCH_PARTS)

	-- 3. Output
	if level <= Level.INFO then
		print(message)
	elseif level == Level.WARN then
		warn(message)
	else
		spawn(error, message, 0)
	end
end

-- ─── LoggerInstance ──────────────────────────────────────────────────────────

local Meta = {}
Meta.__index = Meta

function Meta:debug(template: string, ...) emit(Level.DEBUG, self._prefix, template, ...) end
function Meta:info(template: string, ...)  emit(Level.INFO, self._prefix, template, ...)  end
function Meta:warn(template: string, ...)  emit(Level.WARN, self._prefix, template, ...)  end
function Meta:error(template: string, ...) emit(Level.ERROR, self._prefix, template, ...) end
function Meta:fatal(template: string, ...) emit(Level.FATAL, self._prefix, template, ...) end

-- ─── Public API ───────────────────────────────────────────────────────────────

local Logger = {}
Logger.Level = Level

function Logger.new(tag: string)
	-- Pre-calculate the static part of the log string once per instance
	local prefix = format("[%s] [%s]", CONTEXT, tag)

	return setmetatable({ 
		tag = tag,
		_prefix = prefix 
	}, Meta)
end

return table.freeze(Logger)