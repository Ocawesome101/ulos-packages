-- view: basically a little app-in-an-app type of thing

local _view = {}

function _view:click(x,y)
  if self.textboxes then self.textboxes:click(x-self.x,y-self.y) end
  if self.buttons then self.buttons:click(x-self.x,y-self.y) end
end

function _view:key(c,k)
  if self.textboxes then self.textboxes:key(c,k) end
end

function _view:draw(app)
  if self.border then
    osgui.gpu.setBackground(self.bc or 0x444444)
    osgui.gpu.fill(app.x+self.x-3, app.y+self.y-2, self.w+4, self.h+2, " ")
  end
  osgui.gpu.setBackground(self.bg or 0x888888)
  osgui.gpu.fill(app.x+self.x-1,app.y+self.y-1, self.w, self.h, " ")
  osgui.gpu.setForeground(0x000000)
  if self.textboxes then self.textboxes:draw() end
  if self.labels then self.labels:draw() end
  if self.buttons then self.buttons:draw() end
end

function _view:addLabel(l)
  if not self.labels then self.labels = osgui.labelgroup() end
  self.labels:add(l)
end

function _view:addTextbox(t)
  if not self.textboxes then self.texboxes = osgui.textboxgroup() end
  self.textboxes:add(t)
end

function _view:addButton(b)
  if not self.buttons then self.buttons = osgui.buttongroup() end
  self.buttons:add(b)
end

function osgui.view(x, y, w, h, border)
  checkArg(1, x, "number")
  checkArg(2, y, "number")
  checkArg(3, w, "number")
  checkArg(4, h, "number")
  return setmetatable({
    x = x,
    y = y,
    w = w,
    h = h,
    border = not not border
  }, {__index = _view})
end
