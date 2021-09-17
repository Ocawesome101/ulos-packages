-- "sudo" library --

local usysd = require("usysd")
local process = require("process")

local lib = {}
local requests = {}

local function is_running()
  local running = usysd.list(false, true)
  for i=1, #running, 1 do
    if running[i] == "sudo" then
      return true
    end
  end
  return false
end

function lib.requests()
  if process.info().owner ~= 0 then
    error("permission denied", 0)
  end
  return requests
end

function lib.request(user, cmd)
  checkArg(1, user, "number")
  checkArg(2, cmd, "string")
  local n = #requests + 1
  if not is_running() then
    return nil, "sudo service is not running"
  end
  requests[n] = {from_name = os.getenv("USER"),
    from = process.info().owner, user = user, cmd = cmd, stderr = io.stderr}
  while type(requests[n]) == "table" do coroutine.yield(0) end
  return table.remove(requests, n)
end

return package.protect(lib)
