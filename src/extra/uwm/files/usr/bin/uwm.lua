-- basic window manager --

local tty = require("tty")
local fs = require("filesystem")
local config = require("config")
local process = require("process")
local computer = require("computer")
local gpuproxy = require("gpuproxy")
local gpu = tty.getgpu(io.stderr.tty)
local screen = gpu.getScreen()

if gpu.isProxy then
  io.stderr:write("\27[91mwm: not nestable\n\27[0m")
  os.exit(1)
end

require("component").invoke(gpu.getScreen(), "setPrecise", false)

local cfg = config.table:load(os.getenv("HOME") .. "/.config/uwm.cfg") or
            config.table:load("/etc/uwm.cfg") or {}
cfg.width = cfg.width or 65
cfg.height = cfg.height or 20
cfg.background_color=cfg.background_color or 0xAAAAAA
cfg.bar_color = cfg.bar_color or 0x444444
cfg.text_focused = cfg.text_focused or 0xFFFFFF
cfg.text_unfocused = cfg.text_unfocused or 0xAAAAAA
cfg.update_interval = cfg.update_interval or 0.05
require("config").table:save("/etc/uwm.cfg", cfg)

local w, h = gpu.getResolution()
gpu.setBackground(cfg.background_color)
gpu.fill(1, 1, w, h, " ")

local windows = {}

local function call(i, method, ...)
  if windows[i] and windows[i].app and windows[i].app[method] then
    local ok, err = pcall(windows[i].app[method], windows[i], ...)
    if not ok and err then
      gpu.set(1, 2, err)
    end
  end
end

local function unfocus_window()
  windows[1].gpu.setForeground(cfg.text_unfocused)
  windows[1].gpu.setBackground(cfg.bar_color)
  windows[1].gpu.set(1, windows[1].app.h+1, windows[1].app.__wintitle)
  gpu.bitblt(0, windows[1].x, windows[1].y, nil, nil, windows[1].buffer)
  call(1, "unfocus")
end

local wmt = {}
local n = 0
local function new_window(x, y, prog)
  if windows[1] then
    unfocus_window()
  end

  local app
  if type(prog) == "string" then
    local ok, err = loadfile("/usr/share/apps/" .. prog .. ".lua")
    if not ok then
      wmt.notify(prog .. ": " .. err)
      return
    end
    ok, app = pcall(ok)
    if not ok and app then
      wmt.notify(prog .. ": " .. app)
      return
    end
  elseif type(prog) == "table" then
    app = prog
  end

  if not app then
    wmt.notify("No app was returned")
    return
  end

  app.wm = wmt
  app.w = app.w or cfg.width
  app.h = app.h or cfg.height

  local buffer, err = gpu.allocateBuffer(app.w, app.h + 1)
  if not buffer then wmt.notify("/!\\ " .. err) return nil, err end
  local gpucontext = gpuproxy.buffer(gpu, buffer, nil, app.h)
  gpucontext.setForeground(cfg.text_focused)
  gpucontext.setBackground(cfg.bar_color)
  gpucontext.fill(1, app.h + 1, app.w, 1, " ")
  app.__wintitle = "Close | " .. (app.name or prog)
  gpucontext.set(1, app.h + 1, app.__wintitle)
  app.needs_repaint = true
  table.insert(windows, 1, {gpu = gpucontext, buffer = buffer, x = x or 1,
    y = y or 1, app = app})
  pcall(app.init, windows[1])
end

wmt.new_window = new_window
wmt.cfg = cfg

