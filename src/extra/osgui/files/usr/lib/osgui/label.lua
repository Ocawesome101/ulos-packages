-- text groups

local base = {}

function base:draw(app)
  for i=1, #self.labels, 1 do
    local v = self.labels[i]
    if v.fg then osgui.gpu.setForeground(v.fg) end
    if v.bg then osgui.gpu.setBackground(v.bg) end
    local y = app.y + v.y - self.scroll - 1
    if y >= app.y + 1 and y <= app.y + app.h - 1 then
      osgui.gpu.set(app.x+v.x-1, y, v.text)
    end
  end
end

function base:add(new)
  self.labels[#self.labels+1] = new
end

function base:doscroll(n)
  self.scroll = self.scroll + n
  if self.scroll < 0 then self.scroll = 0 end
end

function osgui.labelgroup()
  return setmetatable({labels={},scroll=0},{__index=base})
end
