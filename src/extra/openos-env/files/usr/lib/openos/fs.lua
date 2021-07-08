local fs = require("filesystem")
local ft = require("filetypes")
local path = require("path")

local lib = {}

function lib.path(p)
  local seg = path.split(p)
  return table.concat(seg, " ", 1, #seg - 1)
end

function lib.name(p)
  local seg = path.split(p)
  return seg[#seg]
end

function lib.exists(p)
  return not not fs.stat(path.canonical(p))
end

function lib.isDirectory(p)
  local s, e = fs.stat(path.canonical(p))
  if not s then return s, e end
  return s and s.isDirectory
end

function lib.makeDirectory(p)
  return fs.touch(path.canonical(p), ft)
end

function lib.get() return {isReadOnly = function() return true end} end

function lib.copy(a, b)
  local i, ie = io.open(a, "r")
  if not i then return nil, ie end
  local o, oe = io.open(b, "w")
  if not o then i:close() return nil, oe end
  o:write(i:read("a"))
  i:close()
  o:close()
  return true
end

function lib.remove(p)
  return fs.remove(path.canonical(p))
end

return lib
