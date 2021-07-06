-- futil: file transfer utilities --

local fs = require("filesystem")
local path = require("path")
local text = require("text")

local lib = {}

-- recursively traverse a directory, generating a tree of all filenames
function lib.tree(dir, modify, rootfs)
  checkArg(1, dir, "string")
  checkArg(2, modify, "table", "nil")
  checkArg(3, rootfs, "string", "nil")

  local abs = path.canonical(dir)
  local mounts = fs.mounts()
  local nrootfs = "/"

  for k, v in pairs(mounts) do
    if #nrootfs < #k then
      if abs:match("^"..text.escape(k)) then
        nrootfs = k
      end
    end
  end

  rootfs = rootfs or nrootfs
  
  -- TODO: make this smarter
  if rootfs ~= nrootfs then
    io.stderr:write("futil: not leaving origin filesystem\n")
    return modify or {}
  end
  
  local files, err = fs.list(abs)
  
  if not files then
    return nil, dir .. ": " .. err
  end

  table.sort(files)

  local ret = modify or {}
  for i=1, #files, 1 do
    local full = string.format("%s/%s", abs, files[i], rootfs)
    local info, err = fs.stat(full)
    
    if not info then
      return nil, full .. ": " .. err
    end

    ret[#ret + 1] = path.clean(string.format("%s/%s", dir, files[i]))
    
    if info.isDirectory then
      local _, err = lib.tree(string.format("%s/%s", dir, files[i]), ret, root)
      if not _ then
        return nil, err
      end
    end
  end

  return ret
end

return lib
