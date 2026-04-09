--!strict
--!native

local tinsert = table.insert
local tremove = table.remove
local tcreate = table.create
local tmove   = table.move
local tsort   = table.sort
local tclone  = table.clone
local tfind   = table.find
local tfreeze = table.freeze
local random  = math.random
local floor   = math.floor

local TableUtil = {}

export type Predicate<T> = (value: T, index: number) -> boolean
export type Mapper<T, U> = (value: T, index: number) -> U
export type Reducer<T, U> = (accumulator: U, value: T, index: number) -> U
export type Comparator<T> = (a: T, b: T) -> boolean

-- ─── Copy / Merge ─────────────────────────────────────────────────────────────

function TableUtil.deepCopy<T>(source: T): T
	if type(source) ~= "table" then
		return source
	end
	local copy = {} :: any
	for k, v in source :: any do
		copy[TableUtil.deepCopy(k)] = TableUtil.deepCopy(v)
	end
	return setmetatable(copy, getmetatable(source :: any)) :: T
end

function TableUtil.shallowCopy<T>(source: { T }): { T }
	return tclone(source :: any) :: any
end

function TableUtil.freeze<T>(source: { T }): { T }
	return tfreeze(TableUtil.deepCopy(source)) :: any
end

function TableUtil.deepMerge(target: { [any]: any }, source: { [any]: any }): { [any]: any }
	local result = TableUtil.deepCopy(target)
	for k, v in source do
		if type(v) == "table" and type(result[k]) == "table" then
			result[k] = TableUtil.deepMerge(result[k], v)
		else
			result[k] = TableUtil.deepCopy(v)
		end
	end
	return result
end

function TableUtil.reconcile(target: { [string]: any }, template: { [string]: any }): { [string]: any }
	local result = TableUtil.deepCopy(target)
	for k, v in template do
		if result[k] == nil then
			result[k] = TableUtil.deepCopy(v)
		elseif type(result[k]) == "table" and type(v) == "table" then
			result[k] = TableUtil.reconcile(result[k], v)
		end
	end
	return result
end

-- ─── Predicates ───────────────────────────────────────────────────────────────

function TableUtil.isEmpty(t: { [any]: any }): boolean
	return next(t) == nil
end

function TableUtil.length(t: { [any]: any }): number
	local n = 0
	for _ in t do n += 1 end
	return n
end

function TableUtil.contains<T>(t: { T }, target: T): boolean
	return tfind(t, target) ~= nil
end

function TableUtil.indexOf<T>(t: { T }, target: T): number?
	return tfind(t, target)
end

function TableUtil.every<T>(t: { T }, pred: Predicate<T>): boolean
	for i, v in t do
		if not pred(v, i) then return false end
	end
	return true
end

function TableUtil.some<T>(t: { T }, pred: Predicate<T>): boolean
	for i, v in t do
		if pred(v, i) then return true end
	end
	return false
end

function TableUtil.none<T>(t: { T }, pred: Predicate<T>): boolean
	for i, v in t do
		if pred(v, i) then return false end
	end
	return true
end

-- ─── Search ───────────────────────────────────────────────────────────────────

function TableUtil.find<T>(t: { T }, pred: Predicate<T>): T?
	for i, v in t do
		if pred(v, i) then return v end
	end
	return nil
end

function TableUtil.findIndex<T>(t: { T }, pred: Predicate<T>): number?
	for i, v in t do
		if pred(v, i) then return i end
	end
	return nil
end

-- ─── Key / Value ──────────────────────────────────────────────────────────────

function TableUtil.keys<K>(t: { [K]: any }): { K }
	local n = 0
	for _ in t do n += 1 end
	local result: { K } = tcreate(n)
	local i = 0
	for k in t do
		i += 1
		result[i] = k
	end
	return result
end

function TableUtil.values<V>(t: { [any]: V }): { V }
	local n = 0
	for _ in t do n += 1 end
	local result: { V } = tcreate(n)
	local i = 0
	for _, v in t do
		i += 1
		result[i] = v
	end
	return result
end

-- ─── Transform ────────────────────────────────────────────────────────────────

