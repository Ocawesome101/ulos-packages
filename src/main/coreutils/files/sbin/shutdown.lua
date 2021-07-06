-- shutdown

local computer = require("computer")

local args, opts = require("argutil").parse(...)

-- don't do anything except broadcast shutdown (TODO)
if opts.k then
  io.stderr:write("shutdown: -k not implemented yet, exiting cleanly anyway\n")
  os.exit(0)
end

local function try(f, a)
  local ok, err = f(a)
  if not ok then
    io.stderr:write("shutdown: ", err, "\n")
    os.exit(1)
  end
end

-- reboot
if opts.r or opts.reboot then
  try(computer.shutdown, true)
end

-- halt
if opts.h or opts.halt then
  try(computer.shutdown, "halt")
end

-- just power off
if opts.p or opts.P or opts.poweroff then
  try(computer.shutdown)
end

io.stderr:write([[
usage: shutdown [options]
options:
  --poweroff, -P, -p  power off
  --reboot, -r        reboot
  --halt, -h          halt the system
  -k                  write wall message but do not shut down
]])

os.exit(1)
