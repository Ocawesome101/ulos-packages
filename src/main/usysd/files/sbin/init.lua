-- USysD init system.  --
-- Copyright (c) 2021 Ocawesome101 under the DSLv2.

if package.loaded.usysd then
  io.stderr:write("\27[97m[ \27[91mFAIL \27[97m] USysD is already running!\n")
  os.exit(1)
end

local usd = {}

--  usysd versioning stuff --

usd._VERSION_MAJOR = 1
usd._VERSION_MINOR = 0
usd._VERSION_PATCH = 3
usd._RUNNING_ON = "unknown"

io.write(string.format("USysD version %d.%d.%d\n", usd._VERSION_MAJOR, usd._VERSION_MINOR,
  usd._VERSION_PATCH))

do
  local handle, err = io.open("/etc/os-release")
  if handle then
    local data = handle:read("a")
    handle:close()

    local name = data:match("PRETTY_NAME=\"(.-)\"")
    if name then usd._RUNNING_ON = name end
  end
end

io.write("\n  \27[97mWelcome to \27[96m" .. usd._RUNNING_ON .. "\27[97m!\27[37m\n\n")
--#include "src/version.lua"
-- logger stuff --

usd.statii = {
  ok = "\27[97m[\27[92m  OK  \27[97m] ",
  warn = "\27[97m[\27[93m WARN \27[97m] ",
  wait = "\27[97m[\27[93m WAIT \27[97m] ",
  fail = "\27[97m[\27[91m FAIL \27[97m] ",
}

function usd.log(...)
  io.write(...)
  io.write("\n")
end
--#include "src/logger.lua"
-- set the system hostname --

do
  local net = require("network")
  local handle, err = io.open("/etc/hostname", "r")
  if handle then
    local hostname = handle:read("a"):gsub("\n", "")
    handle:close()
    net.sethostname(hostname)
  end
  usd.log(usd.statii.ok, "hostname is \27[37m<\27[90m" .. net.hostname() .. "\27[37m>")
end
--#include "src/hostname.lua"
-- service API --