function TableUtil.filter<T>(t: { T }, pred: Predicate<T>): { T }
	local result: { T } = tcreate(#t)
	local n = 0
	for i, v in t do
		if pred(v, i) then
			n += 1
			result[n] = v
		end
	end
	return result
end

function TableUtil.map<T, U>(t: { T }, fn: Mapper<T, U>): { U }
	local result: { U } = tcreate(#t)
	for i, v in t do
		result[i] = fn(v, i)
	end
	return result
end

function TableUtil.reduce<T, U>(t: { T }, fn: Reducer<T, U>, initial: U): U
	local acc = initial
	for i, v in t do
		acc = fn(acc, v, i)
	end
	return acc
end

function TableUtil.flatten<T>(t: { { T } | T }): { T }
	local result: { T } = tcreate(#t * 2)
	local n = 0
	for _, v in t do
		if type(v) == "table" then
			for _, inner in v :: any do
				n += 1
				result[n] = inner
			end
		else
			n += 1
			result[n] = v :: T
		end
	end
	return result
end

function TableUtil.unique<T>(t: { T }): { T }
	local seen: { [any]: boolean } = {}
	local result: { T } = tcreate(#t)
	local n = 0
	for _, v in t do
		if not seen[v :: any] then
			seen[v :: any] = true
			n += 1
			result[n] = v
		end
	end
	return result
end

function TableUtil.partition<T>(t: { T }, pred: Predicate<T>): ({ T }, { T })
	local half = floor(#t / 2)
	local pass: { T } = tcreate(half)
	local fail: { T } = tcreate(half)
	local np, nf = 0, 0
	for i, v in t do
		if pred(v, i) then
			np += 1
			pass[np] = v
		else
			nf += 1
			fail[nf] = v
		end
	end
	return pass, fail
end

function TableUtil.groupBy<T, K>(t: { T }, keyFn: (value: T) -> K): { [K]: { T } }
	local result: { [K]: { T } } = {} :: any
	for _, v in t do
		local k = keyFn(v)
		local group = (result :: any)[k]
		if group == nil then
			group = tcreate(4)
			;(result :: any)[k] = group
		end
		tinsert(group, v)
	end
	return result
end

function TableUtil.countBy<T, K>(t: { T }, keyFn: (value: T) -> K): { [K]: number }
	local result: { [K]: number } = {} :: any
	for _, v in t do
		local k = keyFn(v)
		;(result :: any)[k] = ((result :: any)[k] or 0) + 1
	end
	return result
end

-- ─── Order / Slice ────────────────────────────────────────────────────────────

function TableUtil.reverse<T>(t: { T }): { T }
	local n = #t
	local result: { T } = tcreate(n)
	for i = 1, n do
		result[i] = t[n - i + 1]
	end
	return result
end

function TableUtil.reverseInPlace<T>(t: { T }): { T }
	local n = #t
	for i = 1, floor(n / 2) do
		t[i], t[n - i + 1] = t[n - i + 1], t[i]
	end
	return t
end

function TableUtil.shuffle<T>(t: { T }): { T }
	local result = tclone(t :: any) :: { T }
	for i = #result, 2, -1 do
		local j = random(i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

function TableUtil.shuffleInPlace<T>(t: { T }): { T }
	for i = #t, 2, -1 do
		local j = random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

function TableUtil.sort<T>(t: { T }, cmp: Comparator<T>?): { T }
	local result = tclone(t :: any) :: { T }
	tsort(result, cmp :: any)
	return result
end

function TableUtil.sortInPlace<T>(t: { T }, cmp: Comparator<T>?): { T }
	tsort(t, cmp :: any)
	return t
end

function TableUtil.take<T>(t: { T }, n: number): { T }
	local len = math.min(n, #t)
	local result: { T } = tcreate(len)
	tmove(t, 1, len, 1, result)
	return result
end

function TableUtil.drop<T>(t: { T }, n: number): { T }
	local len = #t
	if n >= len then return tcreate(0) end
	local result: { T } = tcreate(len - n)
	tmove(t, n + 1, len, 1, result)
	return result
end

function TableUtil.chunk<T>(t: { T }, size: number): { { T } }
	assert(size > 0, "chunk size must be > 0")
	local n = #t
	local numChunks = math.ceil(n / size)
	local result: { { T } } = tcreate(numChunks)
	for i = 0, numChunks - 1 do
		local from = i * size + 1
		local to   = math.min(from + size - 1, n)
		local chunk: { T } = tcreate(to - from + 1)
		tmove(t, from, to, 1, chunk)
		result[i + 1] = chunk
	end
	return result
end

function TableUtil.zip<T, U>(a: { T }, b: { U }): { { T | U } }
	local n = math.min(#a, #b)
	local result: { { T | U } } = tcreate(n)
	for i = 1, n do
		result[i] = { a[i], b[i] }
	end
	return result
end

function TableUtil.first<T>(t: { T }): T?  return t[1]   end
function TableUtil.last<T>(t: { T }): T?   return t[#t]  end

-- ─── Set Operations ───────────────────────────────────────────────────────────

function TableUtil.omit<K, V>(t: { [K]: V }, keys: { K }): { [K]: V }
	local drop: { [any]: boolean } = {}
	for _, k in keys do drop[k :: any] = true end
	local result: { [K]: V } = {}
	for k, v in t do
		if not drop[k :: any] then
			(result :: any)[k] = v
		end
	end
	return result
end

function TableUtil.pick<K, V>(t: { [K]: V }, keys: { K }): { [K]: V }
	local result: { [K]: V } = {}
	for _, k in keys do
		local v = (t :: any)[k]
		if v ~= nil then
			(result :: any)[k] = v
		end
	end
	return result
end

function TableUtil.difference<T>(a: { T }, b: { T }): { T }
	local bSet: { [any]: boolean } = {}
	for _, v in b do bSet[v :: any] = true end
	local result: { T } = tcreate(#a)
	local n = 0
	for _, v in a do
		if not bSet[v :: any] then
			n += 1
			result[n] = v
		end
	end
	return result
end

function TableUtil.intersection<T>(a: { T }, b: { T }): { T }
	local bSet: { [any]: boolean } = {}
	for _, v in b do bSet[v :: any] = true end
	local result: { T } = tcreate(math.min(#a, #b))
	local n = 0
	for _, v in a do
		if bSet[v :: any] then
			n += 1
			result[n] = v
		end
	end
	return result
end

function TableUtil.union<T>(a: { T }, b: { T }): { T }
	local seen: { [any]: boolean } = {}
	local result: { T } = tcreate(#a + #b)
	local n = 0
	for _, v in a do
		if not seen[v :: any] then
			seen[v :: any] = true
			n += 1
			result[n] = v
		end
	end
	for _, v in b do
		if not seen[v :: any] then
			seen[v :: any] = true
			n += 1
			result[n] = v
		end
	end
	return result
end

-- ─── Numeric Aggregates ───────────────────────────────────────────────────────

function TableUtil.sum(t: { number }): number
	local s = 0
	for _, v in t do s += v end
	return s
end

function TableUtil.min(t: { number }): number?
	if #t == 0 then return nil end
	local m = t[1]
	for i = 2, #t do if t[i] < m then m = t[i] end end
	return m
end

function TableUtil.max(t: { number }): number?
	if #t == 0 then return nil end
	local m = t[1]
	for i = 2, #t do if t[i] > m then m = t[i] end end
	return m
end

function TableUtil.average(t: { number }): number?
	if #t == 0 then return nil end
	local s = 0
	for _, v in t do s += v end
	return s / #t
end

function TableUtil.minMax(t: { number }): (number?, number?)
	if #t == 0 then return nil, nil end
	local lo, hi = t[1], t[1]
	for i = 2, #t do
		local v = t[i]
		if v < lo then lo = v end
		if v > hi then hi = v end
	end
	return lo, hi
end

function TableUtil.weightedRandom<T>(items: { T }, weights: { number }): T?
	assert(#items == #weights, "items and weights must be same length")
	assert(#items > 0, "table must not be empty")
	local total = 0
	for _, w in weights do total += w end
	local roll = random() * total
	local cum = 0
	for i, w in weights do
		cum += w
		if roll <= cum then return items[i] end
	end
	return items[#items]
end

return table.freeze(TableUtil)