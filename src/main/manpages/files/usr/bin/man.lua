-- manpages: man --

local fs = require("filesystem")
local tio = require("termio")

local w, h = tio.getTermSize()

local page_path = "/usr/man/%d/%s"

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help then
  io.stderr:write("usage: man [SECTION] PAGE\n")
  os.exit(1)
end

-- section search order
local sections = {1, 3, 2, 5, 4, 6, 7}

local section, page

if #args == 1 then
  page = args[1]
elseif tonumber(args[1]) then
  section = tonumber(args[1])
  page = args[2]
else
  page = args[1]
end

if section then table.insert(sections, 1, section) end

for i, section in ipairs(sections) do
  local try = string.format(page_path, section, page)
  if fs.stat(try) then
    os.remove("/tmp/manfmt")
    os.execute("tfmt --output=/tmp/manfmt --wrap=" .. w .. " " .. try)
    os.execute("less /tmp/manfmt")
    os.exit(0)
  end
end

io.stderr:write(page .. ": page not found in any section\n")
os.exit(1)
