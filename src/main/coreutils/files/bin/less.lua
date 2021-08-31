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
local w, h = termio.getTermSize()
local scr = 0

local function scroll(n)
  if n then
    if scr+h < #lines then
      scr=scr+1
    end
  elseif scr > 0 then
    scr=scr-1
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
  io.write("\27[1;1H")
  for i=1, h-1, 1 do
    io.write("\27[2K", lines[scr+i] or "", "\n")
  end
end

io.write("\27[2J")
redraw()

local prompt = string.format("\27[%d;1H\27[2K:", h)

io.write(prompt)
while true do
  local key, flags = termio.readKey()
  if key == "c" and flags.control then
    -- interrupted
    io.write("interrupted\n")
    os.exit(1)
  elseif key == "q" then
    io.write("\27[2J\27[1;1H")
    io.flush()
    os.exit(0)
  elseif key == "up" then
    scroll(false)
  elseif key == "down" then
    scroll(true)
  elseif key == " " then
    scr=math.min(scr+h, #lines - h - 1)
  elseif key == "/" then
    local search = io.read()
  end
  redraw()
  io.write(prompt)
end
