#!/usr/bin/env lua
-- apparently, LuaComp doesn't work under ULOS
-- I'll fix that later, but for now this will do

_G.env = setmetatable({}, {__index = function(t, k) return os.getenv(k) end})

local proc, handle

local dirs = {
  {"@%[%{(.+)%}%]", function(ex)
    return assert(load("return " .. ex, "=eval", "t", _G))()
  end},
  {"%-%-#include \"(.+)\"", function(f)
    return proc(f)
  end},
}

proc = function(f)
  io.write("\27[36m *\27[39m processing " .. f .. "\n")
  for line in io.lines(f) do
    for k, v in ipairs(dirs) do
      line = line:gsub(v[1], v[2])
    end
    handle:write(line .. "\n")
  end
end

local args = {...}

if #args < 2 then
  io.stderr:write([[
usage: proc IN OUT
Preprocesses files in a manner similar to LuaComp.

Much more primitive than LuaComp.
]])
  os.exit(1)
end

handle = assert(io.open(args[2], "w"))

proc(args[1])

handle:close()

io.write("\27[95m * \27[39mSuccess!\n")

os.exit(0)
