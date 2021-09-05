-- coreutils: echo --
-- may be overridden by the shell --

local args = {...}

for i=1, #args, 1 do
  args[i] = tostring(args[i])
end

print(table.concat(args, " "))
