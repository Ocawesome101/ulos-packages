-- coreutils: hostname --

local network = require("network")

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: hostname
   or: hostname NAME
If NAME is specified, tries to set the system
hostname to NAME; otherwise, prints the current
system hostname.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

if #args == 0 then
  print(network.hostname())
else
  local ok, err = network.sethostname(args[1])
  if not ok then
    io.stderr:write("hostname: sethostname: ", err)
    os.exit(1)
  end
end
