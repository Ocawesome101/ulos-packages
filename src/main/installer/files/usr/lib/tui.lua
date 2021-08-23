-- basic TUI scheme --

local termio = require("termio")

local inherit
inherit = function(t, ...)
  t = t or {}
  local new = setmetatable({}, {__index = t, __call = inherit})
  if new.init then new:init(...) end
  return new
end

local function class(t)
  return setmetatable(t or {}, {__call = inherit})
end

local tui = {}

tui.Text = class {
  selectable = false,

  init = function(self, t)
    local text = require("text").wrap(t.text, (t.width or 80) - 2)
    self.text = {}
    for line in text:gmatch("[^\n]+") do
      self.text[#self.text+1] = line
    end
    self.x = t.x or 1
    self.y = t.y or 1
    self.width = t.width or 80
    self.height = t.height or 25
    self.scroll = 0
  end,

  refresh = function(self, x, y)
    local wbuf = "\27[34;47m"
    for i=self.scroll+1, self.height - 2, 1 do
      if self.text[i] then
        wbuf = wbuf .. (string.format("\27[%d;%dH%s", y+self.y+i-1, x+self.x,
          require("text").padLeft(self.width - 2, self.text[i] or "")))
      end
    end
    return wbuf
  end
}

tui.List = class {
  init = function(self, t)
    self.elements = t.elements
    self.selected = t.selected or 1
    self.scroll = 0
    self.width = t.width or 80
    self.height = t.height or 25
    self.x = t.x or 1
    self.y = t.y or 1
    self.bg = t.bg or 47
    self.fg = t.fg or 30
    self.bg_sel = t.bg_sel or 31
    self.fg_sel = t.fg_sel or 37
  end,

  refresh = function(self, x, y)
    local wbuf
    for i=self.y, self.y + self.height, 1 do
      wbuf = wbuf .. (string.format("\27[%d;%dH", i, x+self.x-1))
    end
  end
}

tui.Selectable = class {
  selectable = true,

  init = function(self, t)
    self.x = t.x or 1
    self.y = t.y or 1
    self.text = t.text or "---"
    self.fg = t.fg or 30
    self.bg = t.bg or 47
    self.fgs = t.fgs or 37
    self.bgs = t.bgs or 41
    self.selected = not not t.selected
  end,

  refresh = function(self, x, y)
    if y == 0 then return "" end
    return (string.format("\27[%d;%dH\27[%d;%dm%s",
      self.y+y-1, self.x+x-1,
      self.selected and self.fgs or self.fg,
      self.selected and self.bgs or self.bg,
      self.text))
  end
}

return tui
