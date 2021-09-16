-- coreutils: lshw --

local computer = require("computer")

local args, opts = require("argutil").getopt({
  exit_on_bad_opt = true,
  allow_finish = true,
  options = {
    o = false, openos = false,
    f = false, full = false,
    F = true,  filter = true,
    c = false, class = false,
    C = false, capacity = false,
    d = false, description = false,
    p = false, product = false,
    w = false, width = false,
    v = false, vendor = false,
    h = false, help = false
  }
}, ...)

if opts.h or opts.help then
  io.stderr:write([[
usage: lshw [options] [address|type] ...
List information about the components installed in
a computer.  If no options are specified, defaults
to -fCcdpwvs.
  -o,--openos       Print outputs like OpenOS's
                    'components' command
  -f,--full         Print full output for every
                    component
  -F,--filter CLASS Filter for this class of component
  -c,--class        Print class information
  -C,--capacity     Print capacity information
  -d,--description  Print descriptions
  -p,--product      Print product name
  -w,--width        Print width information
  -v,--vendor       Print vendor information
  -s,--clock        Print clock rate.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(0)
end

if opts.f or opts.full or not next(opts) then
  for _, opt in ipairs {"f","C","c","d","p","w","v","s"} do
    opts[opt] = true
  end
end

local ok, info = pcall(computer.getDeviceInfo)
if not ok and info then
  io.stderr:write("lshw: computer.getDeviceInfo: ", info, "\n")
  os.exit(1)
end

local function read_file(addr, f)
  local handle, err = io.open(f, "r")
  if not handle then
    return info[addr].class
  end
  local data = handle:read("a")
  handle:close()
  return data
end

local field_filter = {
  capacity = opts.C or opts.capacity,
  description = opts.d or opts.description,
  product = opts.p or opts.product,
  width = opts.w or opts.width,
  vendor = opts.v or opts.vendor,
  clock = opts.s or opts.clock,
  class = opts.c or opts.class
}

local function print_information(address)
  if opts.F or opts.filter then
    if info[address].class ~= (opts.F or opts.filter) then
      return
    end
  end
  local info = info[address]
  if opts.o or opts.openos then
    print(address:sub(1, 13).."...  " ..
      read_file(address,
        "/sys/components/by-address/" .. address:sub(1,6) .. "/type"))
    return
  end
  print(address)
  for k, v in pairs(info) do
    if field_filter[k] then
      if not tonumber(v) then v = string.format("%q", v) end
      print("  " .. k .. ": " .. v)
    end
  end
end

if opts.o or opts.openos then
  print("ADDRESS           TYPE")
end

for k in pairs(info) do
  if #args > 0 then
    for i=1, #args, 1 do
      if args[i] == k:sub(1, #args[i]) then
        print_information(k)
        break
      elseif read_file(k, "/sys/components/by-address/" .. k:sub(1,6)
          .. "/type") == args[i] then
        print_information(k)
        break
      end
    end
  else
    print_information(k)
  end
end
