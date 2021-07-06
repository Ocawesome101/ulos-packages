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

--[[
function stream:readfile()
  if self.mode ~= "r" then
    return nil, "cannot read from write-only stream"
  end

  local namelen = (self.base:read(2) or "\0\0")
  if #namelen == 0 then return end
  namelen = (">I2"):unpack(namelen)
  local version = 0
  local to_read = 0
  local file_path = ""
  if namelen == 0xFFFF then
    version = self.base:read(1):byte()
    namelen = formats[version].name:unpack(self.base:read(2))
  elseif namelen == 0 then
    return nil
  end

  if not formats[version] then
    return nil, "unsupported format version " .. version
  end

  file_path = self.base:read(namelen)
  if #file_path ~= namelen then
    return nil, "unexpected end-of-file reading filename from archive"
  end
  
  local file_len = self.base:read(string.packsize(formats[version].len))
  file_len = formats[version].len:unpack(file_len)
  local file_data = self.base:read(file_len)
  if #file_data ~= file_len then
    return nil, string.format("unexpected end-of-file reading file from archive (expected data of length %d, but got %d)", file_len, #file_data)
  end
  return file_path, file_data
end
--]]

function stream:close()
  self.base:close()
end

local mtar = {}

--[[
function mtar.unarchive(base)
  checkArg(1, base, "FILE*")
  return setmetatable({
    base = base,
    mode = "r",
  }, {__index = stream})
end
--]]

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
