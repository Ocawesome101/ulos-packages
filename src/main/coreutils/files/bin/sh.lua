-- a shell.

local fs = require("filesystem")
local pipe = require("pipe")
local users = require("users")
local process = require("process")
local builtins = require("sh/builtins")
local tokenizer = require("tokenizer")
local args, shopts = require("argutil").parse(...)

if shopts.help then
  io.stderr:write([[
usage: sh [-e]
A Bourne-ish shell.  Mildly deprecated in favor of
the Lisp-like SHell (lsh).

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local w_iter = tokenizer.new()

os.setenv("PWD", os.getenv("PWD") or "/")
os.setenv("PS1", os.getenv("PS1") or "\\u@\\h: \\W\\$ ")

local def_path = "/bin:/sbin:/usr/bin"

w_iter.discard_whitespace = false
w_iter:addToken("bracket", "()[]{}<>")
w_iter:addToken("splitter", "$|&\"'; ")

local function tkiter()
  return w_iter:matchToken()
end

local function split(text)
  w_iter.text = text
  w_iter.i = 0
  local words = {}
  for word, ttype in tkiter do
    word = word:gsub("\n", "")
    words[#words + 1] = word
  end
  return words
end

local token_st = {}

local function push(t)
  token_st[#token_st+1] = t
end

local function pop(t)
  return table.remove(token_st, #token_st)
end

local state = {
  backticked = false,
  quoted = false,
}

local alt = {
  ["("] = ")",
  ["{"] = "}",
  ["["] = "]"
}

local splitc = {
  ["|"] = true,
  [";"] = true,
  ["&"] = true,
  [">"] = true,
  ["<"] = true
}

local var_decl = "([^ ]+)=(.-)"

-- builtin command environment
local penv = {
  env = process.info().data.env,
  shopts = shopts,
  exit = false
}
local function resolve_program(program)
  if builtins[program] then
    return function(...) return builtins[program](penv, ...) end
  end

  if program == "" or not program then
    return
  end
  
  local pwd = os.getenv("PWD")
  local path = os.getenv("PATH") or def_path
  
  if program:match("/") then
    local relative
  
    if program:sub(1,1) == "/" then
      relative = program
    else
      relative = string.format("%s/%s", pwd, program)
    end
    
    if fs.stat(relative) then
      return relative
    elseif fs.stat(relative .. ".lua") then
      return relative .. ".lua"
    end
  end

  for entry in path:gmatch("[^:]+") do
    local try = string.format("%s/%s", entry, program)
  
    if fs.stat(try) then
      return try
    elseif fs.stat(try .. ".lua") then
      return try .. ".lua"
    end
  end

  return nil, "sh: " .. program .. ": command not found"
end

local function os_execute(...)
  local prg = table.concat(table.pack(...), " ")
  local e, c = penv.execute(prg)
  return c ~= 0, e, c
end

local function run_programs(programs, getout)
  local sequence = {{}}
  local execs = {}
  for i, token in ipairs(programs) do
    if splitc[token] then
      if #sequence[#sequence] > 0 then
        table.insert(sequence, token)
        sequence[#sequence + 1] = {}
      else
        return nil, "sh: syntax error near unexpected token '"..token.."'"
      end
    else
      table.insert(sequence[#sequence], token)
    end
  end

  if #sequence[1] == 0 then
    return true
  end

  for i, program in ipairs(sequence) do
    if type(program) ~= "string" then
      local prg_env = {}
      program.env = prg_env
      while #program > 0 and program[1]:match(var_decl) do
        local k, v = table.remove(program, 1):match(var_decl)
        prg_env[k] = v
      end

      if #program == 0 then
        for k, v in pairs(prg_env) do
          os.setenv(k, v)
        end
        return
      end

      for i, token in ipairs(program) do
        if token:match("%$([^ ]+)") then
          program[i] = os.getenv(token:sub(2))
        end
      end

      program[0] = program[1]
      local pre
      program[1], pre = resolve_program(program[1])
      if not program[1] and pre then
        return nil, pre
      end

      for k, v in pairs(program) do
        if type(v) == "string" and not v:match("[^%s]") and k ~= 0 then
          table.remove(program, k)
        end
      end

      if (not penv.skip_until) or program[0] == penv.skip_until then
        penv.skip_until = nil
        execs[#execs + 1] = program
      end
      -- TODO: there's some weirdness that will happen here under
      -- certain conditions
    elseif program == "|" then
      if type(sequence[i - 1]) ~= "table" or
          type(sequence[i + 1]) ~= "table" then
        return nil, "sh: syntax error near unexpected token '|'"
      end
      local pipe = pipe.create()
      sequence[i - 1].output = pipe
      sequence[i + 1].input = pipe
    elseif program == ">" then
      if type(sequence[i - 1]) ~= "table" or
          type(sequence[i + 1]) ~= "table" then
        return nil, "sh: syntax error near unexpected token '>'"
      end
      local handle, err = io.open(sequence[i+1][1], "a")
      if not handle then
        handle, err = io.open(sequence[i+1][1], "w")
      end
      if not handle then
        return nil, "sh: cannot open " .. sequence[i+1][1] .. ": " ..
          err .. "\n"
      end
      table.remove(sequence, i + 1)
      sequence[i - 1].output = handle
      handle.buffer_mode = "none"
      getout = false
    end
  end

  local outbuf = ""
  if getout then
    sequence[#sequence].output = {
      write = function(_, ...)
        outbuf = outbuf .. table.concat(table.pack(...))
        return _
      end, close = function()end
    }
    setmetatable(sequence[#sequence].output, {__name = "FILE*"})
  end

  local exit, code

  for i, program in ipairs(execs) do
    if program[1] == "\n" or program[1] == "" or not program[1] then
      return
    end

    local exec, err, pname
    if type(program[1]) == "function" then
      exec = program[1]
      pname = program[0] .. " " .. table.concat(program, " ", 2)
    else
      local handle = io.open(program[1], "r")
      
      if handle then
        local data = handle:read(64)
        handle:close()
        local shebang = data:match("#!([^\n]+)\n")
        if shebang then
          local ok, err = resolve_program(shebang)
          if not ok then
            return nil, "sh: " .. program[0] .. ": " .. shebang ..
              ": bad interpreter: " .. (err or "command not found")
          end
          table.insert(program, 1, shebang)
        end
      end

      exec, err = loadfile(program[1])
      pname = table.concat(program, " ")
    end

    if not exec then
      return nil, "sh: " .. program[0] .. ": " ..
        (err or "command not found")
    end
    
    local pid = process.spawn {
      func = function()
        for k, v in pairs(program.env) do
          os.setenv(k, v)
        end

        -- this hurts me, but i must do it
        local old_osexe = os.execute
        local old_osexit = os.exit
        os.execute = os_execute
        function os.exit(n)
          os.execute = old_osexe
          os.exit = old_osexit
          if program.output then
            program.output:close()
          end
          old_osexit(n)
        end
    
        if program.input then
          io.input(program.input)
          --io.stdin = program.input
        end
        
        if program.output then
          io.output(program.output)
          --io.stdout = program.output
        end
        
        local ok, err, ret1 = xpcall(exec, debug.traceback,
          table.unpack(program, 2))

        if not io.input().tty then io.input():close() end
        if not io.output().tty then io.output():close() end

        if not ok and err then
          io.stderr:write(program[0], ": ", err, "\n")
          os.exit(127)
        elseif not err and ret1 then
          io.stderr:write(program[0], ": ", err, "\n")
          os.exit(127)
        end
        
        os.exit(0)
      end,
      name = pname or program[0],
      stdin = program.input,
      input = program.input,
      stdout = program.output,
      output = program.output,
      stderr = program.stderr
                or io.stderr
    }

    code, exit = process.await(pid)

    if code ~= 0 and shopts.e then
      return exit, code
    end
  end

  if getout then return outbuf, exit, code end
  return exit, code
end

local function parse(cmd)
  local ret = {}
  local words = split(cmd)
  for i=1, #words, 1 do
    local token = words[i]
    token = token:gsub("\n", "")
    local opening = token_st[#token_st]
    local preceding = words[i - 1]
    if token:match("[%(%{]") and not state.quoted then -- opening bracket
      if preceding == "$" then
        push(token)
        if ret[#ret] == "$" then ret[#ret] = "" else ret[#ret + 1] = "" end
      else
        -- TODO: handle this
        return nil, "sh: syntax error near unexpected token '" .. token .. "'"
      end
    elseif token:match("[%)%}]") and not state.quoted then -- closing bracket
      local ttok = pop()
      if token ~= alt[ttok] then
        return nil, "sh: syntax error near unexpected token '" .. token .. "'"
      end
      local pok, perr = parse(table.concat(ret[#ret], " "))
      if not pok then
        return nil, perr
      end
      local rok, rerr = run_programs(pok, true)
      if not rok then
        return nil, rerr
      end
      ret[#ret] = rok
    elseif token:match([=[["']]=]) then
      if state.quoted and token == state.quoted then
        state.quoted = false
      elseif not state.quoted then
        state.quoted = token
        ret[#ret + 1] = ""
      else
        ret[#ret] = ret[#ret] .. token
      end
    elseif opening and opening:match("[%({]") then
      ret[#ret + 1] = {}
      table.insert(ret[#ret], token)
    elseif state.quoted then
      ret[#ret] = ret[#ret] .. token
    elseif token:match("[%s\n]") then
      if (not ret[#ret]) or #ret[#ret] > 0 then ret[#ret + 1] = "" end
    elseif token == ";" or token == ">" then
      if #ret == 0 or #(ret[#ret - 1] or ret[#ret]) == 0 then
        io.stderr:write("sh: syntax error near unexpected token '", token,
          "'\n")
        return nil
      end
      ret[#ret + 1] = token
      ret[#ret + 1] = ""
    elseif token then
      if #ret == 0 then ret[1] = "" end
      ret[#ret] = ret[#ret] .. token
    end
  end
  return ret
end

-- instantly replace these
local crep = {
  ["\\a"] = "\a",
  ["\\e"] = "\27",
  ["\\n"] = "\n",
  ["\\([0-7]+)"] = function(a) return string.char(tonumber(a, 8)) end,
  ["\\x([0-9a-fA-F][0-9a-fA-F])"] = function(a) return
    string.char(tonumber(a,16)) end,
  ["~"] = os.getenv("HOME")
}

local function execute(cmd)
  for k, v in pairs(crep) do
    cmd = cmd:gsub(k, v)
  end

  local data, err = parse(cmd)
  if not data then
    return nil, err
  end

  return run_programs(data)
end

penv.execute = execute

-- this should be mostly complete
local prep = {
  ["\\%$"] = function() return process.info().owner == 0 and "#" or "$" end,
  ["\\a"] = function() return "\a" end,
  ["\\A"] = function() return os.date("%H:%M") end,
  ["\\d"] = function() return os.date("%a %b %d") end,
  ["\\e"] = function() return "\27" end,
  ["\\h"] = function() return os.getenv("HOSTNAME") or "localhost" end,
  ["\\H"] = function() return os.getenv("HOSTNAME") or "localhost" end,
  ["\\j"] = function() return "0" end, -- TODO what does this actually do?
  ["\\l"] = function() return "tty"..(io.stdin.base.ttyn or 0) end,
  ["\\n"] = function() return "\n" end,
  ["\\r"] = function() return "\r" end,
  ["\\s"] = function() return "sh" end,
  ["\\t"] = function() return os.date("%T") end,
  ["\\T"] = function() return os.date("%I:%M:%S") end,
  ["\\u"] = function() return os.getenv("USER") end,
  ["\\v"] = function() return SH_VERSION end,
  ["\\V"] = function() return SH_VERSION end,
  ["\\w"] = function() return (os.getenv("PWD"):gsub("^" .. ((os.getenv("HOME")
    or "/"):gsub("%.%-%+", "%%%1")), "~")) end,
  ["\\W"] = function() local n = require("path").split(os.getenv("PWD"));
    if (not n[#n]) or #n[#n] == 0 then return "/" else return n[#n] end end,
}

local function prompt(text)
  if not text then return "$ " end
  for k, v in pairs(prep) do
    text = text:gsub(k, v() or "")
  end
  return text
end

local function exec_script(s)
  local handle, err = io.open(s, "r")
  if not handle then
    io.stderr:write(s, ": ", err, "\n")
    if not noex then os.exit(1) end
    return
  end
  local data = handle:read("a")
  handle:close()

  local ok, err = execute(data)
  if not ok and err then
    io.stderr:write(s, ": ", err, "\n")
    if not noex then os.exit(1) end
    return
  end
end

if fs.stat("/etc/profile") then
  exec_script("/etc/profile", true)
end

if fs.stat(os.getenv("HOME").."/.shrc") then
  exec_script(os.getenv("HOME").."/.shrc", true)
end

if io.stdin.tty then
  -- ignore ^C
  process.info().data.self.signal[process.signals.interrupt] = function() end

  -- ignore ^Z
  process.info().data.self.signal[process.signals.kbdstop] = function() end

  -- ignore ^D
  process.info().data.self.signal[process.signals.hangup] = function() end
end

while not penv.exit do
  io.write("\27?0c", prompt(os.getenv("PS1")))
  local inp = io.read("L")
  if inp then
    local ok, err = execute(inp)
    if not ok and err then
      io.stderr:write(err, "\n")
    end
  end
end

if type(penv.exit) == "number" then
  os.exit(penv.exit)
end

os.exit(0)
