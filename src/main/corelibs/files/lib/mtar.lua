-- mtar library --

local path = require("path")

local stream = {}

local formats = {
  [0] = { name = ">I2", len = ">I2" },
  [1] = { name = ">I2", len = ">I8" },
}

function stream:writefile(name, data)
  checkArg(1, name, "string")
  checkArg(2, data, "string")
  if self.mode ~= "w" then
    return nil, "cannot write to read-only stream"
  end

  return self.base:write(string.pack(">I2I1", 0xFFFF, 1)
    .. string.pack(formats[1].name, #name) .. name
    .. string.pack(formats[1].len, #data) .. data)
end

function stream:close()
  self.base:close()
end

local mtar = {}

-- this is Izaya's MTAR parsing code because apparently mine sucks
-- however, this is re-indented in a sane way, with argument checking added
function mtar.unarchive(stream)
  checkArg(1, stream, "FILE*")
  local remain = 0
  local function read(n)
    local rb = stream:read(math.min(n,remain))
    if remain == 0 or not rb then
      return nil
    end
    remain = remain - rb:len()
    return rb
  end
  return function()
    while remain > 0 do
      remain=remain-#(stream:read(math.min(remain,2048)) or " ")
    end
    local version = 0
    local nd = stream:read(2) or "\0\0"
    if #nd < 2 then return end
    local nlen = string.unpack(">I2", nd)
    if nlen == 0 then
      return
    elseif nlen == 65535 then -- versioned header
      version = string.byte(stream:read(1))
      nlen = string.unpack(formats[version].name,
        stream:read(string.packsize(formats[version].name)))
    end
    local name = path.clean(stream:read(nlen))
    remain = string.unpack(formats[version].len,
      stream:read(string.packsize(formats[version].len)))
    return name, read, remain
  end
end

function mtar.archive(base)
  checkArg(1, base, "FILE*")
  return setmetatable({
    base = base,
    mode = "w"
  }, {__index = stream})
end

return mtar
