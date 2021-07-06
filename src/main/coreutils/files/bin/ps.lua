-- ps: format information from /proc --

local users = require("users")
local fs = require("filesystem")

local args, opts = require("argutil").parse(...)

local function read(f)
  local handle, err = io.open(f)
  if not handle then
    io.stderr:write("ps: cannot open ", f, ": ", err, "\n")
    os.exit(1)
  end
  local data = handle:read("a")
  handle:close()
  return tonumber(data) or data
end

if opts.help then
  io.stderr:write([[
usage: ps
Format process information from /sys/proc.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(0)
end

local procs = fs.list("/sys/proc")
table.sort(procs, function(a, b) return tonumber(a) < tonumber(b) end)

print("   PID  STATUS     TIME NAME")
for i=1, #procs, 1 do
  local base = string.format("/sys/proc/%d/",
    tonumber(procs[i]))
  local data = {
    name = read(base .. "name"),
    pid = tonumber(procs[i]),
    status = read(base .. "status"),
    owner = users.attributes(read(base .. "owner")).name,
    time = read(base .. "cputime")
  }

  print(string.format("%6d %8s %7s %s", data.pid, data.status,
    string.format("%.2f", data.time), data.name))
end
