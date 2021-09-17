-- getty: dynamically manage login services for TTYs --
-- only works with USysD

local usysd = require("usysd")
local fs = require("filesystem")

while true do
  local running = usysd.list(true)
  local ttys = {}
  do
    local f = fs.list("/sys/dev/")
    for i, F in ipairs(f) do
      if F:match("tty(%d+)") then
        ttys[#ttys + 1] = tonumber(F:match("tty(%d+)"))
      end
    end
    table.sort(ttys)
  end

  for i, tty in ipairs(ttys) do
    local is_running = false
    for i, svc in ipairs(running) do
      if svc:match("@tty"..tty.."$") then
        is_running = true
      end
    end
    if not is_running then
      usysd.start("login@tty" .. tty)
    end
  end
  os.sleep(5)
  running = usysd.list(false, true)
end
