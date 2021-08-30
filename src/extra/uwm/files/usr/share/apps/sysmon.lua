-- system monitor app --

local computer = require("computer")
local process = require("process")
local size = require("size")

local app = {
  w = 40,
  h = 8,
  active = true,
  name = "System Monitor"
}

local cx, cy = 1, 1
local last_ref = 0
local timeout = 5
local instat = " 1   2   3   4  [5]"
function app:refresh(gpu)
  if computer.uptime() - last_ref >= timeout then
    gpu.setBackground(self.app.wm.cfg.bar_color)
    gpu.setForeground(self.app.wm.cfg.text_focused)
    gpu.fill(1, 1, self.app.w, self.app.h, " ")
    local gpu_mem = string.format("GPU Memory: %s used/%s total",
      size.format(gpu.totalMemory() - gpu.freeMemory()),
      size.format(gpu.totalMemory()))
    local pc_mem = string.format("Main Memory: %s used/%s total",
      size.format(computer.totalMemory() - computer.freeMemory()),
      size.format(computer.totalMemory()))
    local processes = string.format("Processes: %d", #process.list())
    gpu.set(1, 1, pc_mem)
    gpu.set(1, 2, gpu_mem)
    gpu.set(1, 3, processes)
    last_ref = computer.uptime()
  end
  gpu.set(1, self.app.h, "Interval: " .. instat)
end

function app:click(x, y)
  if y == self.app.h then
    if x > 10 and x < 14 then
      instat = "[1]  2   3   4   5 "
      timeout = 1
    elseif x > 14 and x < 18 then
      instat = " 1  [2]  3   4   5 "
      timeout = 2
    elseif x > 18 and x < 22 then
      instat = " 1   2  [3]  4   5 "
      timeout = 3
    elseif x > 22 and x < 26 then
      instat = " 1   2   3  [4]  5 "
      timeout = 4
    elseif x > 26 and x < 30 then
      instat = " 1   2   3   4  [5]"
      timeout = 5
    end
  end
end

return app
