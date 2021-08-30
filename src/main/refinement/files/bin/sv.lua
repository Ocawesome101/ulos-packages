-- sv: service management --

local sv = require("sv")
local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help or (args[1] ~= "list" and #args < 2) then
  io.stderr:write([[
usage: sv [up|down|enable|disable] service
   or: sv add [script|service] name file
   or: sv del service
   or: sv list
Manage services through the Refinement API.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local verb = args[1]

if not sv[verb] then
  io.stderr:write("bad command verb '", verb, "'\n")
  os.exit(1)
end

if verb == "list" then
  local r = sv.list()
  print("ENABLED  ACTIVE  TYPE   NAME")
  for k,v in pairs(r) do
    print(string.format("%7s  %6s  %6s %s", tostring(v.isEnabled),
      tostring(v.isRunning), v.type or "N/A", k))
  end
else
  local ok, err = sv[verb](table.unpack(args, 2, #args))
  if not ok then
    io.stderr:write("sv: ", verb, ": ", err, "\n")
    os.exit(1)
  end
end
