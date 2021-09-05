-- stub that executes other shells
local shells = {"/bin/bsh", "/bin/lsh"}
local fs = require("filesystem")
for i, shell in ipairs(shells) do
  if fs.stat(shell..".lua") then
    assert(loadfile(shell .. ".lua"))()
    os.exit(0)
  end
end
io.stderr:write("sh: no shell found\n")
os.exit(1)
