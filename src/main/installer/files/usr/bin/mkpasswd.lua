-- mkpasswd: generate a /etc/passwd file --

local acl = require("acls")
local sha = require("sha3").sha256
local readline = require("readline")
local acls = {}
do
  local __acls, __k = {}, {}
  for k, v in pairs(acl.user) do
    __acls[#__acls + 1] = v
    __k[v] = k
  end
  table.sort(__acls)
  for i, v in ipairs(__acls) do
    acls[i] = {__k[v], v}
  end
end

local args, opts = require("argutil").parse(...)

if #args < 1 or opts.help then
  io.stderr:write([[
usage: mkpasswd OUTPUT
Generate a file for use as /etc/passwd.  Writes
the generated file to OUTPUT.  Will not behave
correctly on a running system;  use passwd(1)
instead.

ULOS Installer copyright (c) 2021 Ocawesome101
under the DSLv2.
]])
  os.exit(1)
end

-- passwd line format:
-- uid:username:passwordhash:acls:homedir:shell

local function hex(dat)
  return dat:gsub(".", function(c) return string.format("%02x", c:byte()) end)
end

local function prompt(txt, opts, default)
  print(txt)
  local c
  if opts then
    repeat
      io.write("-> ")
      c = readline()
    until opts[c] or c == ""
    if c == "" then return default or opts.default end
  else
    repeat
      io.write("-> ")
      c = readline()
    until (default and c == "") or #c > 0
    if c == "" then return default end
  end
  return c
end

local function pwprompt(text)
  local ipw = ""
  repeat
    io.write(text or "password: ", "\27[8m")
    ipw = io.read("l")
  until #ipw > 1
  io.write("\27[28m\n")
  return hex(sha(ipw))
end

local prompts = {
  main = {
    text = "Available actions:\
  \27[96m[C]\27[37mreate a new user\
  \27[96m[l]\27[37mist created users\
  \27[96m[e]\27[37mdit a created user\
  \27[96m[w]\27[37mrite file and exit",
    opts = {c=true,l=true,e=true,w=true,default="c"}
  },
  uattr = {
    text = "Change them?\
  \27[96m[N]\27[37mo, continue\
  \27[96m[u]\27[37m - change username\
  \27[96m[a]\27[37m - change ACLs\
  \27[96m[s]\27[37m - set login shell\
  \27[96m[h]\27[37m - set home directory",
    opts = {n=true,u=true,i=true,a=true,c=true,d=true,s=true,h=true,default="n"}
  },
}

local function getACLs()
  io.write("ACL map:\n")
  for i, v in ipairs(acls) do
    io.write(string.format("  %d) %s\n", i, v[1]))
  end
  local inp = "A"
  while inp:match("[^%d,]") do
    inp = prompt("Enter a comma-separated list (e.g. 1,2,5,9)")
  end
  local n = 0
  for _n in inp:gmatch("[^,]+") do
    n = n | acls[tonumber(_n)][2]
  end
  return n
end

print("ULOS Installer Account Setup Utility v0.5.0 (c) Ocawesome101 under the DSLv2.")

local added = {
  [0] = {
    0,
    "root",
    (function() return pwprompt(
      "Enter a root password for the new system: ") end)(),
    8191,
    "/root",
    "/bin/lsh.lua"
  }
}

local function getAttributes()
  local uid = #added + 1
  local name = prompt("Enter a username")
  local pass = pwprompt("New password: ")
  local acls = getACLs()
  local homedir = "/home/"..name
  homedir = prompt("Set home directory [" .. homedir .. "]", nil, homedir)
  shell = "/bin/lsh.lua"
  return {uid, name, pass, acls, homedir, shell}
end

local function modAttributes(uid)
  local attr = added[uid]
  while true do
    print("Attributes for "..uid..": [" .. table.concat(attr, ", ", 2) .. "]")
    local opt = prompt(prompts.uattr.text, prompts.uattr.opts)
    if opt == "n" then return
    elseif opt == "u" then
      attr[2] = prompt("New username:")
    elseif opt == "a" then
      attr[4] = getACLs()
    elseif opt == "s" then
      attr[6] = prompt("Enter the absolute path of a shell (ex. /bin/lsh.lua)",
        nil, "/bin/lsh.lua")
    elseif opt == "h" then
      attr[5] = prompt("Enter a new home directory", nil, attr[5])
    end
  end
end

while true do
  local opt = prompt(prompts.main.text, prompts.main.opts)
  if opt == "c" then
    local attr = getAttributes()
    added[attr[1]] = attr
    modAttributes(attr[1])
  elseif opt == "l" then
    for i=0, #added, 1 do
      print(string.format("UID %d has name %s", i, added[i][2]))
    end
  elseif opt == "e" then
    local uid
    repeat
      io.write("UID: ")
      uid = tonumber(io.read("l"))
    until uid
    if not added[uid] then
      print("UID not added")
    else
      modAttributes(uid)
    end
  elseif opt == "w" then
    break
  end
end

print("Saving changes to " .. args[1])
local handle = assert(io.open(args[1], "w"))
for i=0, #added, 1 do
  print("Writing user data for " .. added[i][2])
  handle:write(string.format("%d:%s:%s:%d:%s:%s\n",
    table.unpack(added[i])))
  if opts.i then
    os.execute("mkdir -p " .. added[i][5])
  end
end
print("Done!")
