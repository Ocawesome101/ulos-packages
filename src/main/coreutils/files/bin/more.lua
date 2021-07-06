-- coreutils: more --

local text = require("text")
local termio = require("termio")

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help then
  io.stderr:write([[
usage: more FILE ...
Page through FILE(s).  Similar to less(1), but
slower.
]])
  os.exit(1)
end

local written = 0

local w, h = termio.getTermSize()

local prompt = "\27[30;47m--MORE--\27[39;49m"

local function chw()
  if written >= h - 2 then
    io.write(prompt)
    repeat
      local key = termio.readKey()
      if key == "q" then io.write("\n") os.exit(0) end
    until key == " "
    io.write("\27[2K")
    written = 0
  end
end

local function wline(l)
  local lines = text.wrap(l, w)
  while #lines > 0 do
    local nextnl = lines:find("\n")
    if nextnl then
      local ln = lines:sub(1, nextnl)
      lines = lines:sub(#ln + 1)
      written = written + 1
      io.write(ln)
    else
      written = written + 1
      lines = ""
      io.write(lines)
    end
    chw()
  end
end

local function read(f)
  local handle, err = io.open(f, "r")
  if not handle then
    io.stderr:write(f, ": ", err, "\n")
    os.exit(1)
  end

  local data = handle:read("a")
  
  handle:close()

  wline(data)
end

for i=1, #args, 1 do
  read(args[i])
end

