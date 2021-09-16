-- bsh: Better Shell --

local path = require("path")
local pipe = require("pipe")
local text = require("text")
local fs = require("filesystem")
local process = require("process")
local readline = require("readline")

local args, opts = require("argutil").parse(...)

local _VERSION_FULL = "1.0.0"
local _VERSION_MAJOR = _VERSION_FULL:sub(1, -3)

os.setenv("PATH", os.getenv("PATH") or "/bin:/sbin:/usr/bin")
os.setenv("PS1", os.getenv("PS1") or "<\\u@\\h: \\W> ")
os.setenv("SHLVL", tostring(math.floor(((os.getenv("SHLVL") or "0") + 1))))
os.setenv("BSH_VERSION", _VERSION_FULL)

local logError = function(err)
  if not err then return end
  io.stderr:write(err .. "\n")
end

local aliases = {}
local shenv = process.info().data.env
local builtins
builtins = {
  cd = function(dir)
    if dir == "-" then
      if not shenv.OLDPWD then
        logError("sh: cd: OLDPWD not set")
        return 1
      end
      dir = shenv.OLDPWD
      print(dir)
    elseif not dir then
      if not shenv.HOME then
        logError("sh: cd: HOME not set")
        return 1
      end
      dir = shenv.HOME
    end

    local full = path.canonical(dir)
    local ok, err = fs.stat(full)
    
    if not ok then
      logError("sh: cd: " .. dir .. ": " .. err)
      return 1
    else
      shenv.OLDPWD = shenv.PWD
      shenv.PWD = full
    end
    return 0
  end,
  set = function(...)
    local args = {...}
    if #args == 0 then
      for k, v in pairs(shenv) do
        if v:match(" ") then v = "'" .. v .. "'" end
        print(k.."="..v)
      end
    else
      for i=1, #args, 1 do
        local name, assign = args[i]:match("(.-)=(.+)")
        if name then shenv[name] = assign end
      end
    end
  end,
  unset = function(...)
    local args = table.pack(...)
    for i=1, #args, 1 do
      shenv[args[i]] = nil
    end
  end,
  kill = function(...)
    local args, opts = {}, {}
    local _raw_args = {...}
    local signal = process.signals.interrupt
    for i, argument in ipairs(_raw_args) do
      if argument:match("%-.+") then
        local value = argument:match("%-(.+)"):lower()
        if tonumber(value) then signal = value else opts[value] = true end
      elseif not tonumber(argument) then
        logError("sh: kill: expected number as PID")
        return 1
      else
        args[#args+1] = tonumber(argument)
      end
    end
    local signal = process.signals.interrupt
    for k,v in pairs(opts) do
      if process.signals[k] then signal = process.signals[k] end
    end
    if opts.sighup then signal = process.signals.hangup end
    if opts.sigint then signal = process.signals.interrupt end
    if opts.sigquit then signal = process.signals.quit end
    if opts.sigpipe then signal = process.signals.pipe end
    if opts.sigstop then signal = process.signals.stop end
    if opts.sigcont then signal = process.signals.continue end
    local exstat = 0
    for i=1, #args, 1 do
      local ok, err = process.kill(args[i], signal)
      if not ok then
        logError("sh: kill: kill process " .. args[i] .. ": " .. err)
        exstat = 1
      end
    end
    return exstat
  end,
  exit = function(n)
    if opts.l or opts.login then
      logError("logout")
    else
      logError("exit")
    end
    os.exit(tonumber(n or "") or 0)
  end,
  logout = function(n)
    if not (opts.login or opts.l) then
      logError("sh: logout: not login shell: use `exit'")
      return 1
    end
    logError("logout")
    os.exit(0)
  end,
  pwd = function() print(shenv.PWD) end,
  ["true"] = function() return 0 end,
  ["false"] = function() return 1 end,
  alias = function(...)
    local args = {...}
    local exstat = 0
    if #args == 0 then
      for k, v in pairs(aliases) do
        print("alias " .. k .. "='" .. v .. "'")
      end
    else
      for i=1, #args, 1 do
        local name, alias = args[i]:match("(.-)=(.+)")
        if name then aliases[name] = alias
        elseif aliases[args[i]] then
          print("alias " .. args[i] .. "='" .. aliases[args[i]] .. "'")
        else
          logError("sh: alias: " .. args[i] .. ": not found")
          exstat = 1
        end
      end
    end
    return exstat
  end,
  unalias = function(...)
    local args = {...}
    local exstat = 0
    for i=1, #args, 1 do
      if not aliases[args[i]] then
        logError("sh: unalias: " .. args[i] .. ": not found")
        exstat = 1
      else
        aliases[args[i]] = nil
      end
    end
    return exstat
  end,
  builtins = function()
    for k, v in pairs(builtins) do print(k) end
  end,
  time = function(...)
    local cmd = table.concat(table.pack(...), " ")
    local start = require("computer").uptime()
    os.execute(cmd)
    local time = require("computer").uptime() - start
    print("real  " .. tostring(time) .. "s")
  end
}

local function exists(file)
  if fs.stat(file) then return file
  elseif fs.stat(file .. ".lua") then return file .. ".lua" end
end

local function resolveCommand(name)
  if builtins[name] then return builtins[name] end
  local try = {name}
  for ent in os.getenv("PATH"):gmatch("[^:]+") do
    try[#try+1] = path.concat(ent, name)
  end
  for i, check in ipairs(try) do
    local file = exists(check)
    if file then
      return file
    end
  end
  return nil, "command not found"
end

local jobs = {}

local function executeCommand(cstr, nowait)
  while (cstr.command[1] or ""):match("=") do
    local name = table.remove(cstr.command, 1)
    local assign
    name, assign = name:match("^(.-)=(.+)$")
    if name then cstr.env[name] = assign end
  end
  
  if #cstr.command == 0 then for k,v in pairs(cstr.env) do os.setenv(k, v) end return 0, "exited" end
  
  local file, err = resolveCommand(cstr.command[1])
  if not file then logError("sh: " .. cstr.command[1] .. ": " .. err) return nil, err end
  local ok

  if type(file) == "function" then -- this means it's a builtin
    if cstr.input == io.stdin and cstr.output == io.stdout then
      local result = table.pack(pcall(file, table.unpack(cstr.command, 2)))
      if not result[1] and result[2] then
        logError("sh: " .. cstr.command[1] .. ": " .. result[2])
        return 1, result[2]
      elseif result[1] then
        return table.unpack(result, 2, result.n)
      end
    else
      ok = file
    end
  else
    ok, err = loadfile(file)
    if not ok then logError(cstr.command[1] .. ": " .. err) return nil, err end
  end

  local sios = io.stderr
  local pid = process.spawn {
    func = function()
      local result = table.pack(xpcall(ok, debug.traceback, table.unpack(cstr.command, 2)))
      if not result[1] then
        io.stderr:write(cstr.command[1], ": ", result[2], "\n")
        os.exit(127)
      else
        local errno = result[2]
        if type(errno) == "number" then
          os.exit(errno)
        else
          os.exit(0)
        end
      end
    end,
    name = cstr.command[1],
    stdin = cstr.input,
    input = cstr.input,
    stdout = cstr.output,
    output = cstr.output,
    stderr = cstr.err,
    env = cstr.env
  }

  --print("Waiting for " .. pid)
  
  if not nowait then
    return process.await(pid)
  else
    jobs[#jobs+1] = pid
    print(string.format("[%d] %d", #jobs, pid))
  end
end

local special = "['\" %[%(%$&#|%){}\n;<>~]"

local function tokenize(text)
  text = text:gsub("$([a-zA-Z0-9_]+)", function(x)return os.getenv(x)or""end)
  local tokens = {}
  local idx = 0
  while #text > 0 do
    local index = text:find(special) or #text+1
    local token = text:sub(1, math.max(1,index - 1))
    if token == "'" then
      local nind = text:find("'", 2)
      if not nind then
        return nil, "unclosed string at index " .. idx
      end
      token = text:sub(1, nind)
    elseif token == '"' then
      local nind = text:find('"', 2)
      if not nind then
        return nil, "unclosed string at index " .. idx
      end
      token = text:sub(1, nind)
    end
    idx = idx + index
    text = text:sub(#token + 1)
    tokens[#tokens + 1] = token
  end
  return tokens
end

local mkrdr
do
  local r = {}
  function r:pop()
    self.i=self.i+1
    return self.t[self.i - 1]
  end
  function r:peek(n)
    return self.t[self.i+(n or 0)]
  end
  function r:get_until(c)
    local t={}
    repeat
      local _c=self:pop()
      t[#t+1]=_c
    until (_c and _c:match(c)) or not _c
    return mkrdr(t)
  end
  function r:get_balanced(s,e)
    local t={}
    local i=1
    self:pop()
    repeat
      local _c = self:pop()
      t[#t+1] = _c
      i = i + ((_c == s and 1) or (_c == e and -1) or 0)
    until i==0 or not _c
    return t
  end
  mkrdr = function(t)
    return setmetatable({i=1,t=t or{}},{__index=r})
  end
end

local eval_1, eval_2

eval_1 = function(tokens)
  -- first pass: simplify it all
  local simplified = {""}
  while true do
    local tok = tokens:pop()
    if not tok then break end
    if tok == "$" then
      if tokens:peek() == "(" then
        local seq = tokens:get_balanced("(",")")
        seq[#seq] = nil -- remove trailing )
        local cseq = eval_2(eval_1(mkrdr(seq)), true) or {}
        for i=1, #cseq, 1 do
          if #simplified[#simplified]==0 then
            simplified[#simplified]=cseq[i]
          else
            simplified[#simplified+1]=cseq[i]
          end
        end
      elseif tokens:peek() == "{" then
        local seq = tokens:get_balanced("{","}")
        seq[#seq]=nil
        simplified[#simplified]=simplified[#simplified]..(os.getenv(table.concat(seq))or"")
      else
        simplified[#simplified] = simplified[#simplified] .. tok
      end
    elseif tok == "#" then
      tokens:get_until("\n")
    elseif tok:sub(1,1):match("['\"]") then
      simplified[#simplified] = simplified[#simplified] .. tok:sub(2,-2)
    elseif tok:match("[ |;\n&]") and #simplified[#simplified] > 0 then
      if tok:match("[^\n ]") then simplified[#simplified+1] = tok end
      if #simplified[#simplified] > 0 then simplified[#simplified + 1] = "" end
    elseif tok == "}" then
      return nil, "syntax error near unexpected token `}'"
    elseif tok == ")" then
      return nil, "syntax error near unexpected token `)'"
    elseif tok == ">" then
      if simplified[#simplified] == ">" then
        simplified[#simplified] = ">>"
      else
        simplified[#simplified+1] = tok
      end
    elseif tok == "<" then
      simplified[#simplified+1] = tok
    elseif tok == "~" then
      if #simplified[#simplified] > 0 then
        simplified[#simplified] = simplified[#simplified] .. "~"
      else
        simplified[#simplified + 1] = os.getenv("HOME")
      end
    elseif tok ~= " " then
      simplified[#simplified] = simplified[#simplified] .. tok
    end
  end
  if #simplified == 0 then return end
  return simplified
end

eval_2 = function(simplified, captureOutput, captureInput)
  if not simplified then return nil, captureOutput end
  local _cout_pipe
  if captureOutput then
    _cout_pipe = captureInput or pipe.create()
  end
  -- second pass: set up command structure
  local struct = {{command = {}, input = captureInput or io.stdin,
    output = (_cout_pipe or io.stdout), err = io.stderr, env = {}}}
  local i = 0
  while i < #simplified do
    i = i + 1
    if simplified[i] == ";" then
      if #struct[#struct].command == 0 then
        return nil, "syntax error near unexpected token `;'"
      elseif i ~= #simplified then
        struct[#struct+1] = ";"
        struct[#struct+1] = {command = {}, input = captureInput or io.stdin,
          output = (_cout_pipe or io.stdout), err = io.stderr, env = {}}
      end
    elseif simplified[i] == "|" then
      if type(struct[#struct]) == "string" or #struct[#struct].command == 0 then
        return nil, "syntax error near unexpected token `|'"
      else
        local _pipe = pipe.create()
        struct[#struct].output = _pipe
        struct[#struct+1] = {command = {}, input = _pipe,
          output = (_cout_pipe or io.stdout), err = io.stderr, env = {}}
      end
    elseif simplified[i] == "&" then
      if type(struct[#struct]) == "string" or #struct[#struct].command == 0 then
        return nil, "syntax error near unexpected token `&'"
      elseif simplified[i+1] == "&" then
        i = i + 1
        struct[#struct+1] = "&&"
        struct[#struct+1] = {command = {}, input = captureInput or io.stdin,
          output = (_cout_pipe or io.stdout), err = io.stderr, env = {}}
      else
        -- support for & is broken right now, i might fix it later.
        --struct[#struct+1] = "&"
        --struct[#struct+1] = {command = {}, input = captureInput or io.stdin,
        --  output = (captureOutput and _cout_pipe or io.stdout), err = io.stderr, env = {}}
        return nil, "syntax error near unexpected token `&'"
      end
    elseif simplified[i] == ">" or simplified[i] == ">>" then
      if not simplified[i+1] then
        return nil, "syntax error near unexpected token `" .. simplified[i] .. "'"
      else
        i = i + 1
        local handle, err = io.open(simplified[i], simplified[i-1] == ">" and "w" or "a")
        if not handle then
          return nil, "cannot open " .. simplified[i] .. ": " .. err
        end
        struct[#struct].output = handle
      end
    elseif simplified[i] == "<" then
      if not simplified[i+1] then
        return nil, "syntax error near unexpected token `<'"
      else
        i = i + 1
        local handle, err = io.open(simplified[i], "r")
        if not handle then
          return nil, "cannot open " .. simplified[i] .. ": " .. err
        end
        struct[#struct].input = handle
      end
    elseif #simplified[i] > 0 then
      if #struct[#struct].command == 0 and aliases[simplified[i]] then
        local tokens = eval_1(mkrdr(tokenize(aliases[simplified[i]])))
        for i=1, #tokens, 1 do table.insert(struct[#struct].command, tokens[i]) end
      else
        if simplified[i]:sub(1,1) == "~" then simplified[i] = path.concat(os.getenv("HOME"), 
          simplified[i]) end
        if simplified[i]:sub(-1) == "*" then
          local full = path.canonical(simplified[i])
          if full:sub(-2) == "/*" then -- simpler
            local files = fs.list(full:sub(1,-2)) or {}
            for i=1, #files, 1 do
              table.insert(struct[#struct].command, path.concat(full:sub(1,-2),
                files[i]))
            end
          else
            local _path, name = full:match("^(.+/)(.-)$")
            local files = fs.list(_path) or {}
            name = text.escape(name:sub(1,-2)) .. ".+$"
            for i=1, #files, 1 do
              if files[i]:match(name) then
                table.insert(struct[#struct].command, path.concat(_path, files[i]))
              end
            end
          end
        else
          table.insert(struct[#struct].command, simplified[i])
        end
      end
    end
  end

  local srdr = mkrdr(struct)
  local bg = not not captureInput
  local lastExitStatus, lastExitReason, lastSeparator = 0, "", ";"
  for token in srdr.pop, srdr do
    --bg = (srdr:peek() == "|" or srdr:peek() == "&") or not not captureInput
    if type(token) == "table" then
      if lastSeparator == "&&" then
        if lastExitStatus == 0 then
          local exitStatus, exitReason = executeCommand(token, bg)
          lastExitStatus = exitStatus
          if exitReason ~= "__internal_process_exit" and exitReason ~= "exited"
              and exitReason and #exitReason > 0 then
            logError(exitReason)
          end
        end
      elseif lastSeparator == "|" then
        if lastExitStatus == 0 then
          local exitStatus, exitReason = executeCommand(token, bg)
          lastExitStatus = exitStatus
          if exitReason ~= "__internal_process_exit" and exitReason ~= "exited"
              and exitReason and #exitReason > 0 then
            logError(exitReason)
          end
        end
      elseif lastSeparator == ";" then
        lastExitStatus = 0
        local exitStatus, exitReason = executeCommand(token, bg)
        lastExitStatus = exitStatus
        if exitReason ~= "__internal_process_exit" and exitReason ~= "exited"
            and exitReason and #exitReason > 0 and type(exitStatus) == "number" then
          logError(exitReason)
        end
      end
    elseif type(token) == "string" then
      lastSeparator = token
    end
  end

  --print("reading output")

  if captureOutput and not captureInput then
    local lines = {}
    _cout_pipe:close() -- this ONLY works on pipes!
    for line in _cout_pipe:lines("l") do lines[#lines+1] = line end
    return lines
  else
    return lastExitStatus == 0
  end
end

local function process_prompt(ps)
  return (ps:gsub("\\(.)", {
    ["$"] = os.getenv("USER") == "root" and "#" or "$",
    ["a"] = "\a",
    ["A"] = os.date("%H:%M"),
    ["d"] = os.date("%a %b %d"),
    ["e"] = "\27",
    ["h"] = (os.getenv("HOSTNAME") or "localhost"):gsub("%.(.+)$", ""),
    ["h"] = os.getenv("HOSTNAME") or "localhost",
    ["j"] = "0", -- the number of jobs managed by the shell
    ["l"] = "tty" .. math.floor(io.stderr.tty or 0),
    ["n"] = "\n",
    ["r"] = "\r",
    ["s"] = "sh",
    ["t"] = os.date("%T"),
    ["T"] = os.date("%I:%M:%S"),
    ["@"] = os.date("%H:%M %p"),
    ["u"] = os.getenv("USER"),
    ["v"] = _VERSION_MAJOR_MINOR,
    ["V"] = _VERSION_FULL,
    ["w"] = os.getenv("PWD"):gsub(
      "^"..text.escape(os.getenv("HOME")), "~"),
    ["W"] = (os.getenv("PWD") or "/"):gsub(
      "^"..text.escape(os.getenv("HOME")), "~"):match("([^/]+)/?$") or "/",
  }))
end

function os.execute(...)
  local cmd = table.concat({...}, " ")
  if #cmd > 0 then return eval_2(eval_1(mkrdr(tokenize(cmd)))) end
  return 0
end

function os.remove(_path)
  return fs.remove(path.canonical(_path))
end

function io.popen(command, mode)
  checkArg(1, command, "string")
  checkArg(2, mode, "string", "nil")
  mode = mode or "r"
  assert(mode == "r" or mode == "w", "bad mode to io.popen")

  local handle = pipe.create()

  local ok, err = eval_2(eval_1(mkrdr(tokenize(command))), true, handle)
  if not ok and err then
    return nil, err
  end

  return handle
end

if fs.stat("/etc/bshrc") then
  for line in io.lines("/etc/bshrc") do
    local ok, err = eval_2(eval_1(mkrdr(tokenize(line))))
    if not ok and err then logError("sh: " .. err) end
  end
end

if fs.stat(os.getenv("HOME") .. "/.bshrc") then
  for line in io.lines(os.getenv("HOME") .. "/.bshrc") do
    local ok, err = eval_2(eval_1(mkrdr(tokenize(line))))
    if not ok and err then logError("sh: " .. err) end
  end
end

local hist = {}
local rlopts = {history = hist, exit = builtins.exit}
while true do
  io.write(process_prompt(os.getenv("PS1")))
  local text = readline(rlopts)
  if #text > 0 then
    table.insert(hist, text)
    if #hist > 32 then table.remove(hist, 1) end
    local ok, err = eval_2(eval_1(mkrdr(tokenize(text))))
    if not ok and err then logError("sh: " .. err) end
  end
end
