-- glob expansion function --

local path = require("path")
local filesystem = require("filesystem")

local expand
expand = function(pattern)
  if pattern:sub(1,1) == "*" then
    pattern = "./" .. pattern
  end
  local results = {}
  if pattern:match("[^\\]%*") then
    local _, index = pattern:find("[^\\]%*")
    local base, rest = pattern:sub(1, index-1), pattern:sub(index+1)
    local fname_pat = ".+"
    if base:sub(-1) ~= "/" and #base > 0 then
      local start = base:match("^.+/(.-)$")
      if start then
        base = base:sub(1, -#start - 1)
        fname_pat = require("text").escape(start) .. fname_pat
      end
    end
    if rest:sub(1,1) ~= "/" and #rest > 0 then
      local start = rest:match("^(.-/?)$")
      if start then
        if start:sub(-1) == "/" then start = start:sub(1, -2) end
        rest = rest:sub(#start + 1)
        fname_pat = fname_pat .. require("text").escape(start)
      end
    end
    local files, err = filesystem.list(path.canonical(base))
    if not files then
      -- ignore errors for now
      -- TODO: is this correct behavior?
      local res = expand(path.concat(base, rest))
      for i=1, #res, 1 do
        results[#results+1] = res[i]
      end
    else
      table.sort(files)
      for i, file in ipairs(files) do
        if file:sub(-1) == "/" then file = file:sub(1,-2) end
        if file:match(fname_pat) then
          local res = expand(base .. file .. rest)
          for i=1, #res, 1 do
            results[#results+1] = res[i]
          end
        end
      end
    end
  end
  if #results == 0 then results = {pattern} end
  return results
end

return expand
