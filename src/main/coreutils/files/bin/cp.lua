-- coreutils: cp --

local path = require("path")
local futil = require("futil")
local ftypes = require("filetypes")
local filesystem = require("filesystem")

local args, opts = require("argutil").parse(...)

if opts.help or #args < 2 then
  io.stderr:write([[
usage: cp [-rv] SOURCE ... DEST
Copy SOURCE(s) to DEST.

Options:
  -r  Recurse into directories.
  -v  Be verbose.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(2)
end

local function copy(src, dest)
  if opts.v then
    print(string.format("'%s' -> '%s'", src, dest))
  end

  local inhandle, err = io.open(src, "r")
  if not inhandle then
    return nil, src .. ": " .. err
  end

  local outhandle, err = io.open(dest, "w")
  if not outhandle then
    return nil, dest .. ": " .. err
  end

  repeat
    local data = inhandle:read(8192)
    if data then outhandle:write(data) end
  until not data

  inhandle:close()
  outhandle:close()

  return true
end

local function exit(...)
  io.stderr:write("cp: ", ...)
  os.exit(1)
end

local dest = path.canonical(table.remove(args, #args))

if #args > 1 then -- multiple sources, dest has to be a directory
  local dstat, err = filesystem.stat(dest)

  if dstat and (not dstat.isDirectory) then
    exit("cannot copy to '", dest, "': target is not a directory\n")
  end
end

local function cp(f)
  local file = path.canonical(f)
  
  local stat, err = filesystem.stat(file)
  if not stat then
    exit("cannot stat '", f, "': ", err, "\n")
  end

  if stat.isDirectory then
    if not opts.r then
      exit("cannot copy directory '", f, "'; use -r to recurse\n")
    end
    local tree = futil.tree(file)

    filesystem.touch(dest, ftypes.directory)

    for i=1, #tree, 1 do
      local abs = path.concat(dest, tree[i]:sub(#file + 1))
      local data = filesystem.stat(tree[i])
      if data.isDirectory then
        local ok, err = filesystem.touch(abs, ftypes.directory)
        if not ok then
          exit("cannot create directory ", abs, ": ", err, "\n")
        end
      else
        local ok, err = copy(tree[i], abs)
        if not ok then exit(err, "\n") end
      end
    end
  else
    local dst = dest
    if #args > 1 then
      local segments = path.split(file)
      dst = path.concat(dest, segments[#segments])
    end
    local ok, err = copy(file, dst)
    if not ok then exit(err, "\n") end
  end
end

for i=1, #args, 1 do cp(args[i]) end
