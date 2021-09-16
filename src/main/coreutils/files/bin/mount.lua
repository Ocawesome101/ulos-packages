-- coreutils: mount --

local component = require("component")
local filesystem = require("filesystem")

local args, opts = require("argutil").parse(...)

local function readFile(f)
  local handle, err = io.open(f, "r")
  if not handle then
    io.stderr:write("mount: cannot open ", f, ": ", err, "\n")
    os.exit(1)
  end
  local data = handle:read("a")
  handle:close()

  return data
end

if opts.help then
  io.stderr:write([[
usage: mount NODE LOCATION [FSTYPE]
   or: mount -u PATH
Mount the filesystem node NODE at LOCATION.  Or,
if -u is specified, unmount the filesystem node
at PATH.

If FSTYPE is either "overlay" or unset, NODE will
be mounted as an overlay at LOCATION.  Otherwise,
if NODE points to a filesystem in /sys/dev, mount
will try to read device information from the file.
If both of these cases fail, NODE will be treated
as a component address.

Options:
  -u  Unmount rather than mount.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

if #args == 0 then
  for line in io.lines("/sys/mounts", "l") do
    local path, thing = line:match("(.-): (.+)")
    if not thing:match("........%-....%-....%-....%-............") then
      thing = string.format("%q", thing)
    end
    if path and thing then
      print(string.format("%s on %s", thing, path))
    end
  end
  os.exit(0)
end

if opts.u then
  local ok, err = filesystem.umount(require("path").canonical(args[1]))
  if not ok then
    io.stderr:write("mount: unmounting ", args[1], ": ", err, "\n")
    os.exit(1)
  end
  os.exit(0)
end

local node, path, fstype = args[1], args[2], args[3]

do
  local npath = require("path").canonical(node)
  local data = filesystem.stat(npath)
  if data then
    if npath:match("/sys/") then -- the path points to somewhere the sysfs
      if data.isDirectory then
        node = readFile(npath .. "/address")
      else
        node = readFile(npath)
      end
    elseif not data.isDirectory then
      node = readFile(npath)
    end
  end
end

if not fstype then
  local addr = component.get(node)
  if addr then
    node = addr
    if component.type(addr) == "drive" then
      fstype = "raw"
    elseif component.type(addr) == "filesystem" then
      fstype = "node"
    else
      io.stderr:write("mount: ", node, ": not a filesystem or drive\n")
      os.exit(1)
    end
  end
end

if (not fstype) or fstype == "overlay" then
  local abs = require("path").canonical(node)
  local data, err = filesystem.stat(abs)
  if not data then
    io.stderr:write("mount: ", node, ": ", err, "\n")
    os.exit(1)
  end
  if not data.isDirectory then
    io.stderr:write("mount: ", node, ": not a directory\n")
    os.exit(1)
  end
  node = abs
  fstype = "overlay"
end

if not filesystem.types[fstype:upper()] then
  io.stderr:write("mount: ", fstype, ": bad filesystem node type\n")
  os.exit(1)
end

local ok, err = filesystem.mount(node, filesystem.types[fstype:upper()], path)

if not ok then
  io.stderr:write("mount: mounting ", node, " on ", path, ": ", err, "\n")
  os.exit(1)
end
