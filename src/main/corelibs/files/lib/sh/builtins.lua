-- shell builtins

local path = require("path")
local users = require("users")
local fs = require("filesystem")

local builtins = {}

------------------ Some builtins -----------------
function builtins:cd(dir)
  if dir == "-" then
    if not self.env.OLDPWD then
      io.stderr:write("sh: cd: OLDPWD not set\n")
      os.exit(1)
    end
    dir = self.env.OLDPWD
    print(dir)
  elseif not dir then
    if not self.env.HOME then
      io.stderr:write("sh: cd: HOME not set\n")
      os.exit(1)
    end
    dir = self.env.HOME
  end
  local cdir = path.canonical(dir)
  local ok, err = fs.stat(cdir)
  if ok then
    self.env.OLDPWD = self.env.PWD
    self.env.PWD = cdir
  else
    io.stderr:write("sh: cd: ", dir, ": ", err, "\n")
    os.exit(1)
  end
end

function builtins:echo(...)
  print(table.concat(table.pack(...), " "))
end

function builtins:builtin(b, ...)
  if not builtins[b] then
    io.stderr:write("sh: builtin: ", b, ": not a shell builtin\n")
    os.exit(1)
  end
  builtins[b](self, ...)
end

function builtins:builtins()
  for k in pairs(builtins) do print(k) end
end

function builtins:exit(n)
  n = tonumber(n) or 0
  self.exit = n
end

--------------- Scripting builtins ---------------
local state = {
  ifs = {},
  fors = {},
  cases = {},
  whiles = {},
}

local function push(t, i)
  t[#t+1] = i
end

local function pop(t)
  local x = t[#t]
  t[#t] = nil
  return x
end

builtins["if"] = function(self, ...)
  local args = table.pack(...)
  local _, status = self.execute(table.concat(args, " ",
    args[1] == "!" and 2 or 1))

  push(state.ifs, {id = #state.ifs + 1, cond = (args[1] == "!" and status ~= 0
    or args[1] ~= "!" and status == 0)})
end

builtins["then"] = function(self, ...)
  local args = table.pack(...)
  if #args > 0 then
    io.stderr:write("sh: syntax error near unexpected token '", args[1], "'\n")
    os.exit(1)
  end

  if not state.ifs[#state.ifs + 1].cond then
    self.skip_until = "else"
  end
end

builtins["else"] = function(self, ...)
  local args = table.pack(...)
  if #args > 0 then
    io.stderr:write("sh: syntax error near unexpected token '", args[1], "'\n")
    os.exit(1)
  end
end

builtins["fi"] = function(self, ...)
  if #state.ifs == 0 then
    io.stderr:write("sh: syntax error near unexpected token 'fi'\n")
    os.exit(1)
  end

  pop(state.ifs)
end

builtins["true"] = function()
  os.exit(0)
end

builtins["false"] = function()
  os.exit(1)
end

return builtins
