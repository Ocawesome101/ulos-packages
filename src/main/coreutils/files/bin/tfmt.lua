-- coreutils: text formatter --

local text = require("text")

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help then
  io.stderr:write([[
usage: tfmt [options] FILE ...
Format FILE(s) according to a simple format
specification.

Options:
  --wrap=WD       Wrap output text at WD
                  characters.
  --output=FILE   Send output to file FILE.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local colors = {
  bold = "97",
  regular = "39",
  italic = "36",
  link = "94",
  file = "93",
  red = "91",
  green = "92",
  yellow = "93",
  blue = "94",
  magenta = "95",
  cyan = "96",
  white = "97",
  gray = "90",
}

local patterns = {
  {"%*({..-})", "bold"},
  {"%$({..-})", "italic"},
  {"@({..-})", "link"},
  {"#({..-})", "file"},
  {"red({..-})", "red"},
  {"green({..-})", "green"},
  {"yellow({..-})", "yellow"},
  {"blue({..-})", "blue"},
  {"magenta({..-})", "magenta"},
  {"cyan({..-})", "cyan"},
  {"white({..-})", "white"},
  {"gray({..-})", "gray"},
}

opts.wrap = tonumber(opts.wrap)

local output = io.output()
if opts.output and type(opts.output) == "string" then
  local handle, err = io.open(opts.output, "w")
  if not handle then
    io.stderr:write("tfmt: cannot open ", opts.output, ": ", err, "\n")
    os.exit(1)
  end

  output = handle
end

for i=1, #args, 1 do
  local handle, err = io.open(args[i], "r")
  if not handle then
    io.stderr:write("tfmt: ", args[i], ": ", err, "\n")
    os.exit(1)
  end
  local data = handle:read("a")
  handle:close()

  for i=1, #patterns, 1 do
    data = data:gsub(patterns[i][1], function(x)
      return string.format("\27[%sm%s\27[%sm", colors[patterns[i][2]],
        x:sub(2, -2), colors.regular)
    end)
  end

  if opts.wrap then
    data = text.wrap(data, opts.wrap)
  end

  output:write(data .. "\n")
  output:flush()
end

if opts.output then
  output:close()
end
