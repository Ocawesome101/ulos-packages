-- serializer --

local function ser(va, seen)
  if type(va) ~= "table" then
    if type(va) == "string" then return string.format("%q", tostring(va))
    else return tostring(va) end end
  if seen[va] then return "{recursed}" end
  seen[va] = true
  local ret = "{"
  for k, v in pairs(va) do
    k = ser(k, seen)
    v = ser(v, seen)
    if k and v then
      ret = ret .. string.format("[%s]=%s,", k, v)
    end
  end
  return ret .. "}"
end

return function(tab)
  return ser(tab, {})
end
