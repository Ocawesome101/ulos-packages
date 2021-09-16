-- text utilities

local lib = {}

function lib.escape(str)
  return (str:gsub("[%[%]%(%)%$%%%^%*%-%+%?%.]", "%%%1"))
end

function lib.split(text, split)
  checkArg(1, text, "string")
  checkArg(2, split, "string", "table")
  
  if type(split) == "string" then
    split = {split}
  end

  local words = {}
  local pattern = "[^" .. lib.escape(table.concat(split)) .. "]+"

  for word in text:gmatch(pattern) do
    words[#words + 1] = word
  end

  return words
end

function lib.padRight(n, text, c)
  return ("%s%s"):format((c or " "):rep(n - #text), text)
end

function lib.padLeft(n, text, c)
  return ("%s%s"):format(text, (c or " "):rep(n - #text))
end

-- default behavior is to fill rows first because that's much easier
-- TODO: implement column-first sorting
function lib.mkcolumns(items, args)
  checkArg(1, items, "table")
  checkArg(2, args, "table", "nil")
  
  local lines = {""}
  local text = {}
  args = args or {}
  -- default max width 50
  args.maxWidth = args.maxWidth or 50
  
  table.sort(items)
  
  if args.hook then
    for i=1, #items, 1 do
      text[i] = args.hook(items[i]) or items[i]
    end
  end

  local longest = 0
  for i=1, #items, 1 do
    longest = math.max(longest, #items[i])
  end

  longest = longest + (args.spacing or 1)

  local n = 0
  for i=1, #text, 1 do
    text[i] = string.format("%s%s", text[i], (" "):rep(longest - #items[i]))
    
    if longest * (n + 1) + 1 > args.maxWidth and #lines[#lines] > 0 then
      n = 0
      lines[#lines + 1] = ""
    end
    
    lines[#lines] = string.format("%s%s", lines[#lines], text[i])

    n = n + 1
  end

  return table.concat(lines, "\n")
end

-- wrap text, ignoring VT100 escape codes but preserving them.
function lib.wrap(text, width)
  checkArg(1, text, "string")
  checkArg(2, width, "number")
  local whitespace = "[ \t\n\r]"
  local splitters = "[ %=%+]"
  local ws_sp = whitespace:sub(1,-2) .. splitters:sub(2)

  local odat = ""

  local len = 0
  local invt = false
  local esc_len = 0
  for c in text:gmatch(".") do
    odat = odat .. c
    if invt then
      esc_len = esc_len + 1
      if c:match("[a-zA-Z]") then invt = false end
    elseif c == "\27" then
      esc_len = esc_len + 1
      invt = true
    else
      len = len + 1
      if c == "\n" then
        len = 0
        esc_len = 0
      elseif len >= width then
        local last = odat:reverse():find(splitters)
        local last_nl = odat:reverse():find("\n") or 0
        local indt = odat:sub(-last_nl + 1):match("^ *") or ""
        
        if last and (last - esc_len) < (width // 4) and last > 1 and
            not c:match(ws_sp) then
          odat = odat:sub(1, -last) .. "\n" .. indt .. odat:sub(-last + 1)
          len = last + #indt - 1
        else
          odat = odat .. "\n" .. indt
          len = #indt
        end
      end
    end
  end
  if odat:sub(-1) ~= "\n" then odat = odat .. "\n" end

  return odat
end

return lib
