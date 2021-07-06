-- free --

local computer = require("computer")
local size = require("size")

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: free [-h]
Prints system memory usage information.

Options:
  -h  Print sizes human-readably.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local function pinfo()
  local total = computer.totalMemory()
  local free = computer.freeMemory()
  
  -- collect garbage
  for i=1, 10, 1 do
    coroutine.yield(0)
  end
  
  local garbage = free - computer.freeMemory()
  local used = total - computer.freeMemory()

  print(string.format(
"total:    %s\
used:     %s\
free:     %s",
    size.format(total, not opts.h),
    size.format(used, not opts.h),
    size.format(computer.freeMemory(), not opts.h)))
end

pinfo()
