-- sv: service management --

local sv = require("sv")
local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help or (args[1] ~= "list" and #args < 2) then
  io.stderr:write([[
usage: sv [up|down] service
   or: sv list
Manage running services.

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
  for k,v in pairs(r) do
    print(k)
  end
else
  local ok, err = sv[verb](args[2])
  if not ok then
    io.stderr:write("sv: ", verb, ": ", err, "\n")
    os.exit(1)
  end
end
