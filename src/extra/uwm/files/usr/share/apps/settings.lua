-- settings app --

local item = require("wm.item")
local config = require("config")
local tbox = require("wm.textbox")

local app = {
  w = 40,
  h = 10,
  name = "UWM Settings"
}

function app:init()
  self.gpu.setForeground(self.app.wm.cfg.text_focused)
  self.gpu.setBackground(self.app.wm.cfg.bar_color)
  self.gpu.fill(1, 1, self.app.w, self.app.h, " ")
  self.items = item(self, 1, 1)
  
  -- setting: default window width
  self.items:add {x = 1, y = 1, text = "Default window width",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 1, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number)") else
      self.app.wm.cfg.width = txt end end,
    text = tostring(self.app.wm.cfg.width)})

  -- setting: default window height
  self.items:add {x = 1, y = 2, text = "Default window height",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 2, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number)") else
      self.app.wm.cfg.height = txt end end,
    text = tostring(self.app.wm.cfg.height)})

  -- setting: background color
  self.items:add {x = 1, y = 3, text = "Background color (hex)",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 3, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number or hex code") else
      self.app.wm.cfg.background_color = txt end end,
    text = string.format("0x%06X", self.app.wm.cfg.background_color)})

  -- setting: bar color
  self.items:add {x = 1, y = 4, text = "Bar color (hex)",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 4, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number or hex code") else
      self.app.wm.cfg.bar_color = txt end end,
    text = string.format("0x%06X", self.app.wm.cfg.bar_color)})

  -- setting: text color
  self.items:add {x = 1, y = 5, text = "Text color (focused) (hex)",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 5, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number or hex code") else
      self.app.wm.cfg.text_focused = txt end end,
    text = string.format("0x%06X", self.app.wm.cfg.text_focused)})

  -- setting: unfocused text color
  self.items:add {x = 1, y = 6, text = "Text color (unfocused) (hex)",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 6, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number or hex code") else
      self.app.wm.cfg.text_unfocused = txt end end,
    text = string.format("0x%06X", self.app.wm.cfg.text_unfocused)})

  -- setting: window update interval
  self.items:add {x = 1, y = 7, text = "Update interval (seconds)",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color}
  self.items:add(tbox {
    x = 30, y = 7, width = 10, foreground = 0, background = 0xFFFFFF,
    window = self, submit = function(_, txt) txt = tonumber(txt) if not txt then
      self.app.wm.notify("Invalid value (must be number)") else
      self.app.wm.cfg.update_interval = txt end end,
    text = tostring(self.app.wm.cfg.update_interval)})
end

function app:click(...)
  self.items:click(...)
end

function app:key(c, k)
  self.items:key(c, k)
end

function app:refresh()
  if not self.items then self.app.init(self) end
  self.items:refresh()
end

function app:close()
  config.table:save("/etc/uwm.cfg", self.app.wm.cfg)
end

return app
