-- notifications, prompts, errors, oh my!

local computer = require("computer")

local app = {}

function app:init()
  local w, h = osgui.gpu.getResolution()
  self.x = (w // 2 - #self.text // 2 - 2)
  self.y = (h // 2 - 2)
  self.w = #self.text + 4
  self.h = 4
  self.age = computer.uptime()
end

function app:refresh()
  local x, y = self.x, self.y
  if osgui.ui.buffered then x = 1 y = 1 end
  if not (osgui.ui.buffered and self.refreshed) then
    osgui.gpu.setBackground(self.bg or 0x888888)
    osgui.gpu.fill(x, y, self.w, self.h, " ")
    osgui.gpu.setForeground(0x000000)
    osgui.gpu.set(x + 2, y + 1, self.text)
    self.refreshed = true
  end
  if computer.uptime() - self.age >= 10 then -- stick around for !>10s
    self.closeme = true
  end
end

function app:key()
end

function app:click()
end

function app:close()
end

function osgui.notify(notif)
  computer.beep(400, 0.2)
  osgui.ui.add(setmetatable({text = "/!\\ " .. notif}, {__index = app}))
end

-- override syserror

local oserr = syserror
local erroring = false
function osgui.syserror(err)
  if erroring then osgui.oserr(err) end
  erroring = true
  computer.beep(200, 0.5)
  osgui.ui.add(setmetatable({
    text="(X) " .. err, bg = 0x444444}, {__index = app}))
  erroring = false
end

-- add global prompt function

local papp = {}

function papp:init()
  local w, h = osgui.gpu.getResolution()
  self.x = (w // 2) - (#self.text // 2) - 2
  self.y = (h // 2) - 3
  self.w = #self.text + 4
  self.h = 5
  self.labels = labelgroup()
  self.labels:add {
    x = 3, y = 2, fg = 0, text = self.text
  }
  if self.mode == "text" then
    self.textbox = osgui.textboxgroup()
    self.textbox:add {
      x = 3,
      y = 3,
      w = #self.text,
      bg = 0x000000,
      fg = 0x888888,
      submit = function(text)
        self.returned = text
        self.closeme = true
      end
    }
  elseif self.mode == "button" then
    self.buttons = self.btn
  end
end

function papp:refresh()
  self.labels:draw(self)
  if self.textbox then self.textbox:draw(self) end
  if self.buttons then self.buttons:draw(self) end
end

function papp:click(x,y)
  if self.textbox then self.textbox:click(x,y) end
  if self.buttons then self.buttons:click(x,y) end
end

function papp:key(k)
  if self.textbox then self.textbox:key(k) end
end

function papp:close()
  return "__no_keep_me_open"
end

function osgui.prompt(mode, text, btn)
  local new = window(
    setmetatable({text=text,mode=mode,buttons=btn}, {__index = papp}),
    "Prompt"
  )
  osgui.ui.add(new)
  return {
    poll = function()
      if new.returned then
        return new.returned
      elseif new.closeme then
        return nil
      else
        return true
      end
    end
  }
end
