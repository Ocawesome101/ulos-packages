-- wget --

local network = require("network")

local args, opts = require("argutil").getopt({
  h = false, help = false,
  O = true,  output = true
}, ...)

local function usage(s)
  io.stderr:write([[
usage: wget [options ...] url [...]
A non-interactive network file retrieval utility.

Options:
  -h,--help           Print usage information and
                      exit.
  -O,--output FILE    Output downloaded data to
                      FILE rather than to the
                      automatically detected file
                      name.

ULOS WGet copyright (c) 2021 Ocawesome101 under
the DSLv2.
]])
  os.exit(s and 0 or 1)
end

opts.help = opts.h
opts.output = opts.output or opts.O
if #args == 0 or opts.help then
  usage(opts.help)
end

for i=1, #args, 1 do
  local url = args[i]

  local segments = require("path").split(url)
  opts.output = opts.output or segments[#segments]

  print("Downloading " .. url .. " as " .. opts.output)
  
  local handle, err = io.open(opts.output, "w")
  if not handle then
    io.stderr:write("wget: ", opts.output, ": ", err, "\n")
    os.exit(1)
  end

  local stream, err = network.request(url)
  if not stream then
    handle:close()
    io.stderr:write("wget: ", url, ": ", err, "\n")
    os.exit(1)
  end

  for chunk in function() return stream:read(2048) end do
    handle:write(chunk)
  end

  stream:close()
  handle:close()
end
