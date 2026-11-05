-- Loads Roblox-style ModuleScripts from src/ in Lune.
-- Gives each module a fake `script` whose children map onto the folder layout Rojo uses,
-- so `require(script.Parent.Judge)` works unchanged outside Roblox.
--
-- Lune's fs calls can yield, and yielding inside a metamethod is not allowed, so the whole
-- src/ tree is read once up front and lookups after that are plain table reads.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ROOT = "src"

local sources: { [string]: string } = {} -- file path -> source
local dirs: { [string]: boolean } = {}

local function scan(dir: string)
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		elseif string.match(name, "%.luau$") then
			sources[path] = fs.readFile(path)
		end
	end
end
scan(ROOT)

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or "."
end

local function moduleFile(path: string): string?
	if sources[path .. ".luau"] then
		return path .. ".luau"
	end
	if dirs[path] and sources[path .. "/init.luau"] then
		return path .. "/init.luau"
	end
	return nil
end

local cache: { [string]: any } = {}
local nodes: { [string]: any } = {}
local node

local function requireNode(n: any): any
	local path = rawget(n, "__path")
	local file = moduleFile(path)
	assert(file, "not a module: " .. path)
	if cache[file] == nil then
		local isInit = string.match(file, "/init%.luau$") ~= nil
		local fn = luau.load(sources[file], {
			debugName = file,
			environment = { script = if isInit then node(dirname(file)) else n, require = requireNode },
		})
		cache[file] = fn()
	end
	return cache[file]
end

function node(path: string): any
	if nodes[path] then
		return nodes[path]
	end
	local n = setmetatable({ __path = path }, {
		__index = function(self, key)
			local own = rawget(self, "__path")
			if key == "Parent" then
				return node(dirname(own))
			end
			local child = own .. "/" .. key
			assert(moduleFile(child) or dirs[child], `{key} is not a child of {own}`)
			return node(child)
		end,
	})
	nodes[path] = n
	return n
end

local loader = {}

-- loader.require("src/shared/RhythmEngine") -> the module's return value
function loader.require(path: string): any
	return requireNode(node(path))
end

return loader
