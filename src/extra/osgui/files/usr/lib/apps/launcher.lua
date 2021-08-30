-- app launcher

local fs = require("filesystem")

local app = {}

local function mkview(t)
  t = t or ""
  local apps = fs.list("/usr/lib/apps") or {}
  table.sort(apps)
  app.buttons = osgui.buttongroup()
  local skipped = 0
  for i=1, #apps, 1 do
    local a = apps[i]
    if a ~= "login.lua" and a ~= "launcher.lua" and a:match(t) then
      app.buttons:add {
        x = 3, y = 3 + i - skipped, text = a:gsub("%.lua$", ""), fg = 0,
        click = function()
          local app = osgui.dofile("/usr/lib/apps/"..a)
          osgui.ui.add(app)
        end
      }
    else
      skipped = skipped + 1
    end
  end
  if not app.h then
    app.h = #apps + 4 - skipped
  end
end

function app:init()
  self.x = 3
  self.y = 2
  self.w = 16
  mkview()
  self.textboxes = osgui.textboxgroup()
  self.textboxes:add {
    x = 3, y = 2, w = 12, bg = 0, fg = 0x888888,
    submit = function(t)
      mkview(t)
    end
  }
end

function app:refresh()
  self.buttons:draw(self)
  self.textboxes:draw(self)
end

function app:click(x,y)
  self.buttons:click(x, y)
  self.textboxes:click(x, y)
end

function app:key(k)
  self.textboxes:key(k)
end

function app:close()
  notify("You may not close the Launcher.")
  return "__no_keep_me_open"
end

return osgui.window(app, "Launcher")
