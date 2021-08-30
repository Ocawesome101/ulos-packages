-- terminal app --

local tty = require("tty")
local process = require("process")
local gpuproxy = require("gpuproxy")

if not osgui.ui.buffered then
  osgui.notify("this program requires GPU buffers")
  return
end

local app = {}

function app:init()
  self.buffer = osgui.gpu.allocateBuffer(65, 20)
  self.w = 65
  self.h = 20
  self.x = 10
  self.y = 5
  self.active = true
  self.gprox = gpuproxy.buffer(osgui.gpu, self.buffer)
  self.stream = tty.create(self.gprox)
  self.pid = process.spawn {
    name = "lsh",
    func = loadfile((os.getenv("SHELL") or "/bin/lsh")..".lua"),
    stdin = self.stream,
    stdout = self.stream,
    stderr = self.stream,
    input = self.stream,
    output = self.stream
  }
end

function app:key() end
function app:click() end

function app:focus() self.stream:write("\27?5c") self.stream:flush() end
function app:unfocus()self.stream:write("\27?15c")self.stream:flush()end

function app:close()
  process.kill(self.pid, process.signals.hangup)
  tty.delete(self.stream.tty)
  osgui.gpu.freeBuffer(self.buffer)
end

function app:refresh()
  osgui.gpu.bitblt(self.buf, 3, 2, nil, nil, self.buffer)
  if not process.info(self.pid) then
    self:close()
    self.closeme = true
  end
end

return osgui.window(app, "Terminal")
