-- coreutils: wc --

local path = require("path")

local args, opts = require("argutil").parse(...)

if opts.help or #args == 0 then
  io.stderr:write([[
usage: wc [-lcw] FILE ...
Print line, word, and character (byte) counts from
all FILEs.

Options:
  -c  Print character counts.
  -l  Print line counts.
  -w  Print word counts.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

if not (opts.l or opts.w or opts.c) then
  opts.l = true
  opts.w = true
  opts.c = true
end

local function wc(f)
  local handle, err = io.open(f, "r")
  if not handle then
    return nil, err
  end

  local data = handle:read("a")
  handle:close()

  local out = {}

  if opts.l then
    local last = 0
    local val = 0
    while true do
      local nex = data:find("\n", last)
      if not nex then break end
      val = val + 1
      last = nex + 1
    end
    out[#out+1] = tostring(val)
  end

  if opts.w then
    local last = 0
    local val = 0
    while true do
      local nex, nen = data:find("[ \n\t\r]+", last)
      if not nex then break end
      val = val + 1
      last = nen + 1
    end
    out[#out+1] = tostring(val)
  end

  if opts.c then
    out[#out+1] = tostring(#data)
  end

  return out
end

for i=1, #args, 1 do
  local ok, err = wc(path.canonical(args[i]))
  if not ok then
    io.stderr:write("wc: ", args[i], ": ", err, "\n")
    os.exit(1)
  else
    io.write(table.concat(ok, " "), " ", args[i], "\n")
  end
end
