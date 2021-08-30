-- at long last, a mv command --

local args = table.pack(...)
local args, opts = require("argutil").parse(...)

if #args < 2 or opts.help then
  io.stderr:write([[
usage: mv FILE ... DEST
Move FILEs to DEST.  Executes cp(1), then rm(1)
under the hood.

ULOS Coreutils copyright (c) 2021 Ocawesome101
under the DSLv2.
]])
  os.exit(1)
end

local cp = loadfile("/bin/cp.lua")
cp("-r", table.unpack(args))
local rm = loadfile("/bin/rm.lua")
rm("-r", table.unpack(args, 1, #args - 1))
