local computer = require("computer")

return function()
  local env = setmetatable({osgui = {}}, {__index = _G})
  env._ENV=env
  env._G=env

  local gpu = require("tty").getgpu(io.stderr.tty)
  if gpu.isProxy then
    return nil, "gpu must not be proxied"
  end

  env.osgui.gpu = gpu

  local w, h = gpu.getResolution()
  gpu.setBackground(0x000040)
  gpu.fill(1, 1, w, h, " ")

  function env.osgui.syserror(e)
    env.osgui.gpu.setBackground(0x808080)
    env.osgui.gpu.fill(40, 15, 80, 20, " ")
    env.osgui.gpu.setBackground(0xc0c0c0)
    env.osgui.gpu.fill(42, 16, 76, 18, " ")
    env.osgui.gpu.setForeground(0x000000)
    env.osgui.gpu.set(44, 17, "A fatal system error has occurred:")
    local l = 0
    for line in debug.traceback(e, 2):gmatch("[^\n]+") do
      env.osgui.gpu.set(44, 19 + l, (line:gsub("\t", "  ")))
      l = l + 1
      computer.pullSignal(0.1)
    end
    computer.beep(440, 2)
  end

  function env.osgui.fread(fpath)
    local handle, err = io.open(fpath, "r")
    if not handle then
      return nil, fpath..": "..err
    end
    local data = handle:read("a")
    return data
  end

  local function loaduifile(file)
    local ok, err = assert(loadfile(file, "t", env))
    local ok, err = assert(pcall(ok))
    return err or true
  end

  loaduifile("/usr/lib/osgui/ui.lua")
  loaduifile("/usr/lib/osgui/buttons.lua")
  loaduifile("/usr/lib/osgui/textbox.lua")
  loaduifile("/usr/lib/osgui/label.lua")
  loaduifile("/usr/lib/osgui/view.lua")
  loaduifile("/usr/lib/osgui/window.lua")
  loaduifile("/usr/lib/osgui/notify.lua")

  env.osgui.dofile = loaduifile

  local n = env.osgui.ui.add(loaduifile("/usr/lib/apps/launcher.lua"))

  io.write("\27?15c\27?1;2;3s")
  io.flush()
  while not env.osgui.ui.logout do
    env.osgui.ui.tick()
    if not env.osgui.ui.running(n) then
      n = env.osgui.ui.add(loaduifile("/usr/lib/apps/launcher.lua"))
    end
  end

  for i, window in ipairs(env.osgui.ui.__windows) do
    if window.close then
      pcall(window.close, window)
    end
  end

  io.write("\27?5c\27[m\27[2J\27[1;1H")
  io.flush()
end
