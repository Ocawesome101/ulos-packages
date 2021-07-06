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
    out[#out+1] = tostring(select(2, data:gsub("\n", "")))
  end

  if opts.w then
    out[#out+1] = tostring(select(2, data:gsub("[ \n\t\r]+", "")))
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
