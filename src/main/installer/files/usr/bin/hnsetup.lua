-- hnsetup: set system hostname during installation --

local hn
repeat
  io.write("Enter a hostname for the installed system: ")
  hn = io.read("l")
until #hn > 0

local handle = assert(io.open("/mnt/etc/hostname", "w"))
print("Setting installed system's hostname to " .. hn)
handle:write(hn)
handle:close()
