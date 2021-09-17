-- "sudo" service --

local users = require("users")
local computer = require("computer")

if os.getenv("USER") ~= "root" then
  error("must be run as root", 0)
end

local requests = require("sudo").requests()

local cred_cache = {}

while true do
  coroutine.yield()
  for i, req in ipairs(requests) do
    local crid = string.format("%d:%d", req.from, req.stderr.tty)
    if (not cred_cache[crid]) or computer.uptime() - cred_cache[crid] > 300 then
      local tries = 0
      local auth
      repeat
        tries = tries + 1
        req.stderr:write("[sudo] password for " .. req.from_name .. ": \27[8m")
        local ln = req.stderr:read("l")
        req.stderr:write("\27[28m\n")
        auth = users.authenticate(req.from, ln)
        if auth then
          cred_cache[crid] = computer.uptime()
        else
          req.stderr:write("Sorry, try again.\n")
        end
      until tries == 3 or auth
      if not auth then
        req.stderr:write("Authentication failed.\n")
        requests[i] = false
      end
    end
    cred_cache[crid] = computer.uptime()
    local ok, err = users.exec_as(req.user, "", function()
      return os.execute(req.cmd)
    end, "<sudo executor>", true)
    if not ok then
      io.stderr:write(err, "\n")
    end
    requests[i] = true
  end
end
