-- config --

local serializer = require("serializer")

local lib = {}

local function read_file(f)
  local handle, err = io.open(f, "r")
  if not handle then return nil, err end
  return handle:read("a"), handle:close()
end

local function write_file(f, d)
  local handle, err = io.open(f, "w")
  if not handle then return nil, err end
  return true, handle:write(d), handle:close()
end

local function new(self)
  return setmetatable({}, {__index = self})
end

---- table: serialized lua tables ----
lib.table = {new = new}

function lib.table:load(file)
  checkArg(1, file, "string")
  local data, err = read_file(file)
  if not data then return nil, err end
  local ok, err = load("return " .. data, "=(config@"..file..")", "t", _G)
  if not ok then return nil, err end
  return ok()
end

function lib.table:save(file, data)
  checkArg(1, file, "string")
  checkArg(2, data, "table")
  return write_file(file, serializer(data))
end

---- bracket: see example ----
-- [header]
-- key1=value2
-- key2 = [ value1, value3,"value_fortyTwo"]
-- key15=[val5,v7 ]
lib.bracket = {new=new}

local patterns = {
  bktheader = "^%[([%w_-]+)%]$",
  bktkeyval = "^([%w_-]+) ?= ?(.+)",
}

local function pval(v)
  if v:sub(1,1):match("[\"']") and v:sub(1,1) == v:sub(-1) then
    v = v:sub(2,-2)
  elseif v == "true" then
    v = true
  elseif v == "false" then
    v = false
  else
    v = tonumber(v) or v
  end
  return v
end

function lib.bracket:load(file)
  checkArg(1, file, "string")
  local handle, err = io.open(file, "r")
  if not handle then return nil, err end
  local cfg = {}
  local header
  cfg.__load_order = {}
  for line in handle:lines("l") do
    if line:match(patterns.bktheader) then
      header = line:match(patterns.bktheader)
      cfg[header] = {__load_order = {}}
      cfg.__load_order[#cfg.__load_order + 1] = header
    elseif line:match(patterns.bktkeyval) and header then
      local key, val = line:match(patterns.bktkeyval)
      if val:sub(1,1)=="[" and val:sub(-1)=="]" then
        local _v = val:sub(2,-2)
        val = {}
        if #_v > 0 then
          for _val in _v:gmatch("[^,]+") do
            _val=_val:gsub("^ +","") -- remove starting spaces
            val[#val+1] = pval(_val)
          end
        end
      else
        val = pval(val)
      end
      cfg[header].__load_order[#cfg[header].__load_order + 1] = key
      cfg[header][key] = val
    end
  end
  handle:close()
  return cfg
end

function lib.bracket:save(file, cfg)
  checkArg(1, file, "string")
  checkArg(2, cfg, "table")
  local data = ""
  for ind, head in ipairs(cfg.__load_order) do
    local k, v = head, cfg[head]
    data = data .. string.format("%s[%s]", #data > 0 and "\n\n" or "", k)
    for _i, _hd in ipairs(v.__load_order) do
    --for _k, _v in pairs(v) do
      local _k, _v = _hd, v[_hd]
      data = data .. "\n" .. _k .. "="
      if type(_v) == "table" then
        data = data .. "["
        for kk, vv in ipairs(_v) do
          data = data .. serializer(vv) .. (kk < #_v and "," or "")
        end
        data = data .. "]"
      else
        data = data .. serializer(_v)
      end
    end
  end

  data = data .. "\n"

  return write_file(file, data)
end

return lib
