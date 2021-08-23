#!/usr/bin/env lua

local name, pat = ...

pat = "^" .. pat

io.write(string.format("[%q]={info={version=0,mtar=\"pkg/%s.mtar\"},files={",
  name, name))
for line in io.lines() do
	local file = line:gsub(pat, "")
	io.write("\"", file, "\",")
end
io.write("}},")
