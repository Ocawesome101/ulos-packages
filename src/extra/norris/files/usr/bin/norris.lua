local net = require("network")

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: norris
Prints a random Chuck Norris joke from the
internet.  ]].."\27[91mCW: These jokes are unfiltered and may\
be offensive to some people, or not safe for work,\
or not suitable for children.\27[39m\n"..[[

Copyright (c) 2021 Ocawesome101 under the DSLv2.
]])
  os.exit(1)
end

local handle, err = net.request("http://api.icndb.com/jokes/random")
if not handle then io.stderr:write("cnjoke: " .. err .. "\n") os.exit(1) end

local data = ""
for i=1, 4, 1 do
  local chunk = handle:read(2048)
  if chunk then data = data .. chunk end
end
handle:close()

local joke = data:match('"joke": "(.-)"'):gsub("&quot;", '"')
print(joke)
