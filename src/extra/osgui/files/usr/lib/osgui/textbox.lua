-- textboxes

local base = {}

function base:key(k, c)
  if self.focused == 0 then return end
  local box = self.boxes[self.focused]
  if not box then return end
  if k == 8 then
    box.text = box.text:sub(1, -2)
  elseif k == 13 and box.submit then
    if box.submit(box.text) == true then
      box.text = ""
    end
  elseif k >= 31 and k <= 127 then
    box.text = box.text .. string.char(k)
  end
end

function base:click(x, y)
  self.focused = 0
  for k, v in pairs(self.boxes) do
    if x >= v.x and x <= v.x + v.w and y == v.y then
      self.focused = k
    end
  end
end

function base:draw(app)
  local f, b
  for k, v in pairs(self.boxes) do
    if v.bg then osgui.gpu.setBackground(v.bg) end
    if v.fg then osgui.gpu.setForeground(v.fg) end
    osgui.gpu.fill(app.x+v.x-1,app.y+v.y-1,v.w,1," ")
    local wr = (self.focused == k and (v.text:sub(0-v.w+1).."|") or
      (v.text:sub(1,v.w)))
    osgui.gpu.set(app.x+v.x-1,app.y+v.y-1,wr)
  end
end

function base:add(new)
  new.text = new.text or ""
  self.boxes[#self.boxes+1] = new
end

function osgui.textboxgroup()
  return setmetatable({focused=0,boxes={}},{__index=base})
end
