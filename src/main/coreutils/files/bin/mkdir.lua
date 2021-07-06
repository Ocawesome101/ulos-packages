-- coreutils: mkdir --

local path = require("path")
local ftypes = require("filetypes")
local filesystem = require("filesystem")

local args, opts = require("argutil").parse(...)

if opts.help or #args == 0 then
  io.stderr:write([[
usage: mkdir [-p] DIRECTORY ...
Create the specified DIRECTORY(ies), if they do
not exist.

Options:
  -p  Do not exit if the file already exists;
      automatically create parent directories as
      necessary.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

for i=1, #args, 1 do
  local dir = path.canonical(args[i])
  local exists = not not filesystem.stat(dir)
  if exists and not opts.p then
    io.stderr:write("mkdir: ", args[i], ": file already exists\n")
    os.exit(1)
  elseif not exists then
    local seg = path.split(dir)
    local parent = path.clean(table.concat(seg, "/", 1, #seg - 1))
    if opts.p then
      local segments = path.split(parent)
      for n, segment in ipairs(segments) do
        local ok, err = filesystem.touch(path.canonical("/"..
          table.concat(segments, "/", 1, n)), ftypes.directory)
        if not ok and err then
          io.stderr:write("mkdir: cannot create directory '", args[i], ": ",
            err, "\n")
          --os.exit(2)
        end
      end
    end
    local ok, err = filesystem.touch(dir, ftypes.directory)
    if not ok and err then
      io.stderr:write("mkdir: cannot create directory '", args[i],
        "': ", err, "\n")
      os.exit(2)
    end
  end
end
