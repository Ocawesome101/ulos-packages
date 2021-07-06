-- cat --

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: cat FILE1 FILE2 ...
Concatenate FILE(s) to standard output.  With no
FILE, or where FILE is -, read standard input.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(0)
end

if #args == 0 then
  args[1] = "-"
end

for i=1, #args, 1 do
  local handle, err

  if args[i] == "-" then
    handle, err = io.input(), "missing stdin"
  else
    handle, err = io.open(require("path").canonical(args[i]), "r")
  end
  
  if not handle then
    io.stderr:write("cat: cannot open '", args[i], "': ", err, "\n")
    os.exit(1)
  else
    for line in handle:lines("L") do
      io.write(line)
    end
    if handle ~= io.input() then handle:close() end
  end
end
