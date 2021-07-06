-- work with some paths!

local lib = {}

function lib.split(path)
  checkArg(1, path, "string")

  local segments = {}
  
  for seg in path:gmatch("[^\\/]+") do
    if seg == ".." then
      segments[#segments] = nil
    elseif seg ~= "." then
      segments[#segments + 1] = seg
    end
  end
  
  return segments
end

function lib.clean(path)
  checkArg(1, path, "string")

  return string.format("/%s", table.concat(lib.split(path), "/"))
end

function lib.concat(...)
  local args = table.pack(...)
  if args.n == 0 then return end

  for i=1, args.n, 1 do
    checkArg(i, args[i], "string")
  end

  return lib.clean("/" .. table.concat(args, "/"))
end

function lib.canonical(path)
  checkArg(1, path, "string")

  if path:sub(1,1) ~= "/" then
    path = lib.concat(os.getenv("PWD") or "/", path)
  end

  return lib.clean(path)
end

return lib
