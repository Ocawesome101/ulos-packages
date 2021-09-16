-- lua REPL --

local args = table.pack(...)
local opts = {}

local readline = require("readline")

-- prevent some pollution of _G
local prog_env = {}
for k, v in pairs(_G) do prog_env[k] = v end

local exfile, exargs = nil, {}
local ignext = false
for i=1, #args, 1 do
  if ignext then
    ignext = false
  else
    if args[i] == "-e" and not exfile then
      opts.e = args[i + 1]
      if not opts.e then
        io.stderr:write("lua: '-e' needs argument\n")
        opts.help = true
        break
      end
      ignext = true
    elseif args[i] == "-l" and not exfile then
      local arg = args[i + 1]
      if not arg then
        io.stderr:write("lua: '-l' needs argument\n")
        opts.help = true
        break
      end
      prog_env[arg] = require(arg)
      ignext = true
    elseif (args[i] == "-h" or args[i] == "--help") and not exfile then
      opts.help = true
      break
    elseif args[i] == "-i" and not exfile then
      opts.i = true
    elseif args[i]:match("%-.+") and not exfile then
      io.stderr:write("lua: unrecognized option '", args[i], "'\n")
      opts.help = true
      break
    elseif exfile then
      exargs[#exargs + 1] = args[i]
    else
      exfile = args[i]
    end
  end
end

opts.i = #args == 0

if opts.help then
  io.stderr:write([=[
usage: lua [options] [script [args ...]]
Available options are:
  -e stat  execute string 'stat'
  -i       enter interactive mode after executing 'script'
  -l name  require library 'name' into global 'name'
  -v       show version information

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]=])
  os.exit(1)
end

if opts.e then
  local ok, err = load(opts.e, "=(command line)", "bt", prog_env)
  if not ok then
    io.stderr:write("lua: ", err, "\n")
    os.exit(1)
  else
    local result = table.pack(xpcall(ok, debug.traceback))
    if not result[1] and result[2] then
      io.stderr:write("lua: ", result[2], "\n")
      os.exit(1)
    elseif result[1] then
      print(table.unpack(result, 2, result.n))
    end
  end
end

opts.v = opts.v or opts.i
if opts.v then
  if _VERSION == "Lua 5.2" then
    io.write(_VERSION, "  Copyright (C) 1994-2015 Lua.org, PUC-Rio\n")
  else
    io.write(_VERSION, "  Copyright (C) 1994-2020 Lua.org, PUC-Rio\n")
  end
end

if exfile then
  local ok, err = loadfile(exfile, "t", prog_env)
  if not ok then
    io.stderr:write("lua: ", err, "\n")
    os.exit(1)
  end
  local result = table.pack(xpcall(ok, debug.traceback,
    table.unpack(exargs, 1, #exargs)))
  if not result[1] and result[2] then
    io.stderr:write("lua: ", result[2], "\n")
    os.exit(1)
  end
end

if opts.i or (not opts.e and not exfile) then
  local hist = {}
  local rlopts = {history = hist}
  while true do
    io.write("> ")
    local eval = readline(rlopts)
    hist[#hist+1] = eval
    local ok, err = load("return "..eval, "=stdin", "bt", prog_env)
    if not ok then
      ok, err = load(eval, "=stdin", "bt", prog_env)
    end
    if not ok then
      io.stderr:write(err, "\n")
    else
      local result = table.pack(xpcall(ok, debug.traceback))
      if not result[1] and result[2] then
        io.stderr:write(result[2], "\n")
      elseif result[1] then
        print(table.unpack(result, 2, result.n))
      end
    end
  end
end
