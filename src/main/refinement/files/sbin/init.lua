-- Refinement init system. --
-- Copyright (c) 2021 i develop things under the DSLv1.

local rf = {}
-- versioning --

do
  rf._NAME = "Refinement"
  rf._RELEASE = "1.2"
  rf._RUNNING_ON = "@[{os.getenv('OS')}]"
  
  io.write("\n  \27[97mWelcome to \27[93m", rf._RUNNING_ON, "\27[97m!\n\n")
  local version = "2021.07.08"
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
  function rf.log(...)
    io.write(...)
    io.write("\n")
  end

  rf.log(rf.prefix.blue, "Starting \27[94m", rf._VERSION, "\27[97m")
end
--#include "src/logger.lua"
-- require function

rf.log(rf.prefix.green, "src/require")

do
  local loaded = package.loaded
  local loading = {}
  function _G.require(module)
    if loaded[module] then
      return loaded[module]
    elseif not loading[module] then
      local library, status, step
      
      step, library, status = "not found",
          package.searchpath(module, package.path)
      
      if library then
        step, library, status = "loadfile failed", loadfile(library)
      end
      
      if library then
        loading[module] = true
        step, library, status = "load failed", pcall(library, module)
        loading[module] = false
      end
      
      assert(library, string.format("module '%s' %s:\n%s",
          module, step, status))
      
      loaded[module] = status
      return status
    else
      error("already loading: " .. module .. "\n" .. debug.traceback(), 2)
    end
  end
end
--#include "src/require.lua"
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
    local section
    for line in io.lines("/etc/rf.cfg") do
      if line:match("%[.+%]") then
        section = line:sub(2, -2)
        config[section] = config[section] or {}
      else
        local k, v = line:match("^(.-) = (.+)$")
        if k and v then
          v = v:gsub("\n", "")
          if v:match("^%[.+%]$") then
            config[section][k] = {}
            for item in v:gmatch("[^%[%]%s,]+") do
              table.insert(config[section][k], coerce(item))
           end
          else
            config[section][k] = coerce(v)
          end
        end
      end
    end
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
    if not ok then
      return nil, err
    end
    
    local pid = process.spawn {
      name = svc,
      func = ok,
    }
    
    running[svc] = pid
    return true
  end
  
  function sv.down(svc)
    if not running[svc] then
      return true
    end
    
    local ok, err = process.kill(running[svc])
    if not ok then
      return nil, err
    end
    
    running[svc] = nil
    return true
  end
  
  function sv.list()
    return setmetatable({}, {
      __index = running,
      __pairs = running,
      __ipairs = running,
      __metatable = {}
    })
  end

  package.loaded.sv = package.protect(sv)
  
  rf.log(rf.prefix.blue, "Starting services")
  for k, v in pairs(config) do
    if v.autostart then
      if (not v.type) or v.type == "service" then
        rf.log(rf.prefix.yellow, "service START: ", k)
        local ok, err = sv.up(k)
    
        if not ok then
          rf.log(rf.prefix.red, "service FAIL: ", k, ": ", err)
        else
          rf.log(rf.prefix.yellow, "service UP: ", k)
        end
      elseif v.type == "script" then
        rf.log(rf.prefix.yellow, "script START: ", k)
        local file = v.file or k
        
        if file:sub(1, 1) ~= "/" then
          file = string.format("%s/%s", svdir, file)
        end
        
        local ok, err = pcall(dofile, file)
        if not ok and err then
          rf.log(rf.prefix.red, "script FAIL: ", k, ": ", err)
        else
          rf.log(rf.prefix.yellow, "script DONE: ", k)
        end
      end
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

  function computer.shutdown(rbt)
    if process.info().owner ~= 0 then
      return nil, "permission denied"
    end

    rf.log(rf.prefix.red, "INIT: Stopping services")
    
    for svc, proc in pairs(rf.running) do
      rf.log(rf.prefix.yellow, "INIT: Stopping service: ", svc)
      process.kill(proc)
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
end
--#include "src/shutdown.lua"

while true do
  --local s = table.pack(
  coroutine.yield()
  --) if s[1] == "process_died" then print(table.unpack(s)) end
end
