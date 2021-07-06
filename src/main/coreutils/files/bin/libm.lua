-- preload: preload libraries

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.h or opts.help then
  io.stderr:write([[
usage: libm [-vr] LIB1 LIB2 ...
Loads or unloads libraries.  Internally uses
require().
    -v    be verbose
    -r    unload libraries rather than loading
          them

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
end

local function handle(f, a)
  local ok, err = pcall(f, a)
  if not ok and err then
    io.stderr:write(err, "\n")
    os.exit(1)
  else
    return true
  end
end

for i=1, #args, 1 do
  if opts.v then
    io.write(opts.r and "unload" or "load", " ", args[i], "\n")
  end
  if opts.r then
    handle(function() package.loaded[args[i]] = nil end)
  else
    handle(require, args[i])
  end
end
