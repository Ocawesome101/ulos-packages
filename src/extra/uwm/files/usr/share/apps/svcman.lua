-- svcman: service manager --

local sv = require("sv")
local item = require("wm.item")
local tbox = require("wm.textbox")
local fs = require("filesystem")

local app = {
  w = 40,
  h = 4,
  name = "Service Manager"
}

local services = sv.list()
for k,v in pairs(services) do app.h=app.h+1 end

function app:init()
  self.page = 1
  self.tab_bar = item(self)
  self.tab_bar:add {
    x = 1, y = 1, text = " Toggle ", w = 8,
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color, click = function(b)
      self.page = 1
      b.foreground = self.app.wm.cfg.text_focused
      b.background = self.app.wm.cfg.bar_color
      self.tab_bar.items[2].background = 0
      self.tab_bar.items[2].foreground = self.app.wm.cfg.text_unfocused
    end
  }
  self.tab_bar:add {
    x = 9, y = 1, text = " Add ", w = 5,
    foreground = self.app.wm.cfg.text_unfocused,
    background = 0, click = function(b)
      self.page = 2
      b.foreground = self.app.wm.cfg.text_focused
      b.background = self.app.wm.cfg.bar_color
      self.tab_bar.items[1].background = 0
      self.tab_bar.items[1].foreground = self.app.wm.cfg.text_unfocused
    end
  }
  self.pages = {}
  self.pages[1] = item(self)
  self.pages[1]:add {
    x = 3, y = 3, text = "Services",
    foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color
  }

  local i = 0
  for service, state in pairs(services) do
    self.pages[1]:add {
      x = 3, y = 4 + i, text = service .. (state.isEnabled and "*" or ""),
      foreground = self.app.wm.cfg.text_focused, enabled = state.isEnabled,
      background = 0, click = function(b)
        local opts = {"Enable", "Cancel"}
        if b.enabled then opts[1] = "Disable" end
        local ed = self.app.wm.menu(self.x, self.y, "**Enable/Disable**", opts)
        if ed == "Enable" then
          if b.text:sub(-1) ~= "*" then b.text = b.text .. "*" end
          local ok, err = sv.enable(b.text:sub(1, -2))
          b.enabled = true
          if not ok then
            self.app.wm.notify(err)
          end
        elseif ed == "Disable" then
          if b.text:sub(-1) == "*" then b.text = b.text:sub(1, -2) end
          local ok, err = sv.disable(b.text)
          b.enabled = false
          if not ok then
            self.app.wm.notify(err)
          end
        end
      end
    }
    i = i + 1
  end

  self.pages[2] = item(self)

  self.pages[2]:add {
    x = 1, y = 2, text = "Name", foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color
  }
  self.pages[2]:add(tbox {
    x = 6, y = 2, w = 10, foreground = self.app.wm.cfg.bar_color,
    background = self.app.wm.cfg.text_focused, window = self, text = "",
    submit = function(_,text) self.pages[2].sname = text end
  })

  self.pages[2]:add {
    x = 17, y = 2, text = "File", foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color
  }
  self.pages[2]:add(tbox {
    x = 22, y = 2, w = 10, foreground = self.app.wm.cfg.bar_color,
    background = self.app.wm.cfg.text_focused, window = self, text = "",
    submit = function(_,text)
      if not fs.stat(text) then
        self.app.wm.notify("That file does not exist.")
      else
        self.pages[2].sfile = text
      end
    end
  })

  self.pages[2]:add {
    x = 1, y = 3, text = "script", foreground = self.app.wm.cfg.text_unfocused,
    background = self.app.wm.cfg.bar_color, click = function(b)
      self.pages[2].stype = "script"
      b.foreground = self.app.wm.cfg.text_focused
      self.pages[2].items[#self.pages[2].items - 1].foreground =
        self.app.wm.cfg.text_unfocused
    end
  }

  self.pages[2]:add {
    x = 8, y = 3, text = "service", foreground = self.app.wm.cfg.text_unfocused,
    background = self.app.wm.cfg.bar_color, click = function(b)
      self.pages[2].stype = "service"
      b.foreground = self.app.wm.cfg.text_focused
      self.pages[2].items[#self.pages[2].items - 2].foreground =
        self.app.wm.cfg.text_unfocused
    end
  }

  self.pages[2]:add {
    x = 17, y = 3, text = "Add", foreground = self.app.wm.cfg.text_focused,
    background = self.app.wm.cfg.bar_color, click = function(b)
      local pg = self.pages[2]
      if not (pg.stype and pg.sname and
          pg.sfile) then
        self.app.wm.notify("Missing name, file, or type")
      else
        local ok, err = sv.add(pg.stype, pg.sname, pg.sfile)
        if not ok then
          self.app.wm.notify(err)
        else
          services = sv.list()
        end
      end
    end
  }
end

function app:click(...)
  self.tab_bar:click(...)
  self.pages[self.page]:click(...)
end

function app:key(...)
  self.pages[self.page]:key(...)
end

function app:refresh()
  if not self.pages then self.app.init(self) end
  self.gpu.setBackground(self.app.wm.cfg.bar_color)
  self.gpu.fill(1, 1, self.app.w, self.app.h, " ")
  self.gpu.setBackground(0)
  self.gpu.fill(1, 1, self.app.w, 1, " ")
  if self.page == 1 then
    self.gpu.fill(3, 4, self.app.w - 4, self.app.h - 4, " ")
  end
  self.tab_bar:refresh()
  self.pages[self.page]:refresh()
end

return app
