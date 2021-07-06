-- coreutils: sudo --

local users = require("users")
local process = require("process")

local args = table.pack(...)

local uid = 0
if args[1] and args[1]:match("^%-%-uid=%d+$") then
  uid = tonumber(args[1]:match("uid=(%d+)")) or 0
  table.remove(args, 1)
end

if #args == 0 then
  io.stderr:write([[
sudo: usage: sudo [--uid=UID] COMMAND
Executes COMMAND as root or the specified UID.
]])
  os.exit(1)
end

local password
repeat
  io.write("password: \27[8m")
  password = io.read()
  io.write("\27[0m\n")
until #password > 0

local ok, err = users.exec_as(uid,
  password, function() os.execute(table.concat(args, " ")) end, args[1], true)

if ok ~= 0 and err ~= "__internal_process_exit" then
  io.stderr:write(err, "\n")
  os.exit(ok)
end
