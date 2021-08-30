-- basic window "app"

local function wrap(app, name)
  local w = {}
  
  function w:init()
    app:init()
    self.x = app.x
    self.y = app.y
    self.w = app.w + 4
    self.h = app.h + 2
  end
  
  function w:refresh(gpu)
    local x, y = self.x, self.y
    if osgui.ui.buffered then
      app.buf = self.buf
      x, y = 1, 1
    end
    osgui.gpu.setBackground(0x444444)
    osgui.gpu.setForeground(0x888888)
    osgui.gpu.fill(x, y, self.w, self.h, " ")
    if name then osgui.gpu.set(x, y, name) end
    osgui.gpu.setBackground(0x888888)
    osgui.gpu.setForeground(0x000000)
    osgui.gpu.fill(x + 2, y + 1, self.w - 4, self.h - 2, " ")
    app.x = x + 2
    app.y = y + 1
    app:refresh(gpu)
  end
  
  function w:click(x, y)
    app:click(x - 1, y - 1)
  end
  
  return setmetatable(w, {__index = app})
end

osgui.window = wrap
