local args, options = require("argutil").parse(...)
local process = require("process")
local filesystem = require("filesystem")
local component = require("component")

if #args == 0 or options.help then
    print("usage: flash [OPTIONS] <FILE> [EEPROM NAME]")
    return 0
elseif process.info().owner ~= 0 then
    print("You must be root to flash EEPROMs.")
    return 1
end

local eeprom
do
    local address = component.list("eeprom")()
    if not address then
        print("No EEPROM found.")
        return 1
    end
    eeprom = component.proxy(address)
end

local absolute_path = args[1]:sub(1,1) == "/" and args[1] or os.getenv("PWD") .. "/" .. args[1]

if filesystem.stat(absolute_path).size > eeprom.getSize() then
    print("File is too large to fit in EEPROM.")
    return 1
end

local rom_file, err = filesystem.open(absolute_path, "r")
if not rom_file then
    print(("Could not open %s for reading: %s"):format(absolute_path, err))
    return 1
end

print("Put the EEPROM you want to flash into the computer and press enter to start.")

repeat
    local signal = {coroutine.yield()}
until signal[1] == "key_down" and signal[4] == 28

print("Flashing EEPROM...")
eeprom.set(rom_file:read(filesystem.stat(absolute_path).size))
rom_file:close()

if args[2] then
    print("Setting EEPROM name...")
    eeprom.setLabel(args[2])
end

print("Done.")
