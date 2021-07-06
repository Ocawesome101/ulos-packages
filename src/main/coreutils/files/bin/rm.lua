-- coreutils: rm --

local path = require("path")
local futil = require("futil")
local filesystem = require("filesystem")

local args, opts = require("argutil").parse(...)

if opts.help or #args == 0 then
  io.stderr:write([[
usage: rm [-rfv] FILE ...
   or: rm --help
Remove all FILE(s).

Options:
  -r      Recurse into directories.  Only
          necessary on some filesystems.
  -f      Ignore nonexistent files/directories.
  -v      Print the path of every file that is
          directly removed.
  --help  Print this help and exit.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local function exit(...)
  if not opts.f then
    io.stderr:write("rm: ", ...)
    os.exit(1)
  end
end

local function remove(file)
  local abs = path.canonical(file)
  local data, err = filesystem.stat(abs)

  if not data then
    exit("cannot delete '", file, "': ", err, "\n")
  end

  if data.isDirectory and opts.r then
    local files = futil.tree(abs)
    for i=#files, 1, -1 do
      remove(files[i])
    end
  end

  local ok, err = filesystem.remove(abs)
  if not ok then
    exit("cannot delete '", file, "': ", err, "\n")
  end

  if ok and opts.v then
    io.write("removed ", data.isDirectory and "directory " or "",
      "'", abs, "'\n")
  end
end

for i, file in ipairs(args) do remove(file) end
