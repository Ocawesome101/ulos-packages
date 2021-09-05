-- Refinement init system. --
-- Copyright (c) 2021 i develop things under the DSLv1.

local rf = {}
-- versioning --

do
  rf._NAME = "Refinement"
  rf._RELEASE = "1.54"
  rf._RUNNING_ON = "ULOS"
  
  io.write("\n  \27[97mWelcome to \27[93m", rf._RUNNING_ON, "\27[97m!\n\n")
  local version = "2021.09.05"
  rf._VERSION = string.format("%s r%s-%s", rf._NAME, rf._RELEASE, version)
end
--#include "src/version.lua"
-- logger --

do
  rf.prefix = {
    red = " \27[91m*\27[97m ",
    blue = " \27[94m*\27[97m ",
    green = " \27[92m*\27[97m ",
    yellow = " \27[93m*\27[97m "
  }

  local h,e=io.open("/sys/cmdline","r")
  if h then
    e=h:read("a")
    h:close()
    h=e
  end
  if h and h:match("bootsplash") then
    rf._BOOTSPLASH = true
    function rf.log(...)
      io.write("\27[G\27[2K", ...)
      io.flush()
    end
  else
    function rf.log(...)
      io.write(...)
      io.write("\n")
    end
  end

  rf.log(rf.prefix.blue, "Starting \27[94m", rf._VERSION, "\27[97m")
end
--#include "src/logger.lua"
-- set the system hostname, if possible --

rf.log(rf.prefix.green, "src/hostname")

if package.loaded.network then
  local handle, err = io.open("/etc/hostname", "r")
  if not handle then
    rf.log(rf.prefix.red, "cannot open /etc/hostname: ", err)
  else
    local data = handle:read("a"):gsub("\n", "")
    handle:close()
    rf.log(rf.prefix.blue, "setting hostname to ", data)
    package.loaded.network.sethostname(data)
  end
end
--#include "src/hostname.lua"
local config = {}
do
  rf.log(rf.prefix.blue, "Loading service configuration")

  local fs = require("filesystem")
  local capi = require("config").bracket

  -- string -> boolean, number, or string
  local function coerce(val)
    if val == "true" then
      return true
    elseif val == "false" then
      return false
    elseif val == "nil" then
      return nil
    else
      return tonumber(val) or val
    end
  end

  local fs = require("filesystem")
  if fs.stat("/etc/rf.cfg") then
    config = capi:load("/etc/rf.cfg")
  end
end
--#include "src/config.lua"
-- service management, again

rf.log(rf.prefix.green, "src/services")

do
  local svdir = "/etc/rf/"
  local sv = {}
  local running = {}
  rf.running = running
  local process = require("process")
  
  function sv.up(svc)
    local v = config[svc]
    if not v then
      return nil, "no such service"
    end
    if (not v.type) or v.type == "service" then
      rf.log(rf.prefix.yellow, "service START: ", svc)
      
      if running[svc] then
        return true
      end

      if not config[svc] then
        return nil, "service not registered"
      end
    
      if config[svc].depends then
        for i, v in ipairs(config[svc].depends) do
          local ok, err = sv.up(v)
      
          if not ok then
            return nil, "failed starting dependency " .. v .. ": " .. err
          end
        end
      end

      local path = config[svc].file or
        string.format("%s.lua", svc)
    
      if path:sub(1,1) ~= "/" then
        path = string.format("%s/%s", svdir, path)
      end
    
      local ok, err = loadfile(path, "bt", _G)
      if ok then
        local pid = process.spawn {
          name = svc,
          func = ok,
        }
    
        running[svc] = pid
      end
  
      if not ok then
        rf.log(rf.prefix.red, "service FAIL: ", svc, ": ", err)
        return nil, err
      else
        rf.log(rf.prefix.yellow, "service UP: ", svc)
        return true
      end
    elseif v.type == "script" then
      rf.log(rf.prefix.yellow, "script START: ", svc)
      local file = v.file or svc
      
      if file:sub(1, 1) ~= "/" then
        file = string.format("%s/%s", svdir, file)
      end
      
      local ok, err = pcall(dofile, file)
      if not ok and err then
        rf.log(rf.prefix.red, "script FAIL: ", svc, ": ", err)
        return nil, err
      else
        rf.log(rf.prefix.yellow, "script DONE: ", svc)
        return true
      end
    end
  end
  
  function sv.down(svc)
    if not running[svc] then
      return true
    end
    
    local ok, err = process.kill(running[svc], process.signals.interrupt)
    if not ok then
      return nil, err
    end
    
    running[svc] = nil
    return true
  end
  
  function sv.list()
    local r = {}
    for k,v in pairs(config) do
      if k ~= "__load_order" then
        r[k] = {isRunning = not not running[k], isEnabled = not not v.autostart,
          type = config[k].type}
      end
    end
    return r
  end

  function sv.add(stype, name, file, ...)
    if config[name] then
      return nil, "service already exists"
    end

    local nent = {
      __load_order = {"autostart", "type", "file", "depends"},
      depends = table.pack(...),
      autostart = false,
      type = stype,
      file = file
    }
    table.insert(config.__load_order, name)
    config[name] = nent
    require("config").bracket:save("/etc/rf.cfg", config)
    return true
  end

  function sv.del(name)
    checkArg(1, name, "string")
    if not config[name] then
      return nil, "no such service"
    end
    config[name] = nil
    for k, v in pairs(config.__load_order) do
      if v == name then
        table.remove(config.__load_order, k)
        break
      end
    end
    require("config").bracket:save("/etc/rf.cfg", config)
    return true
  end
  
  function sv.enable(name)
    if not config[name] then
      return nil, "no such service"
    end
    config[name].autostart = true
    require("config").bracket:save("/etc/rf.cfg", config)
    return true
  end

  function sv.disable(name)
    if not config[name] then
      return nil, "no such service"
    end
    config[name].autostart = false
    require("config").bracket:save("/etc/rf.cfg", config)
    return true
  end

  package.loaded.sv = package.protect(sv)
  
  rf.log(rf.prefix.blue, "Starting services")
  for k, v in pairs(config) do
    if v.autostart then
      sv.up(k)
    end
  end

  rf.log(rf.prefix.blue, "Started services")
end
--#include "src/services.lua"
-- shutdown override mkII

rf.log(rf.prefix.green, "src/shutdown")

do
  local computer = require("computer")
  local process = require("process")

  local shutdown = computer.shutdown

  function rf.shutdown(rbt)
    rf.log(rf.prefix.red, "INIT: Stopping services")
    
    for svc, proc in pairs(rf.running) do
      rf.log(rf.prefix.yellow, "INIT: Stopping service: ", svc)
      process.kill(proc, process.signals.kill)
    end

    if package.loaded.network then
      local net = require("network")
      if net.hostname() ~= "localhost" then
        rf.log(rf.prefix.red, "INIT: saving hostname")
        local handle, err = io.open("/etc/hostname", "w")
        if handle then
          handle:write(net.hostname())
          handle:close()
        end
      end
    end

    rf.log(rf.prefix.red, "INIT: Requesting system shutdown")
    shutdown(rbt)
  end

  function computer.shutdown(rbt)
    if process.info().owner ~= 0 then return nil, "permission denied" end
    rf._shutdown = true
    rf._shutdown_mode = not not rbt
  end
end
--#include "src/shutdown.lua"

while true do
  if rf._shutdown then
    rf.shutdown(rf._shutdown_mode)
  end
  --local s = table.pack(
  coroutine.yield(2)
  --) if s[1] == "process_died" then print(table.unpack(s)) end
end
