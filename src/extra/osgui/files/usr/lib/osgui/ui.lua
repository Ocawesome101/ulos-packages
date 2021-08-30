-- ui lib

local ui = {}
osgui.ui = ui

require("component").invoke(osgui.gpu.getScreen(), "setPrecise", false)
local oserr=osgui.syserror

local windows = {}
osgui.ui.__windows = windows

local running = {}
local erroring = false
function ui.add(app)
  if not app.init then
    osgui.notify("That application has no init function.")
    return
  elseif not app.refresh then
    osgui.notify("That application has no refresh function.")
    return
  end
  app:init()
  app.update = true
  if ui.buffered then
    local err
    app.buf, err = osgui.gpu.allocateBuffer(app.w, app.h)
    if not app.buf then
      if erroring then
        -- we ran into an error with the error box.  Oh no!
        oserr(err)
      else
        -- there's a chance we might have enough VRAM for an error box.
        erroring = true
        osgui.syserror(err)
        erroring = false
      end
    end
  end
  app.n = math.random(0, 999999999)
  running[app.n] = true
  table.insert(windows, 1, app)
  return app.n
end

function ui.running(n)
  return not not running[n]
end

local function search(x, y)
  for i=1, #windows, 1 do
    local w = windows[i]
    if (w.x and w.y and w.w and w.h) and
      x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h then
      return i, windows[i]
    end
  end
end

-- return whether w1 overlaps with w2
local function overlaps(w1, w2)
  do return true end
  local blx, bly = w1.x + w1.w, w2.y + w1.h
  return (w1.x >= w2.x and w1.x <= w2.x + w2.w and w1.y >= w2.y
    and w1.y <= w2.y + w2.h) or
         (w2.x >= blx and w2.x + w2.h <= blx and w2.y >= bly
    and w2.y + w2.h <= bly)
end

local function func()end
local closeme = {closeme=true,
  init=func,refresh=func,key=func,click=func,close=func}

local function call(n, i, f, ...)
  local ok, err = pcall(f, ...)
  if not ok and err then
    closeme.n = windows[i].n
    closeme.buf = windows[i].buf
    windows[i]=closeme
    osgui.syserror(string.format(
      "Error in %s handler: %s", n, err))
  end
  return err
end

local dx, dy, to = 0, 0, 1
ui.composited = 0
local screen = osgui.gpu.getScreen()
function ui.tick()
  local s = table.pack(require("computer").pullSignal(to))
  to = 1
  if s.n == 0 then goto draw end
  if s[2] ~= screen then return end
  if s[1] == "touch" then
    local i = search(s[3], s[4])
    if i then
      if windows[1].unfocus then
        call("unfocus", 1, windows[1].unfocus, windows[1])
      end
      local w = table.remove(windows, i)
      table.insert(windows, 1, w)
      dx, dy = s[3] - w.x, s[4] - w.y
      windows[1].drag = true
      if windows[1].focus then
        call("focus", 1, windows[1].focus, windows[1])
      end
    end
  elseif s[1] == "drag" and windows[1].drag then
    windows[1].drag = 1
    if not windows[1].nodrag then
      osgui.gpu.setBackground(0x000040)
      osgui.gpu.fill(windows[1].x, windows[1].y, windows[1].w, windows[1].h,
        " ")
      windows[1].x, windows[1].y = s[3]-dx, s[4]-dy
    end
  elseif s[1] == "drop" and search(s[3],s[4])==1 then
    if s[5] == 1 then
      if windows[1].close then
        local r = call("close", 1, windows[1].close, windows[1])
        if r == "__no_keep_me_open" then goto draw end
      end
      windows[1].closeme = true
    elseif windows[1].drag ~= 1 then
      windows[1].update = true
      if not windows[1].click then
        osgui.notify("Application has no click handler.")
      else
        call("click", 1, windows[1].click, windows[1],
          s[3]-windows[1].x+1, s[4]-windows[1].y+1)
      end
    end
    if windows[1] then windows[1].drag = false end
  elseif s[1] == "key_up" then
    if not windows[1].key then
      osgui.notify("Application has no keypress handler.")
    else
      windows[1].update = true
      call("key", 1, windows[1].key, windows[1], s[3], s[4])
    end
  elseif s[1] == "scroll" and not windows[1].drag then
    local i = search(s[3], s[4])
    if i and windows[i].scroll then
      call("scroll", i, windows[i].scroll, windows[i], -s[5])
      windows[i].update = true
    end
  end
  ::draw::
  ui.nWindows = #windows
  local comp = 0
  for i=#windows, 1, -1 do
    if windows[i].closeme then
      if ui.buffered and windows[i].buf then
        osgui.gpu.freeBuffer(windows[i].buf)
        osgui.gpu.setActiveBuffer(0)
      end
      osgui.gpu.setBackground(0x000040)
      if windows[i].x and windows[i].y and windows[i].w and windows[i].h then
        osgui.gpu.fill(windows[i].x, windows[i].y, windows[i].w, windows[i].h,
          " ")
      end
      if windows[i].n then
        running[windows[i].n] = nil
      end
      table.remove(windows, i)
      if i == 1 and #windows > 0 and windows[1].focus then
        call("focus", 1, windows[1].focus, windows[1]) end
      to = 0
    else
      if ui.buffered then
        osgui.gpu.setActiveBuffer(windows[i].buf or 0)
      end
      -- note: while buffered, no windows will refresh during a window drag
      if (not windows[i].buf) or ((not (windows[1].drag and ui.buffered)) and
          (windows[i].active or windows[i].update or not ui.buffered)) then
        windows[i].update = false
        call("refresh", i, windows[i].refresh, windows[i], gpu)
        comp = comp + 1
      end
      if ui.buffered then
        osgui.gpu.bitblt(0, windows[i].x, windows[i].y)
        osgui.gpu.setActiveBuffer(0)
      end
    end
  end
  if ui.buf then
    osgui.gpu.setActiveBuffer(ui.buf)
    osgui.gpu.bitblt(0)
    osgui.gpu.setActiveBuffer(0)
  end
  ui.composited = comp
end

if osgui.gpu.allocateBuffer then
  ui.buffered = true
end
