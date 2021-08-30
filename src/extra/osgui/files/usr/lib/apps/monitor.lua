-- example app

local computer = require("computer")

local app = {}

function app:init()
  self.x = 1
  self.y = 1
  self.w = 21
  self.h = 11
  self.active = true
  self.buttons = osgui.buttongroup()
  self.buttons:add({
    x = 3, y = 8, text = "Shut Down",
    click = function()computer.shutdown()end
  })
  self.buttons:add({
    x = 3, y = 9, text = "Restart",
    click = function()computer.shutdown(true)end
  })
  self.buttons:add({
    x = 3, y = 10, text = "Log Out",
    click = function()osgui.ui.logout=true end
  })
end

local last = computer.uptime()
local free = computer.freeMemory() // 1024
local vfree = 0
local gtm = 0
function app:refresh()
  osgui.gpu.setForeground(0x000000)
  osgui.gpu.set(self.x + 2, self.y + 1, string.format("Total RAM: %sk", computer.totalMemory() // 1024))
  if computer.uptime() - last >= 1 then
    free = computer.freeMemory()
    if free > 1024 then
      free = (free // 1024) .. "k"
    end
    last = computer.uptime()
    if osgui.gpu.freeMemory then
      gtm = osgui.gpu.totalMemory() // 1024
      vfree = osgui.gpu.freeMemory()
      if vfree > 1024 then
        vfree = (vfree // 1024) .. "k"
      end
    end
  end
  osgui.gpu.set(self.x + 2, self.y + 2, string.format("Free RAM: %s", free))
  osgui.gpu.set(self.x + 2, self.y + 3, string.format("Total VRAM: %sk", gtm))
  osgui.gpu.set(self.x + 2, self.y + 4, string.format("Free VRAM: %s", vfree))
  osgui.gpu.set(self.x + 2, self.y + 5, string.format("Recomposited: %s",
    osgui.ui.composited))
  osgui.gpu.set(self.x + 2, self.y + 6, string.format("Total: %s",
    osgui.ui.nWindows))
  self.buttons:draw(self)
end

function app:click(x, y)
  self.buttons:click(x, y)
end

function app:key(k)
end

function app:close()
end

return osgui.window(app, "Statistics")
