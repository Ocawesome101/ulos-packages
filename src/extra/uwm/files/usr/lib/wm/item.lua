-- labels --

local _item = {}

function _item:click(x, y)
  for i, item in ipairs(self.items) do
    local iw = item.w or (item.text and #item.text) or 1
    local ih = item.h or 1
    if x >= item.x and x < item.x + iw and
       y >= item.y and y < item.y + ih and item.click then
      item:click(x, y)
      --break
    end
  end
end

function _item:key(...)
  for i, item in ipairs(self.items) do
    if item.key then item:key(...) end
  end
end

function _item:refresh()
  for i, item in ipairs(self.items) do
    if item.refresh then
      item:refresh(self.window.gpu)
    elseif item.text then
      if item.foreground then self.window.gpu.setForeground(item.foreground) end
      if item.background then self.window.gpu.setBackground(item.background) end
      if type(item.text) == "string" then
        self.window.gpu.set(item.x, item.y, item.text)
      elseif type(item.text) == "table" then
        for n, line in pairs(item.text) do
          self.window.gpu.set(item.x, item.y + n - 1, line)
        end
      end
    end
  end
end

function _item:add(args)
  args.x = args.x or 1
  args.y = args.y or 1
  args.w = args.w or (args.text and #args.text) or 1
  args.h = args.h or 1
  args.text = args.text or ""
  table.insert(self.items, args)
end

return function(win)
  return setmetatable({window = win, items = {}}, {__index = _item})
end