function wmt.notify(text, x, y)
  wmt.menu((w // 2) - (#text // 2), h // 2 - 1, text, {"OK"})
end

local function smenu(x, y, title, opts)
  if not title then return end
  x, y = x or 1, y or 2
  local w = #title
  opts = opts or {"OK", "Cancel"}
  gpu.setForeground(cfg.text_focused)
  gpu.setBackground(cfg.bar_color)
  gpu.fill(x, y, w, #opts + 1, " ")
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

wmt.menu = smenu

local function menu(x, y)
  local files = fs.list("/usr/share/apps")
  for i=1,#files,1 do
    files[i]=files[i]:gsub("%.lua$", "")
  end
  local sel = smenu(x, y, "**UWM App Menu**", files)
  if sel then
    gpu.setBackground(cfg.bar_color)
    gpu.set(x, y, "**Please Wait.**")
    new_window(x, y, sel)
  end
end

local function focus_window(id)
  unfocus_window()
  table.insert(windows, 1, table.remove(windows, id))
  windows[1].gpu.setForeground(cfg.text_focused)
  windows[1].gpu.setBackground(cfg.bar_color)
  windows[1].gpu.set(1, windows[1].app.h+1, windows[1].app.__wintitle)
  gpu.bitblt(0, windows[1].x, windows[1].y, nil, nil, windows[1].buffer)
  call(1, "focus")
end

local last_ref = 0
local function refresh()
  if computer.uptime() - last_ref < cfg.update_interval then return end
  last_ref = computer.uptime()
  for i=#windows, 1, -1 do
    if windows[i] then
      if windows[i].app.refresh and (windows[i].app.needs_repaint or
          windows[i].app.active) then
        call(i, "refresh", windows[i].gpu)
      end
    end
  end
  
  for i=#windows, 1, -1 do
    if windows[i] then
      if windows[i].ox ~= windows[i].x or windows[i].oy ~= windows[i].y then
        gpu.setBackground(cfg.background_color)
        gpu.fill(windows[i].ox or windows[i].x, windows[i].oy or windows[i].y,
          windows[i].app.w, windows[i].app.h + 1, " ")
        windows[i].ox = windows[i].x
        windows[i].oy = windows[i].y
      end

      gpu.bitblt(0, windows[i].x, windows[i].y, nil, nil, windows[i].buffer)
    end
  end
  gpu.setBackground(cfg.bar_color)
  gpu.setForeground(cfg.text_focused)
  gpu.set(1, 1, "Quit | ULOS Window Manager | Right-Click for menu")
end

io.write("\27?15c\27?1;2;3s")
io.flush()
local dragging, xo, yo = false, 0, 0
local keyboards = {}
for i, addr in ipairs(require("component").invoke(screen, "getKeyboards")) do
  keyboards[addr] = true
end
while true do
  refresh()
  local sig, scr, x, y, button = coroutine.yield(0)
  for i=1, #windows, 1 do
    if windows[i] then
      if windows[i].closeme then
        call(i, "close")
        local win = table.remove(windows, i)
        if #windows > 0 then focus_window(1) end
        gpu.freeBuffer(win.buffer)
      else
        goto skipclose
      end
      closed = true
      gpu.setBackground(cfg.background_color)
      gpu.fill(1, 1, w, h, " ")
      ::skipclose::
    end
  end
  if keyboards[scr] or scr == screen then
    if sig == "touch" then
      if y == 1 and x < 6 then
        local opt = smenu((w // 2) - 8, h // 2 - 1,
          "**Really Exit?**", {"Yes", "No"})
        if opt == "Yes" then
          break
        end
      elseif button == 1 then
        menu(x, y)
      else
        for i=1, #windows, 1 do
          if x >= windows[i].x and x <= windows[i].x + 6 and
             y == windows[i].y + windows[i].app.h then
            call(i, "close")
            gpu.freeBuffer(windows[i].buffer)
            gpu.setBackground(cfg.background_color)
            gpu.fill(windows[i].x, windows[i].y, windows[i].app.w,
              windows[i].app.h + 1, " ")
            table.remove(windows, i)
            if i == 1 and windows[1] then
              focus_window(1)
            end
            break
          elseif x >= windows[i].x and x < windows[i].x + windows[i].app.w and
              y >= windows[i].y and y <= windows[i].y + windows[i].app.h  then
            focus_window(i)
            dragging = true
            xo, yo = x - windows[1].x, y - windows[1].y
            break
          end
        end
      end
    elseif sig == "drag" and dragging then
      windows[1].x = x - xo
      windows[1].y = y - yo
      dragging = 1
    elseif sig == "drop" then
      if dragging ~= 1 and windows[1] then
        call(1, "click", x - windows[1].x + 1, y - windows[1].y + 1)
        windows[1].app.needs_repaint = true
      end
      dragging = false
      xo, yo = 0, 0
    elseif sig == "key_down" then
      if windows[1] then
        call(1, "key", x, y)
        windows[1].app.needs_repaint = true
      end
    end
  end
end

-- clean up unused resources
for i=1, #windows, 1 do
  call(i, "close", "UI_CLOSING")
  gpu.freeBuffer(windows[i].buffer)
end

io.write("\27?5c\27?0s\27[m\27[2J\27[1;1H")
io.flush()
