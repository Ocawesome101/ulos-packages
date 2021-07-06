-- df --

local path = require("path")
local size = require("size")
local filesystem = require("filesystem")

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: df [-h]
Print information about attached filesystems.
Uses information from the sysfs.

Options:
  -h  Print sizes in human-readable form.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local fscpath = "/sys/components/by-type/filesystem/"
local files = filesystem.list(fscpath)

table.sort(files)

print("      fs     name    total     used     free")

local function readFile(f)
  local handle = assert(io.open(f, "r"))
  local data = handle:read("a")
  handle:close()

  return data
end

local function printInfo(fs)
  local addr = readFile(fs.."/address"):sub(1, 8)
  local name = readFile(fs.."/label")
  local used = tonumber(readFile(fs.."/spaceUsed"))
  local total = tonumber(readFile(fs.."/spaceTotal"))

  local free = total - used

  if opts.h then
    used = size.format(used)
    free = size.format(free)
    total = size.format(total)
  end

  print(string.format("%8s %8s %8s %8s %8s", addr, name, total, used, free))
end

for i, file in ipairs(files) do
  printInfo(path.concat(fscpath, file))
end
