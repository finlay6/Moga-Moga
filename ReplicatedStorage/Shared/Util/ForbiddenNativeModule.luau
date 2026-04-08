--!strict
-- Here be dragons. Fast ones.
-- Technically can use this, would not recommend this though lol. Super funky. If any player steals this script, they will be cursed, I promise.
--
-- Two things live here:
--   1. Stolen engine metamethods (__index / __newindex) for Instance property access.
--      These skip Luau's property dispatch layer and call the C function directly.
--      If Roblox patches this, the wrappers fall back to normal access — nothing breaks.
--   2. Cached references to stdlib functions so every module uses upvalue access
--      instead of global table lookups in hot paths.

local Native = {}

-- ─── Metamethod Theft ────────────────────────────────────────────────────────

local function steal(thunk: () -> ()): ((...any) -> ...any)?
	local fn: ((...any) -> ...any)? = nil
	xpcall(thunk, function()
		fn = debug.info(2, "f") :: any
	end)
	return fn
end

local _rawGet = steal(function()
	return (game :: any).__NATIVE_ILLEGAL_READ__
end)

local _rawSet = steal(function()
	(game :: any).__NATIVE_ILLEGAL_WRITE__ = nil
end)

function Native.get(instance: Instance, property: string): any
	if _rawGet then
		return _rawGet(instance, property)
	end
	return (instance :: any)[property]
end

function Native.set(instance: Instance, property: string, value: any)
	if _rawSet then
		_rawSet(instance, property, value)
	else
		(instance :: any)[property] = value
	end
end

-- ─── Cached Engine Methods ────────────────────────────────────────────────────

Native.findFirstChild            = game.FindFirstChild
Native.findFirstChildOfClass     = game.FindFirstChildOfClass
Native.findFirstAncestorOfClass  = game.FindFirstAncestorOfClass
Native.waitForChild              = game.WaitForChild
Native.isA                       = game.IsA
Native.getChildren               = game.GetChildren
Native.getDescendants            = game.GetDescendants
Native.destroy                   = game.Destroy
Native.clone                     = game.Clone
Native.getAttribute              = game.GetAttribute
Native.setAttribute              = game.SetAttribute
Native.getPropertyChangedSignal  = game.GetPropertyChangedSignal

-- ─── Cached Lua Stdlib ────────────────────────────────────────────────────────

-- table
Native.tinsert  = table.insert
Native.tremove  = table.remove
Native.tcreate  = table.create
Native.tmove    = table.move
Native.tfind    = table.find
Native.tconcat  = table.concat
Native.tsort    = table.sort
Native.tunpack  = table.unpack
Native.tfreeze  = table.freeze
Native.tclear   = table.clear
Native.tclone   = table.clone

-- math
Native.floor    = math.floor
Native.ceil     = math.ceil
Native.abs      = math.abs
Native.max      = math.max
Native.min      = math.min
Native.sqrt     = math.sqrt
Native.log      = math.log
Native.sin      = math.sin
Native.cos      = math.cos
Native.atan2    = math.atan2
Native.random   = math.random
Native.huge     = math.huge
Native.pi       = math.pi
Native.clamp    = math.clamp
Native.round    = math.round

-- bit32
Native.band     = bit32.band
Native.bor      = bit32.bor
Native.bxor     = bit32.bxor
Native.bnot     = bit32.bnot
Native.lshift   = bit32.lshift
Native.rshift   = bit32.rshift
Native.arshift  = bit32.arshift
Native.btest    = bit32.btest
Native.countlz  = bit32.countlz
Native.countrz  = bit32.countrz

-- string
Native.format   = string.format
Native.find     = string.find
Native.match    = string.match
Native.gmatch   = string.gmatch
Native.gsub     = string.gsub
Native.sub      = string.sub
Native.rep      = string.rep
Native.reverse  = string.reverse
Native.upper    = string.upper
Native.lower    = string.lower
Native.byte     = string.byte
Native.char     = string.char
Native.split    = string.split

-- buffer
Native.bcreate      = buffer.create
Native.bwritef32    = buffer.writef32
Native.breadf32     = buffer.readf32
Native.bwritef64    = buffer.writef64
Native.breadf64     = buffer.readf64
Native.bwriteu8     = buffer.writeu8
Native.breadu8      = buffer.readu8
Native.bwriteu16    = buffer.writeu16
Native.breadu16     = buffer.readu16
Native.bwriteu32    = buffer.writeu32
Native.breadu32     = buffer.readu32
Native.bwritei8     = buffer.writei8
Native.breadi8      = buffer.readi8
Native.bwritei16    = buffer.writei16
Native.breadi16     = buffer.readi16
Native.bwritei32    = buffer.writei32
Native.breadi32     = buffer.readi32
Native.bwritestring = buffer.writestring
Native.breadstring  = buffer.readstring
Native.blen         = buffer.len
Native.bfill        = buffer.fill
Native.bcopy        = buffer.copy

-- os / timing
Native.clock    = os.clock
Native.time     = os.time
Native.date     = os.date

-- task
Native.spawn    = task.spawn
Native.defer    = task.defer
Native.delay    = task.delay
Native.wait     = task.wait
Native.cancel   = task.cancel

-- pcall

Native.pcall = pcall

Native.type = type
Native.typeof = typeof

Native.tostring = tostring
Native.tonnumber = tonumber

return table.freeze(Native)