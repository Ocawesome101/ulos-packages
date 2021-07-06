-- coreutils: touch --

local path = require("path")
local ftypes = require("filetypes")
local filesystem = require("filesystem")

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help then
  io.stderr:write([[
usage: touch FILE ...
Create the specified FILE(s) if they do not exist.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

for i=1, #args, 1 do
  local ok, err = filesystem.touch(path.canonical(args[i]),
    ftypes.file)

  if not ok then
    io.stderr:write("touch: cannot touch '", args[i], "': ", err, "\n")
    os.exit(1)
  end
end
