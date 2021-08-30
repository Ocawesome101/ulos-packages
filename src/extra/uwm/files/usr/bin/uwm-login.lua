-- login --

local tty = require("tty")
local text = require("text")
local users = require("users")
local config = require("config")
local process = require("process")

local cfg = config.table:load("/etc/uwm-login.cfg") or {}

cfg.tty = cfg.tty or 0
cfg.background_color = cfg.background_color or 0xAAAAAA
cfg.box_background = cfg.box_background or 0xFFFFFF
cfg.text_color = cfg.text_color or 0x111111
cfg.box_color = cfg.box_color or 0x444444

config.table:save("/etc/uwm-login.cfg", cfg)

local handle, err = io.open("/sys/dev/tty"..cfg.tty, "rw")
if not handle then
  io.stderr:write("uwm-login: cannot open tty: " .. err .. "\n")
  os.exit(1)
end

local gpu = tty.getgpu(cfg.tty)
local w, h = gpu.getResolution()

local box_w, box_h = 25, 10
local box_x, box_y = (w // 2) - (box_w // 2), (h // 2) - (box_h // 2)

local screen = gpu.getScreen()

local uwm, err = loadfile("/usr/bin/uwm.lua")
if not uwm then
  io.stderr:write("uwm-login: cannot load uwm: " .. err .. "\n")
  os.exit(1)
end

local function menu(title, opts)
  if not title then return end
  local x = (w // 2) - (#title // 2)
  local y = (h // 2) - (#opts // 2)
  local mw = #title
  opts = opts or {"OK", "Cancel"}
  gpu.setForeground(cfg.background_color)
  gpu.setBackground(cfg.box_color)
  gpu.fill(x, y, mw, #opts + 1, " ")
  gpu.set(x, y, title)
  for i=1, #opts, 1 do
    gpu.set(x, y + i, opts[i])
  end
  local sig, scr, _x, _y
  repeat
    local s, S = coroutine.yield(0)
  until (s == "touch" or s == "drop") and S == screen
  repeat
    sig, scr, _x, _y = coroutine.yield(0)
  until sig == "drop" and scr == screen
  gpu.setBackground(cfg.background_color)
  gpu.fill(x, y, w, #opts + 1, " ")
  if _x < x or _x > x+15 or _y < y or _y > y+#opts then return
  elseif _y == y then -- do nothing
  else return opts[_y - y] end
end

local keyboards = {}
for _,keyboard in ipairs(require("component").invoke(screen, "getKeyboards")) do
  keyboards[keyboard] = true
end

handle:write("\27?15c")
handle:flush()

local function log_in(uname, pass)
  if not users.get_uid(uname) then
    menu("**no such user**", {"Ok"})
    return
  end

  local exit, err = users.exec_as(users.get_uid(uname), pass, uwm, "uwm", true)
  if not exit then
    menu("**"..err.."**", {"Ok"})
    return
  end

  return true
end

while true do
  gpu.setBackground(cfg.background_color)
  gpu.fill(1, 1, w, h, " ")

  gpu.setBackground(cfg.box_color)
  gpu.fill(box_x, box_y, box_w, box_h, " ")
  
  local uname, pass = "", ""
  local focused = 1

  gpu.setForeground(cfg.background_color)
  gpu.set(1, 1, "Power | ULOS Login Manager")
  gpu.set(box_x + (box_w // 2) - 4, box_y + 1, "Username")
  gpu.set(box_x + (box_w // 2) - 4, box_y + 4, "Password")
  gpu.setForeground(cfg.text_color)
  gpu.setBackground(cfg.box_background)
  while true do
    gpu.set(box_x + 2, box_y + 2, text.padLeft(box_w - 4, uname ..
      (focused == 1 and "|" or "")))
    gpu.set(box_x + 2, box_y + 5, text.padLeft(box_w - 4, pass:gsub(".", "*") ..
      (focused == 2 and "|" or "")))
    local signal, scr, arg1, arg2 = coroutine.yield()
    if scr == screen then
      if signal == "touch" then
        if arg1 < 6 and arg2 == 1 then
          local sd = menu("**Shut Down?**", {"Shut Down", "Restart", "Cancel"})
          if sd == "Shut Down" then
            require("computer").shutdown()
          elseif sd == "Restart" then
            require("computer").shutdown(true)
          else
            break
          end
        end
        if arg2 == box_y + 2 then focused = 1 end
        if arg2 == box_y + 5 then focused = 2 end
      end
    elseif keyboards[scr] then
      if signal == "key_down" then
        if focused == 1 then
          if arg1 > 31 and arg1 < 127 then
            uname = uname .. string.char(arg1)
          elseif arg1 == 8 then
            uname = uname:sub(0, -2)
          elseif arg1 == 13 then
            focused = 2
          end
        elseif focused == 2 then
          if arg1 > 31 and arg1 < 127 then
            pass = pass .. string.char(arg1)
          elseif arg1 == 8 then
            pass = pass:sub(0, -2)
          elseif arg1 == 13 then
            if log_in(uname, pass) then break end
          end
        end
      end
    end
  end
end
