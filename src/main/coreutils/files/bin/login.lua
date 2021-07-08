-- coreutils: login

local users = require("users")
local process = require("process")
local readline = require("readline")

local gethostname = (package.loaded.network and package.loaded.network.hostname)
  or function() return "localhost" end

if (process.info().owner or 0) ~= 0 then
  io.stderr:write("login may only be run as root!\n")
  os.exit(1)
end

io.write("\27?0c\27[39;49m\nWelcome to ULOS.\n\n")

local function main()
  io.write("\27?0c", gethostname(), " login: ")
  local un = readline()
  io.write("password: \27[8m")
  local pw = io.read("l")
  io.write("\n\27[m\27?0c")
  local uid = users.get_uid(un)
  if not uid then
    io.write("no such user\n\n")
  else
    local ok, err = users.authenticate(uid, pw)
    if not ok then
      io.write(err, "\n\n")
    else
      local info = users.attributes(uid)
      local shell = info.shell or "/bin/sh"
      if not shell:match("%.lua$") then
        shell = string.format("%s.lua", shell)
      end
      local shellf, sherr = loadfile(shell)
      if not shellf then
        io.write("failed loading shell: ", sherr, "\n\n")
      else
        io.write("\n")

        local motd = io.open("/etc/motd.txt", "r")
        if motd then
          print((motd:read("a") or ""))
          motd:close()
        end

        local exit, err = users.exec_as(uid, pw, shellf, shell, true)
        if exit ~= 0 then
          print(err)
        end
      end
    end
  end
end

while true do
  local ok, err = xpcall(main, debug.traceback)
  if not ok then
    io.stderr:write(err, "\n")
  end
end
