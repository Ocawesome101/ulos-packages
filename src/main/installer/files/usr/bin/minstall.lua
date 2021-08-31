-- install to a writable medium. --

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: install
Install ULOS to a writable medium.

ULOS Installer (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local component = require("component")
local computer = require("computer")

local fs = {}
do
  local _fs = component.list("filesystem")

  for k, v in pairs(_fs) do
    if k ~= computer.tmpAddress() then
      fs[#fs+1] = k
    end
  end
end

print("Available filesystems:")
for k, v in ipairs(fs) do
  print(string.format("%d. %s", k, v))
end

print("Please input your selection.")

local choice
repeat
  io.write("> ")
  choice = io.read("l")
until fs[tonumber(choice) or 0]

os.execute("mount -u /mnt")
os.execute("mount " .. fs[tonumber(choice)] .. " /mnt")

local online, full = false, false
if component.list("internet")() then
  io.write("Perform an online installation? [Y/n]: ")
  local choice
  repeat
    io.write(choice and "Please enter 'y' or 'n': " or "")
    choice = io.read():gsub("\n", "")
  until choice == "y" or choice == "n" or choice == ""
  online = (choice == "y" or #choice == 0)
  if online then
    io.write("Install the full system (manual pages, TLE)?  [Y/n]: ")
    local choice
    repeat
      io.write(choice and "Please enter 'y' or 'n': " or "")
      choice = io.read():gsub("\n", "")
    until choice == "y" or choice == "n" or choice == ""
    full = (choice == "y" or #choice == 0)
    if full then
      print("Installing the full system from the internet")
    else
      print("Installing the base system from the internet")
    end
  else
    print("Copying the system from the installer medium")
  end
else
  print("No internet card installed, defaulting to offline installation")
end

if online then
  os.execute("upm update --root=/mnt")
  local pklist = {
    "cldr",
    "cynosure",
    "usysd",
    "coreutils",
    "corelibs",
    "upm",
  }
  if full then
    pklist[#pklist+1] = "tle"
    pklist[#pklist+1] = "manpages"
  end
  os.execute("upm install -fy --root=/mnt " .. table.concat(pklist, " "))
else
-- TODO: do this some way other than hard-coding it
  local dirs = {
    "bin",
    "etc",
    "lib",
    "sbin",
    "usr",
    "init.lua", -- copy this last for safety reasons
  }

  for i, dir in ipairs(dirs) do
    os.execute("cp -rv /"..dir.." /mnt/"..dir)
  end

  os.execute("rm /mnt/bin/install.lua")
end

print("The base system has now been installed.")

os.execute("mkpasswd -i /mnt/etc/passwd")
os.execute("hnsetup")
