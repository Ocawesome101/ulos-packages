-- textboxes! --

local _tb = {}

function _tb:key(c, k)
  if self.focused then
    if c > 31 and c < 127 then
      self.text = self.text .. string.char(c)
    elseif c == 8 then
      if #self.text > 0 then self.text = self.text:sub(0, -2) end
    elseif c == 13 then
      if self.submit then self:submit(self.text) end
    end
  end
end

function _tb:click(x, y)
  if y == self.y and x >= self.x and x < self.x + self.w then
    self.focused = true
  else
    self.focused = false
  end
end

function _tb:refresh()
  self.win.gpu.setForeground(self.fg)
  self.win.gpu.setBackground(self.bg)
  self.win.gpu.fill(self.x, self.y, self.w, 1, " ")
  self.win.gpu.set(self.x, self.y, 
    ((self.password and self.text:gsub(".", "*") or self.text)
      .. (self.focused and"|"or""))
      :sub(-math.min(#self.text + 2, self.w)))
end

return function(args)
  return setmetatable({x = args.x or 1, y = args.y or 1, w = args.width or 8,
    fg = args.foreground or 0xFFFFFF, bg = args.background or 0,
    password = not not args.isPassword,
    win = args.window, submit = args.submit, text = args.text or ""},
    {__index = _tb})
end
