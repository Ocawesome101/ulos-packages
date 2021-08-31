-- ussyd service management --

local usysd = require("usysd")
local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help or (args[1] ~= "list" and #args < 2) then
  io.stderr:write([[
usage: usysd <start|stop> SERVICE[@ttyN]
   or: usysd <enable|disable> [--now] SERVICE[@ttyN]
   or: usysd list [--enabled]

Manages services under USysD.

USysD copyright (c) 2021 Ocawesome101 under the
DSLv2.
]])
end

local cmd, svc = args[1], args[2]
if cmd == "list" then
  local services, err = usysd.list(opts.enabled, opts.running)
  print(table.concat(services, "\n"))
elseif cmd == "enable" then
  local ok, err = usysd.enable(svc)
  if not ok then io.stderr:write(err, "\n") os.exit(1) end
  if opts.now then usysd.start(svc) end
elseif cmd == "disable" then
  local ok, err = usysd.disable(svc)
  if not ok then io.stderr:write(err, "\n") os.exit(1) end
  if opts.now then usysd.stop(svc) end
elseif cmd == "start" or cmd == "stop" then
  local ok = usysd[cmd](svc)
  if not ok then os.exit(1) end
end
