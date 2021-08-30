-- file browser app

local fs = require("filesystem")

local app = {}

local function prompt(f)
  f = f:gsub("[/\\]+", "/")
  local new = {}

  function new:init()
    self.x = app.x + 10
    self.y = app.y + 5
    self.w = 24
    self.h = 5
    self.labels = osgui.labelgroup()
    self.buttons = osgui.buttongroup()
    self.labels:add {
      x = 3, y = 2, fg = 0x000000, text = "What do you want to"
    }
    self.labels:add {
      x = 3, y = 3, fg = 0x000000, text = "do with this file?"
    }
    self.buttons:add {
      x = 3, y = 5, bg = 0x000000, fg = 0x888888, text = "Execute",
      click = function()
        local app = osgui.dofile(f)
        if app then osgui.ui.add(app) end
        self.closeme = true
      end
    }
  end
  
  function new:refresh()
    self.labels:draw(self)
    self.buttons:draw(self)
  end
  
  function new:click(x,y)
    self.buttons:click(x,y)
  end
  
  function new:key()
  end
  
  function new:close()
  end
  
  ui.add(window(new, f))
end

local function mkfolderview(f)
  local buttons = osgui.buttongroup()
  local files = fs.list(f) or {}
  for i, file in ipairs(files) do
    buttons:add {
      x = 3, y = i + 3,
      text = file,
      click = function()
        if fs.isDirectory(f .. "/" .. file) then
          _G.CD = (f.."/"..file):gsub("[/\\]+", "/")
          osgui.ui.add(dofile("/apps/browser.lua"))
          _G.CD = nil
        else
          prompt(f.."/"..file)
        end
      end
    }
  end
  if not app.h then
    app.h = #files + 4
  end
  return buttons
end

function app:init()
  self.x = 10
  self.y = 5
  self.w = 64
  self.labels = osgui.labelgroup()
  self.labels:add {
    x = 3, y = 2, fg = 0x000000, text = "Path:"
  }
  self.textboxes = osgui.textboxgroup()
  self.textboxes:add {
    x = 8, y = 2, w = 52, fg = 0x888888, bg = 0x000000,
    text = CD or "/", submit = function(text)
      if fs.exists(text) then
        self.files = mkfolderview(text)
      end
    end
  }
  self.files = mkfolderview(CD or "/")
  self.navigation = osgui.buttongroup()
  self.navigation:add {
    x = 62, y = 2, fg = 0x888888, bg = 0x000000,
    text = "^", click = function()
      local fp = self.textboxes.boxes[1].text
      if fp == "/" then return end
      self.closeme = true
      fp = fp:gsub("^/.+/(.+/?)$", "")
      if fp == "" then fp = "/" end
      self.files = mkfolderview(fp)
      self.textboxes.boxes[1].text = fp
    end
  }
end

function app:refresh()
  self.labels:draw(self)
  self.files:draw(self)
  self.navigation:draw(self)
  self.textboxes:draw(self)
end

function app:key(k)
  self.textboxes:key(k)
end

function app:click(x, y)
  self.navigation:click(x, y)
  self.textboxes:click(x, y)
  self.files:click(x, y)
end

return osgui.window(app, "File Browser")
