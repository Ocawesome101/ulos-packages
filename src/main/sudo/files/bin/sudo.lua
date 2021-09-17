-- sudo v2 --

local sudo = require("sudo")
local users = require("users")

local args, opts = require("argutil").getopt({
  allow_finish = true,
  finish_after_arg = true,
  options = {
    u = true, user = true,
    help = true
  }
}, ...)

if #args == 0 or opts.help then
  io.stderr:write([[
usage: sudo [options] COMMAND
Execute a command as another user.  Requires the
'sudo' service to be running.
  --help          Print this help text.
  -u,--user USER  Execute COMMAND as USER rather
                  than root.

Sudo implementation (c) 2021 Ocawesome101 under
the DSLv2.
]])
  os.exit(opts.help and 0 or 1)
end

opts.user = opts.user or opts.u or "root"
local user, err = users.get_uid(opts.user)

if not user then
  io.stderr:write("sudo: user ", opts.user, ": ", err, "\n")
  os.exit(1)
end

local ok, err = sudo.request(user, table.concat(args, " "))
if not ok then
  io.stderr:write("sudo: request failed: ", err, "\n")
  os.exit(2)
end
