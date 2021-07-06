-- find --

local path = require("path")
local futil = require("futil")

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: find DIRECTORY ...
Print a tree of all files in DIRECTORY.  All
printed file paths are absolute.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
end

for i=1, #args, 1 do
  local tree, err = futil.tree(path.canonical(args[i]))
  
  if not tree then
    io.stderr:write("find: ", err, "\n")
    os.exit(1)
  end

  for i=1, #tree, 1 do
    io.write(tree[i], "\n")
    if i % 10 == 0 then coroutine.yield(0) end
  end
end