do
  usd.log(usd.statii.ok, "initializing service management")

  local config = require("config").bracket
  local fs = require("filesystem")
  local users = require("users")
  local process = require("process")

  local autostart = "/etc/usysd/autostart"
  local svc_dir = "/etc/usysd/services/"

  local api = {}
  local running = {}
  usd.running = running

  local starting = {}
  local ttys = {[0] = io.stderr}
  function api.start(name)
    checkArg(1, name, "string")
    if running[name] or starting[name] then return true end

    local full_name = name
    local tty = io.stderr.tty
    do
      local _name, _tty = name:match("(.+)@tty(%d+)")
      name = _name or name
      tty = tonumber(_tty) or tty
      if not ttys[tty] then
        local hnd, err = io.open("/sys/dev/tty" .. tty)
        if not hnd then
          usd.log(usd.statii.fail, "cannot open tty", tty, ": ", err)
          return nil
        end
        ttys[tty] = hnd
        hnd.tty = tty
      end
    end
    
    usd.log(usd.statii.wait, "starting service ", name)
    local cfg = config:load(svc_dir .. name)
    
    if not cfg then
      usd.log("\27[A\27[G\27[2K", usd.statii.fail, "service ", name, " not found!")
      return nil
    end
    
    if not (cfg["usysd-service"] and cfg["usysd-service"].file) then
      usd.log("\27[A\27[G\27[2K", usd.statii.fail, "service ", name,
        " has invalid configuration")
      return nil
    end
    
    local file = cfg["usysd-service"].file
    local user = cfg["usysd-service"].user or "root"
    local uid, err = users.get_uid(user)
    
    if not uid then
      usd.log("\27[A\27[G\27[2K", usd.statii.fail, "service ", name,
        " is configured to run as ", user, " but: ", err)
      return nil
    end
    
    if user ~= process.info().owner and process.info().owner ~= 0 then
      usd.log("\27[A\27[G\27[2K", usd.statii.fail, "service ", name,
        " cannot be started as ", user, ": insufficient permissions")
      return nil
    end

    starting[full_name] = true
    if cfg["usysd-service"].depends then
      for i, svc in ipairs(cfg["usysd-service"].depends) do
        local ok = api.start(svc)
        if not ok then
          usd.log(usd.statii.fail, "failed starting dependency ", svc)
          starting[name] = false
          return nil
        end
      end
    end
    
    local ok, err = loadfile(file)
    if not ok then
      usd.log("\27[A\27[G\27[2K", usd.statii.fail, "failed to load ", name, ": ", err)
      return nil
    end

    local pid, err = users.exec_as(uid, "", ok, "["..name.."]", nil, ttys[tty])
    if not pid and err then
      usd.log("\27[A\27[G\27[2K", usd.statii.fail, "failed to start ", full_name, ": ", err)
      return nil
    end

    usd.log("\27[A\27[G\27[2K", usd.statii.ok, "started service ", full_name)
    
    running[full_name] = pid
    return true
  end

  function api.stop(name)
    checkArg(1, name, "string")
    usd.log(usd.statii.ok, "stopping service ", name)
    if not running[name] then
      usd.log(usd.statii.warn, "service ", name, " is not running")
      return nil
    end
    process.kill(running[name], process.signals.quit)
    running[name] = nil
    return true
  end

  function api.list(enabled, running)
    enabled = not not enabled
    running = not not running
    if running then
      local list = {}
      for name in pairs(usd.running) do
        list[#list + 1] = name
      end
      return list
    end
    if enabled then
      local list = {}
      for line in io.lines(autostart,"l") do
        list[#list + 1] = line
      end
      return list
    end
    return fs.list(svc_dir)
  end

  function api.enable(name)
    checkArg(1, name, "string")
    local enabled = api.list(true)
    local handle, err = io.open(autostart, "w")
    if not handle then return nil, err end
    table.insert(enabled, math.min(#enabled + 1, math.max(1, #enabled - 1)), name)
    handle:write(table.concat(enabled, "\n"))
    handle:close()
    return true
  end

  function api.disable(name)
    checkArg(1, name, "string")
    local enabled = api.list(true)
    local handle, err = io.open(autostart, "w")
    if not handle then return nil, err end
    for i=1, #enabled, 1 do
      if enabled[i] == name then
        table.remove(enabled, i)
        break
      end
    end
    handle:write(table.concat(enabled, "\n"))
    handle:close()
    return true
  end

  usd.api = api
  package.loaded.usysd = api

  for line in io.lines(autostart, "l") do
    api.start(line)
  end
end
--#include "src/serviceapi.lua"
-- wrap computer.shutdown --

do
  local network = require("network")
  local computer = require("computer")
  local shutdown = computer.shutdown

  function usd.shutdown()
    usd.log(usd.statii.wait, "stopping services")
    for name in pairs(usd.running) do
      usd.api.stop(name)
    end
    usd.log(usd.statii.ok, "stopped services")

    if network.hostname() ~= "localhost" then
      usd.log(usd.statii.wait, "saving hostname")
      local handle = io.open("/etc/hostname", "w")
      if handle then
        handle:write(network.hostname())
        handle:close()
      end
      usd.log("\27[A\27[G\27[2K", usd.statii.ok, "saved hostname")
    end

    os.sleep(1)

    shutdown(usd.__should_reboot)
  end

  function computer.shutdown(reboot)
    usd.__should_shut_down = true
    usd.__should_reboot = not not reboot
  end
end
--#include "src/shutdown.lua"

local proc = require("process")
while true do
  coroutine.yield(2)
  for name, pid in pairs(usd.running) do
    if not proc.info(pid) then
      usd.running[name] = nil
    end
  end
  if usd.__should_shut_down then
    usd.shutdown()
  end
end
