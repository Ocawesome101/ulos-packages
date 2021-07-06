-- LuaFileSystem compatibility layer --

local fs = require("filesystem")
local path = require("path")

local lfs = {}

function lfs.attributes(file, optional)
  checkArg(1, file, "string")
  checkArg(2, optional, "string", "table", "nil")
  file = path.canonical(file)

  local out = {}
  if type(optional) == "table" then out = optional end

  local data, err = fs.stat(file)
  if not data then return nil, err end

  out.dev = 0
  out.ino = 0
  out.mode = (data.isDirectory and "directory") or "file"
  out.uid = data.owner
  out.gid = data.group
  out.rdev = 0
  out.access = data.lastModified
  out.modification = data.lastModified
  out.change = data.lastModified
  out.size = data.size
  out.permissions = "rwxrwxrwx" -- TODO do this properly!!
  out.blksize = 0

  if type(optional) == "string" then
    return out[optional]
  end

  return out
end

function lfs.chdir(dir)
  dir = path.canonical(dir)
  if not fs.stat(dir) then
    return nil, "no such file or directory"
  end
  os.setenv("PWD", dir)
  return true
end

function lfs.lock_dir() end

function lfs.currentdir()
  return os.getenv("PWD")
end

function lfs.dir(dir)
  dir = path.canonical(dir)
  local files, err = fs.list(dir)
  if not files then return nil, err end
  local i = 0
  return function()
    i = i + 1
    return files[i]
  end
end

function lfs.lock() end

function lfs.link() end

function lfs.mkdir(dir)
  dir = path.canonical(dir)
  local ok, err = fs.touch(dir, 2)
  if not ok then return nil, err end
  return true
end

function lfs.rmdir(dir)
  dir = path.canonical(dir)
  local ok, err = fs.remove(dir)
  if not ok then return nil, err end
  return true
end

function lfs.setmode() return "binary" end

lfs.symlinkattributes = lfs.attributes

function lfs.touch(f)
  f = path.canonical(f)
  return fs.touch(f)
end

function lfs.unlock() end

return lfs
