-- make io sensible about paths

local path = require("path")

local function wrap(f)
  return function(p, ...)
    if type(p) == "string" then p = path.canonical(p) end
    return f(p, ...)
  end
end

io.open = wrap(io.open)
io.input = wrap(io.input)
io.output = wrap(io.output)
io.lines = wrap(io.lines)
