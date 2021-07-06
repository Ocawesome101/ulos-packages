-- cynosure loader --

local fs = component.proxy(computer.getBootAddress())
local gpu = component.proxy(component.list("gpu", true)())
gpu.bind(gpu.getScreen() or (component.list("screen", true)()))
gpu.setResolution(50, 16)
local b, w = 0, 0xFFFFFF
gpu.setForeground(b)
gpu.setBackground(w)
gpu.set(1, 1, "            Cynosure Kernel Loader v1             ")
gpu.setBackground(b)
gpu.setForeground(w)

local function readFile(f, p)
  local handle
  if p then
    handle = fs.open(f, "r")
    if not handle then return "" end
  else
    handle = assert(fs.open(f, "r"))
  end
  local data = ""
  repeat
    local chunk = fs.read(handle, math.huge)
    data = data .. (chunk or "")
  until not chunk
  fs.close(handle)
  return data
end

local function status(x, y, t, c)
  if c then gpu.fill(1, y+1, 50, 1, " ") end
  gpu.set(x, y+1, t)
end

status(1, 1, "Reading configuration")

local cfg = {}
do
  local data = readFile("/boot/cldr.cfg", true)
  for line in data:gmatch("[^\n]+") do
    local word, arg = line:gmatch("([^ ]+) (.+)")
    if word and arg then cfg[word] = tonumber(arg) or arg end
  end

  local flags = cfg.flags or "root=UUID="..computer.getBootAddress()
  cfg.flags = {}
  for word in flags:gmatch("[^ ]+") do
    cfg.flags[#cfg.flags+1] = word
  end
  cfg.path = cfg.path or "/boot/cynosure.lua"
end

status(1, 2, "Loading kernel from " .. cfg.path)
status(1, 3, "Kernel flags: " .. table.concat(cfg.flags, " "))

assert(load(readFile(cfg.path), "="..cfg.path, "t", _G))(table.unpack(cfg.flags))
