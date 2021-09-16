-- coreutils: passwd --

local sha = require("sha3").sha256
local acl = require("acls")
local users = require("users")
local process = require("process")

local n_args = select("#", ...)
local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: passwd [options] USER
   or: passwd [options]
Generate or modify users.

Options:
  -i, --info      Print the user's info and exit.
  --home=PATH     Set the user's home directory.
  --shell=PATH    Set the user's shell.
  --enable=P,...  Enable user ACLs.
  --disable=P,... Disable user ACLs.
  --clear-acls    Clear ACLs before applying
  --              '--enable'.
  -r, --remove    Remove the specified user.

Note that an ACL may only be set if held by the
current user.  Only root may delete users.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local current = users.attributes(process.info().owner).name
local user = args[1] or current

local _ok, _err = users.get_uid(user)
local attr
if not _ok then
  io.stderr:write("passwd: warning: " .. _err .. "\n")
  attr = {}
else
  local err
  attr, err = users.attributes(_ok)
  if not attr then
    io.stderr:write("passwd: failed getting attributes: " .. err .. "\n")
    os.exit(1)
  end
end

attr.home = opts.home or attr.home or "/home/" .. user
attr.shell = opts.shell or attr.shell or "/bin/lsh"
attr.uid = _ok
attr.name = attr.name or user

local acls = attr.acls or 0
attr.acls = {}
if not opts["clear-acls"] then
  for k, v in pairs(acl.user) do
    if acls & v ~= 0 then
      attr.acls[k] = true
    end
  end
end

if opts.i or opts.info then
  print("uid:   " .. attr.uid)
  print("name:  " .. attr.name)
  print("home:  " .. attr.home)
  print("shell: " .. attr.shell)
  local cacls = {}
  for k,v in pairs(attr.acls) do if v then cacls[#cacls+1] = k end end
  print("acls:  " .. table.concat(cacls, " | "))
  os.exit(0)
elseif opts.r or opts.remove then
  local ok, err = users.remove(attr.uid)
  if not ok then
    io.stderr:write("passwd: cannot remove user: ", err, "\n")
    os.exit(1)
  end
  os.exit(0)
end

if n_args == 0 or (args[1] and args[1] ~= current) then
  local pass
  repeat
    io.stderr:write("password for ", args[1] or current, ": \27[8m")
    pass = io.read()
    io.stderr:write("\27[0m\n")
    if #pass < 4 then
      io.stderr:write("passwd: password too short\n")
    end
  until #pass >= 4

  attr.pass = sha(pass):gsub(".", function(x)
    return string.format("%02x", x:byte()) end)
end

for a in (opts.enable or ""):gmatch("[^,]+") do
  attr.acls[a:upper()] = true
end

for a in (opts.disable or ""):gmatch("[^,]+") do
  attr.acls[a:upper()] = false
end

local function pc(f, ...)
  local result = table.pack(pcall(f, ...))
  if not result[1] and result[2] then
    io.stderr:write("passwd: ", result[2], "\n")
    os.exit(1)
  else
    return table.unpack(result, 2, result.n)
  end
end

local ok, err = pc(users.usermod, attr)

if not ok then
  io.stderr:write("passwd: ", err, "\n")
  os.exit(1)
end
