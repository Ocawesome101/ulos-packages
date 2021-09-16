-- coreutils: less --

local text = require("text")
local termio = require("termio")

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help then
  io.stderr:write([[
usage: less FILE ...
Page through FILE(s).  They will be concatenated.
]])
  os.exit(1)
end

local lines = {}
local lcache = {}
local w, h = termio.getTermSize()
local scr = 0

local function scroll(down)
  if down then
    if scr+h < #lines then
      local n = math.min(#lines - h, scr + 4)
      if n > scr then
        io.write(string.format("\27[%dS", n - scr))
        for i=scr, scr + n, 1 do lcache[i + h] = false end
        scr = n
      end
    end
  elseif scr > 0 then
    local n = math.max(0, scr - 4)
    if n < scr then
      io.write(string.format("\27[%dT", scr - n))
      for i=scr - n - 3, scr, 1 do lcache[i] = false end
      scr = n
    end
  end
end

for i=1, #args, 1 do
  for line in io.lines(args[i], "l") do
    lines[#lines+1] = line
  end
end

if #lines < h - 1 then
  for i=1, #lines, 1 do
    io.write(lines[i] .. "\n")
  end
  io.write("\27[30;47mEND\27[m")
  repeat local k = termio.readKey() until k == "q"
  io.write("\27[G\27[2K")
  os.exit()
end

local function redraw()
  for i=1, h-1, 1 do
    if not lcache[scr+i] then
      lcache[scr+i] = true
      io.write(string.format("\27[%d;1H\27[2K%s", i, lines[scr+i] or ""))
    end
  end
end

io.write("\27[2J")
redraw()

local prompt = string.format("\27[%d;1H\27[2K:", h)
local lastpat = ""
io.write(prompt)
while true do
  local key, flags = termio.readKey()
  if key == "q" then
    io.write("\27[m\n")
    io.flush()
    os.exit(0)
  elseif key == "up" then
    scroll(false)
  elseif key == "down" then
    scroll(true)
  elseif key == " " then
    lcache = {}
    scr = math.min(scr + h, #lines - h)
  elseif key == "/" then
    io.write(string.format("\27[%d;1H/", h))
    local search = io.read("l")
    if #search > 0 then
      lastpat = search
    else
      search = lastpat
    end
    for i = math.max(scr, 1) + 1, #lines, 1 do
      if lines[i]:match(search) then
        scr = math.min(i, #lines - h)
        break
      end
    end
  end
  redraw()
  io.write(prompt)
end
