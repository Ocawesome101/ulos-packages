-- terminal app --

local tty = require("tty")
local process = require("process")

local shell = (require("config").table:load(os.getenv("HOME").."/.uwmterm.cfg")
  or require("config").table:load("/etc/uwmterm.cfg")
  or {shell = "/bin/lsh"}).shell

local app = {
  name = "Terminal"
}

function app:refresh(gpu)
  if not self.app.pid then
    local shell, err = loadfile((shell or os.getenv("SHELL") or "/bin/lsh")
      .. ".lua")
    if not shell then
      self.app.refresh = function(s, g)
        g.set(1, 1, "shell load: " .. err)
      end
    end
    self.app.stream = tty.create(gpu)
    self.app.pid = process.spawn {
      name = "[terminal]",
      func = shell,
      stdin  = self.app.stream,
      stdout = self.app.stream,
      stderr = self.app.stream,
      input  = self.app.stream,
      output = self.app.stream
    }
  elseif not process.info(self.app.pid) then
    tty.delete(self.app.stream.tty)
    self.closeme = true
  end
end

function app:focus()
  if self.app.stream then self.app.stream:write("\27?5c") end
end

function app:unfocus()
  if self.app.stream then self.app.stream:write("\27?15c") end
end

function app:close()
  process.kill(self.app.pid, process.signals.hangup)
  tty.delete(self.app.stream.tty)
end

return app
