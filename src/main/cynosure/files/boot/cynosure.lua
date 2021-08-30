-- Cynosure kernel.  Should (TM) be mostly drop-in compatible with Paragon. --
-- Might even be better.  Famous last words!
-- Copyright (c) 2021 i develop things under the DSLv1.

_G.k = { cmdline = table.pack(...) }
do
  local start = computer.uptime()
  function k.uptime()
    return computer.uptime() - start
  end
end
-- kernel arguments

do
  local arg_pattern = "^(.-)=(.+)$"
  local orig_args = k.cmdline
  k.__original_cmdline = orig_args
  k.cmdline = {}

  for i=1, #orig_args, 1 do
    local karg = orig_args[i]
    
    if karg:match(arg_pattern) then
      local ka, v = karg:match(arg_pattern)
    
      if ka and v then
        k.cmdline[ka] = tonumber(v) or v
      end
    else
      k.cmdline[karg] = true
    end
  end
end
--#include "base/args.lua"
-- kernel version info --

do
  k._NAME = "Cynosure"
  k._RELEASE = "1.03"
  k._VERSION = "2021.08.29-default"
  _G._OSVERSION = string.format("%s r%s-%s", k._NAME, k._RELEASE, k._VERSION)
end
--#include "base/version.lua"
-- object-based tty streams --

do
  local colors = {
    0x000000,
    0xaa0000,
    0x00aa00,
    0xaa5500,
    0x0000aa,
    0xaa00aa,
    0x00aaaa,
    0xaaaaaa,
    0x555555,
    0xff5555,
    0x55ff55,
    0xffff55,
    0x5555ff,
    0xff55ff,
    0x55ffff,
    0xffffff
  }

  -- pop characters from the end of a string
  local function pop(str, n)
    local ret = str:sub(1, n)
    local also = str:sub(#ret + 1, -1)
 
    return also, ret
  end

  local function wrap_cursor(self)
    while self.cx > self.w do
    --if self.cx > self.w then
      self.cx, self.cy = math.max(1, self.cx - self.w), self.cy + 1
    end
    
    while self.cx < 1 do
      self.cx, self.cy = self.w + self.cx, self.cy - 1
    end
    
    while self.cy < 1 do
      self.cy = self.cy + 1
      self.gpu.copy(1, 1, self.w, self.h - 1, 0, 1)
      self.gpu.fill(1, 1, self.w, 1, " ")
    end
    
    while self.cy > self.h do
      self.cy = self.cy - 1
      self.gpu.copy(1, 2, self.w, self.h, 0, -1)
      self.gpu.fill(1, self.h, self.w, 1, " ")
    end
  end

  local function writeline(self, rline)
    local wrapped = false
    while #rline > 0 do
      local to_write
      rline, to_write = pop(rline, self.w - self.cx + 1)
      
      self.gpu.set(self.cx, self.cy, to_write)
      
      self.cx = self.cx + #to_write
      wrapped = self.cx > self.w
      
      wrap_cursor(self)
    end
    return wrapped
  end

  local function write(self, lines)
    while #lines > 0 do
      local next_nl = lines:find("\n")

      if next_nl then
        local ln
        lines, ln = pop(lines, next_nl - 1)
        lines = lines:sub(2) -- take off the newline
        
        local w = writeline(self, ln)

        if not w then
          self.cx, self.cy = 1, self.cy + 1
        end

        wrap_cursor(self)
      else
        writeline(self, lines)
        break
      end
    end
  end

  local commands, control = {}, {}
  local separators = {
    standard = "[",
    control = "?"
  }

  -- move cursor up N[=1] lines
  function commands:A(args)
    local n = math.max(args[1] or 0, 1)
    self.cy = self.cy - n
  end

  -- move cursor down N[=1] lines
  function commands:B(args)
    local n = math.max(args[1] or 0, 1)
    self.cy = self.cy + n
  end

  -- move cursor right N[=1] lines
  function commands:C(args)
    local n = math.max(args[1] or 0, 1)
    self.cx = self.cx + n
  end

  -- move cursor left N[=1] lines
  function commands:D(args)
    local n = math.max(args[1] or 0, 1)
    self.cx = self.cx - n
  end

  -- incompatibility: terminal-specific command for calling advanced GPU
  -- functionality
  function commands:g(args)
    if #args < 1 then return end
    local cmd = table.remove(args, 1)
    if cmd == 0 then -- fill
      if #args < 4 then return end
      args[1] = math.max(1, math.min(args[1], self.w))
      args[2] = math.max(1, math.min(args[2], self.h))
      self.gpu.fill(args[1], args[2], args[3], args[4], " ")
    elseif cmd == 1 then -- copy
      if #args < 6 then return end
      self.gpu.copy(args[1], args[2], args[3], args[4], args[5], args[6])
    end
    -- TODO more commands
  end

  function commands:G(args)
    self.cx = math.max(1, math.min(self.w, args[1] or 1))
  end

  function commands:H(args)
    local y, x = 1, 1
    y = args[1] or y
    x = args[2] or x
  
    self.cx = math.max(1, math.min(self.w, x))
    self.cy = math.max(1, math.min(self.h, y))
    
    wrap_cursor(self)
  end

  -- clear a portion of the screen
  function commands:J(args)
    local n = args[1] or 0
    
    if n == 0 then
      self.gpu.fill(1, self.cy, self.w, self.h - self.cy, " ")
    elseif n == 1 then
      self.gpu.fill(1, 1, self.w, self.cy, " ")
    elseif n == 2 then
      self.gpu.fill(1, 1, self.w, self.h, " ")
    end
  end
  
  -- clear a portion of the current line
  function commands:K(args)
    local n = args[1] or 0
    
    if n == 0 then
      self.gpu.fill(self.cx, self.cy, self.w, 1, " ")
    elseif n == 1 then
      self.gpu.fill(1, self.cy, self.cx, 1, " ")
    elseif n == 2 then
      self.gpu.fill(1, self.cy, self.w, 1, " ")
    end
  end

  -- adjust some terminal attributes - foreground/background color and local
  -- echo.  for more control {ESC}?c may be desirable.
  function commands:m(args)
    args[1] = args[1] or 0
    local i = 1
    while i <= #args do
      local n = args[i]
      if n == 0 then
        self.fg = colors[8]
        self.bg = colors[1]
        self.gpu.setForeground(self.fg)
        self.gpu.setBackground(self.bg)
        self.attributes.echo = true
      elseif n == 8 then
        self.attributes.echo = false
      elseif n == 28 then
        self.attributes.echo = true
      elseif n > 29 and n < 38 then
        self.fg = colors[n - 29]
        self.gpu.setForeground(self.fg)
      elseif n == 39 then
        self.fg = colors[8]
        self.gpu.setForeground(self.fg)
      elseif n > 39 and n < 48 then
        self.bg = colors[n - 39]
        self.gpu.setBackground(self.bg)
      elseif n == 49 then
        self.bg = colors[1]
        self.gpu.setBackground(self.bg)
      elseif n > 89 and n < 98 then
        self.fg = colors[n - 81]
        self.gpu.setForeground(self.fg)
      elseif n > 99 and n < 108 then
        self.bg = colors[n - 91]
        self.gpu.setBackground(self.bg)
      elseif n == 38 then
        i = i + 1
        if not args[i] then return end
        local mode = args[i]
        if mode == 5 then -- 256-color mode
          -- TODO
        elseif mode == 2 then -- 24-bit color mode
          local r, g, b = args[i + 1], args[i + 2], args[i + 3]
          if not b then return end
          i = i + 3
          self.fg = (r << 16 + g << 8 + b)
          self.gpu.setForeground(self.fg)
        end
      elseif n == 48 then
        i = i + 1
        if not args[i] then return end
        local mode = args[i]
        if mode == 5 then -- 256-color mode
          -- TODO
        elseif mode == 2 then -- 24-bit color mode
          local r, g, b = args[i + 1], args[i + 2], args[i + 3]
          if not b then return end
          i = i + 3
          self.bg = (r << 16 + g << 8 + b)
          self.gpu.setBackground(self.bg)
        end
      end
      i = i + 1
    end
  end

  function commands:n(args)
    local n = args[1] or 0

    if n == 6 then
      self.rb = string.format("%s\27[%d;%dR", self.rb, self.cy, self.cx)
    end
  end

  function commands:S(args)
    local n = args[1] or 1
    self.gpu.copy(1, n, self.w, self.h, 0, -n)
    self.gpu.fill(1, self.h, self.w, n, " ")
  end

  function commands:T(args)
    local n = args[1] or 1
    self.gpu.copy(1, 1, self.w, self.h-n, 0, n)
    self.gpu.fill(1, 1, self.w, n, " ")
  end

  -- adjust more terminal attributes
  -- codes:
  --   - 0: reset
  --   - 1: enable echo
  --   - 2: enable line mode
  --   - 3: enable raw mode
  --   - 4: show cursor
  --   - 5: undo 15
  --   - 11: disable echo
  --   - 12: disable line mode
  --   - 13: disable raw mode
  --   - 14: hide cursor
  --   - 15: disable all input and output
  function control:c(args)
    args[1] = args[1] or 0
    
    for i=1, #args, 1 do
      local n = args[i]

      if n == 0 then -- (re)set configuration to sane defaults
        -- echo text that the user has entered?
        self.attributes.echo = true
        
        -- buffer input by line?
        self.attributes.line = true
        
        -- whether to send raw key input data according to the VT100 spec,
        -- rather than e.g. changing \r -> \n and capturing backspace
        self.attributes.raw = false

        -- whether to show the terminal cursor
        self.attributes.cursor = true
      elseif n == 1 then
        self.attributes.echo = true
      elseif n == 2 then
        self.attributes.line = true
      elseif n == 3 then
        self.attributes.raw = true
      elseif n == 4 then
        self.attributes.cursor = true
      elseif n == 5 then
        self.attributes.xoff = false
      elseif n == 11 then
        self.attributes.echo = false
      elseif n == 12 then
        self.attributes.line = false
      elseif n == 13 then
        self.attributes.raw = false
      elseif n == 14 then
        self.attributes.cursor = false
      elseif n == 15 then
        self.attributes.xoff = true
      end
    end
  end

  -- adjust signal behavior
  -- 0: reset
  -- 1: disable INT on ^C
  -- 2: disable keyboard STOP on ^Z
  -- 3: disable HUP on ^D
  -- 11: enable INT
  -- 12: enable STOP
  -- 13: enable HUP
  function control:s(args)
    args[1] = args[1] or 0
    for i=1, #args, 1 do
      local n = args[i]
      if n == 0 then
        self.disabled = {}
      elseif n == 1 then
        self.disabled.C = true
      elseif n == 2 then
        self.disabled.Z = true
      elseif n == 3 then
        self.disabled.D = true
      elseif n == 11 then
        self.disabled.C = false
      elseif n == 12 then
        self.disabled.Z = false
      elseif n == 13 then
        self.disabled.D = false
      end
    end
  end

  local _stream = {}

  local function temp(...)
    return ...
  end

  function _stream:write(...)
    checkArg(1, ..., "string")

    local str = (k.util and k.util.concat or temp)(...)

    if self.attributes.line and not k.cmdline.nottylinebuffer then
      self.wb = self.wb .. str
      if self.wb:find("\n") then
        local ln = self.wb:match("(.-\n)")
        self.wb = self.wb:sub(#ln + 1)
        return self:write_str(ln)
      elseif #self.wb > 2048 then
        local ln = self.wb
        self.wb = ""
        return self:write_str(ln)
      end
    else
      return self:write_str(str)
    end
  end

  -- This is where most of the heavy lifting happens.  I've attempted to make
  -- this function fairly optimized, but there's only so much one can do given
  -- OpenComputers's call budget limits and wrapped string library.
  function _stream:write_str(str)
    local gpu = self.gpu
    local time = computer.uptime()
    
    -- TODO: cursor logic is a bit brute-force currently, there are certain
    -- TODO: scenarios where cursor manipulation is unnecessary
    if self.attributes.cursor then
      local c, f, b = gpu.get(self.cx, self.cy)
      gpu.setForeground(b)
      gpu.setBackground(f)
      gpu.set(self.cx, self.cy, c)
      gpu.setForeground(self.fg)
      gpu.setBackground(self.bg)
    end
    
    -- lazily convert tabs
    str = str:gsub("\t", "  ")
    
    while #str > 0 do
      if computer.uptime() - time >= 4.8 then -- almost TLWY
        time = computer.uptime()
        computer.pullSignal(0) -- yield so we don't die
      end

      if self.in_esc then
        local esc_end = str:find("[a-zA-Z]")

        if not esc_end then
          self.esc = string.format("%s%s", self.esc, str)
        else
          self.in_esc = false

          local finish
          str, finish = pop(str, esc_end)

          local esc = string.format("%s%s", self.esc, finish)
          self.esc = ""

          local separator, raw_args, code = esc:match(
            "\27([%[%?])([%-%d;]*)([a-zA-Z])")
          raw_args = raw_args or "0"
          
          local args = {}
          for arg in raw_args:gmatch("([^;]+)") do
            args[#args + 1] = tonumber(arg) or 0
          end
          
          if separator == separators.standard and commands[code] then
            commands[code](self, args)
          elseif separator == separators.control and control[code] then
            control[code](self, args)
          end
          
          wrap_cursor(self)
        end
      else
        -- handle BEL and \r
        if str:find("\a") then
          computer.beep()
        end
        str = str:gsub("\a", "")
        str = str:gsub("\r", "\27[G")

        local next_esc = str:find("\27")
        
        if next_esc then
          self.in_esc = true
          self.esc = ""
        
          local ln
          str, ln = pop(str, next_esc - 1)
          
          write(self, ln)
        else
          write(self, str)
          str = ""
        end
      end
    end

    if self.attributes.cursor then
      c, f, b = gpu.get(self.cx, self.cy)
    
      gpu.setForeground(b)
      gpu.setBackground(f)
      gpu.set(self.cx, self.cy, c)
      gpu.setForeground(self.fg)
      gpu.setBackground(self.bg)
    end
    
    return true
  end

  function _stream:flush()
    if #self.wb > 0 then
      self:write_str(self.wb)
      self.wb = ""
    end
    return true
  end

  -- aliases of key scan codes to key inputs
  local aliases = {
    [200] = "\27[A", -- up
    [208] = "\27[B", -- down
    [205] = "\27[C", -- right
    [203] = "\27[D", -- left
  }

  local sigacts = {
    D = 1, -- hangup, TODO: check this is correct
    C = 2, -- interrupt
    Z = 18, -- keyboard stop
  }

  function _stream:key_down(...)
    local signal = table.pack(...)

    if not self.keyboards[signal[2]] then
      return
    end

    if signal[3] == 0 and signal[4] == 0 then
      return
    end

    if self.xoff then
      return
    end
    
    local char = aliases[signal[4]] or
              (signal[3] > 255 and unicode.char or string.char)(signal[3])
    local ch = signal[3]
    local tw = char

    if ch == 0 and not aliases[signal[4]] then
      return
    end
    
    if #char == 1 and ch == 0 then
      char = ""
      tw = ""
    elseif char:match("\27%[[ABCD]") then
      tw = string.format("^[%s", char:sub(-1))
    elseif #char == 1 and ch < 32 then
      local tch = string.char(
          (ch == 0 and 32) or
          (ch < 27 and ch + 96) or
          (ch == 27 and 91) or -- [
          (ch == 28 and 92) or -- \
          (ch == 29 and 93) or -- ]
          (ch == 30 and 126) or
          (ch == 31 and 63) or ch
        ):upper()
    
      if sigacts[tch] and not self.disabled[tch] and k.scheduler.processes
          and not self.attributes.raw then
        -- fairly stupid method of determining the foreground process:
        -- find the highest PID associated with this TTY
        -- yeah, it's stupid, but it should work in most cases.
        -- and where it doesn't the shell should handle it.
        local mxp = 0

        for _k, v in pairs(k.scheduler.processes) do
          --k.log(k.loglevels.error, _k, v.name)
          if v.io.stderr.tty == self.ttyn then
            mxp = math.max(mxp, _k)
          elseif v.io.stdin.tty == self.ttyn then
            mxp = math.max(mxp, _k)
          elseif v.io.stdout.tty == self.ttyn then
            mxp = math.max(mxp, _k)
          end
        end

        --k.log(k.loglevels.error, "sending", sigacts[tch], "to", mxp == 0 and mxp or k.scheduler.processes[mxp].name)

        if mxp > 0 then
          k.scheduler.processes[mxp]:signal(sigacts[tch])
        end

        self.rb = ""
        if tch == "\4" then self.rb = tch end
        char = ""
      end

      tw = "^" .. tch
    end
    
    if not self.attributes.raw then
      if ch == 13 then
        char = "\n"
        tw = "\n"
      elseif ch == 8 then
        if #self.rb > 0 then
          tw = "\27[D \27[D"
          self.rb = self.rb:sub(1, -2)
        else
          tw = ""
        end
        char = ""
      end
    end
    
    if self.attributes.echo and not self.attributes.xoff then
      self:write_str(tw or "")
    end
    
    if not self.attributes.xoff then
      self.rb = string.format("%s%s", self.rb, char)
    end
  end

  function _stream:clipboard(...)
    local signal = table.pack(...)

    for c in signal[3]:gmatch(".") do
      self:key_down(signal[1], signal[2], c:byte(), 0)
    end
  end
  
  function _stream:read(n)
    checkArg(1, n, "number")

    self:flush()

    local dd = self.disabled.D or self.attributes.raw

    if self.attributes.line then
      while (not self.rb:find("\n")) or (self.rb:find("\n") < n)
          and not (self.rb:find("\4") and not dd) do
        coroutine.yield()
      end
    else
      while #self.rb < n and (self.attributes.raw or not
          (self.rb:find("\4") and not dd)) do
        coroutine.yield()
      end
    end

    if self.rb:find("\4") and not dd then
      self.rb = ""
      return nil
    end

    local data = self.rb:sub(1, n)
    self.rb = self.rb:sub(n + 1)
    return data
  end

  local function closed()
    return nil, "stream closed"
  end

  function _stream:close()
    self:flush()
    self.closed = true
    self.read = closed
    self.write = closed
    self.flush = closed
    self.close = closed
    k.event.unregister(self.key_handler_id)
    k.event.unregister(self.clip_handler_id)
    if self.ttyn then k.sysfs.unregister("/dev/tty"..self.ttyn) end
    return true
  end

  local ttyn = 0

  -- this is the raw function for creating TTYs over components
  -- userspace gets somewhat-abstracted-away stuff
  function k.create_tty(gpu, screen)
    checkArg(1, gpu, "string", "table")
    checkArg(2, screen, "string", "nil")

    local proxy
    if type(gpu) == "string" then
      proxy = component.proxy(gpu)

      if screen then proxy.bind(screen) end
    else
      proxy = gpu
    end

    proxy.setForeground(colors[8])
    proxy.setBackground(colors[1])

    proxy.setDepth(proxy.maxDepth())
    -- optimizations for no color on T1
    if proxy.getDepth() == 1 then
      local fg, bg = proxy.setForeground, proxy.setBackground
      local f, b = colors[1], colors[8]
      function proxy.setForeground(c)
        -- [[
        if c >= 0xAAAAAA or c <= 0x000000 and f ~= c then
          fg(c)
        end
        f = c
        --]]
      end
      function proxy.setBackground(c)
        -- [[
        if c >= 0xDDDDDD or c <= 0x000000 and b ~= c then
          bg(c)
        end
        b = c
        --]]
      end
      proxy.getBackground = function()return f end
      proxy.getForeground = function()return b end
    end

    -- userspace will never directly see this, so it doesn't really matter what
    -- we put in this table
    local new = setmetatable({
      attributes = {echo=true,line=true,raw=false,cursor=false,xoff=false}, -- terminal attributes
      disabled = {}, -- disabled signals
      keyboards = {}, -- all attached keyboards on terminal initialization
      in_esc = false, -- was a partial escape sequence written
      gpu = proxy, -- the associated GPU
      esc = "", -- the escape sequence buffer
      cx = 1, -- the cursor's X position
      cy = 1, -- the cursor's Y position
      fg = colors[8], -- the current foreground color
      bg = colors[1], -- the current background color
      rb = "", -- a buffer of characters read from the input
      wb = "", -- line buffering at its finest
    }, {__index = _stream})

    -- avoid gpu.getResolution calls
    new.w, new.h = proxy.maxResolution()

    proxy.setResolution(new.w, new.h)
    proxy.fill(1, 1, new.w, new.h, " ")
    
    if screen then
      -- register all keyboards attached to the screen
      for _, keyboard in pairs(component.invoke(screen, "getKeyboards")) do
        new.keyboards[keyboard] = true
      end
    end
    
    -- register a keypress handler
    new.key_handler_id = k.event.register("key_down", function(...)
      return new:key_down(...)
    end)

    new.clip_handler_id = k.event.register("clipboard", function(...)
      return new:clipboard(...)
    end)
    
    -- register the TTY with the sysfs
    if k.sysfs then
      k.sysfs.register(k.sysfs.types.tty, new, "/dev/tty"..ttyn)
      new.ttyn = ttyn
    end

    new.tty = ttyn

    if k.gpus then
      k.gpus[ttyn] = proxy
    end
    
    ttyn = ttyn + 1
    
    return new
  end
end
--#include "base/tty.lua"
-- event handling --

do
  local event = {}
  local handlers = {}

  function event.handle(sig)
    for _, v in pairs(handlers) do
      if v.signal == sig[1] then
        v.callback(table.unpack(sig))
      end
    end
  end

  local n = 0
  function event.register(sig, call)
    checkArg(1, sig, "string")
    checkArg(2, call, "function")
    
    n = n + 1
    handlers[n] = {signal=sig,callback=call}
    return n
  end

  function event.unregister(id)
    checkArg(1, id, "number")
    handlers[id] = nil
    return true
  end

  k.event = event
end
--#include "base/event.lua"
-- early boot logger

do
  local levels = {
    debug = 0,
    info = 1,
    warn = 64,
    error = 128,
    panic = 256,
  }
  k.loglevels = levels

  local lgpu = component.list("gpu", true)()
  local lscr = component.list("screen", true)()

  local function safe_concat(...)
    local args = table.pack(...)
    local msg = ""
  
    for i=1, args.n, 1 do
      msg = string.format("%s%s%s", msg, tostring(args[i]), i < args.n and " " or "")
    end
    return msg
  end

  if lgpu and lscr then
    k.logio = k.create_tty(lgpu, lscr)
    
    if k.cmdline.bootsplash then
      local lgpu = component.proxy(lgpu)
      function k.log() end

      -- TODO custom bootsplash support
      local splash = {
        {{0x66b6ff,0,"   ⢀⣠⣴⣾"},{0x66b6ff,0xffffff,"⠿⠿⢿"},{0x66b6ff,0,"⣿⣶⣤⣀    "}},
        {{0x66b6ff,0," ⢀⣴⣿⣿"},{0x66b6ff,0xffffff,"⠋     ⠉⠻⢿"},{0x66b6ff,0,"⣷⣄  "}},
        {{0x66b6ff,0,"⢀⣾⣿⣿"},{0x66b6ff,0xffffff,"⠏        ⠈"},{0x66b6ff,0,"⣿⣿⣆ "}},
        {{0x66b6ff,0,"⣾⣿⣿"},{0x66b6ff,0xffffff,"⡟   ⢀⣾⣿⣿⣦⣄⣠"},{0x66b6ff,0,"⣿⣿⣿⡆"}},
        {{0x66b6ff,0,"⣿⣿⣿"},{0x66b6ff,0xffffff,"⠁   ⠘⠿⢿"},{0x66b6ff,0,"⣿⣿⣿⣿⣿⣿⣿⡇"}},
        {{0x66b6ff,0,"⢻⣿⣿"},{0x66b6ff,0xffffff,"⣄⡀     ⠉⢻"},{0x66b6ff,0,"⣿⣿⣿⣿⣿⠃"}},
        {{0x66b6ff,0," ⢻⣿⣿⣿⣿"},{0x66b6ff,0xffffff,"⣶⣆⡀  ⢸"},{0x66b6ff,0,"⣿⣿⣿⣿⠃ "}},
        {{0x66b6ff,0,"  ⠙⢿⣿⣿⣿⣿⣿"},{0x66b6ff,0xffffff,"⣷"},{0x66b6ff,0,"⣿⣿⣿⣿⠟⠁  "}},
        {{0x66b6ff,0,"    ⠈⠙⠻⠿⠿⠿⠿⠛⠉     "}},
        {{0x66b6ff,0,"                  "}},
        {{0xffffff,0,"     CYNOSURE     "}},
      }

      local w, h = lgpu.maxResolution()
      local x, y = (w // 2) - 10, (h // 2) - (#splash // 2)
      lgpu.setResolution(w, h)
      lgpu.fill(1, 1, w, h, " ")
      for i, line in ipairs(splash) do
        local xo = 0
        for _, ent in ipairs(line) do
          lgpu.setForeground(ent[1])
          lgpu.setBackground(ent[2])
          lgpu.set(x + xo, y + i - 1, ent[3])
          xo = xo + utf8.len(ent[3])
        end
      end
    else
      function k.log(level, ...)
        local msg = safe_concat(...)
        msg = msg:gsub("\t", "  ")
  
        if k.util and not k.util.concat then
          k.util.concat = safe_concat
        end
      
        if (tonumber(k.cmdline.loglevel) or 1) <= level then
          k.logio:write(string.format("[\27[35m%4.4f\27[37m] %s\n", k.uptime(),
            msg))
        end
        return true
      end
    end
  else
    k.logio = nil
    function k.log()
    end
  end

  local raw_pullsignal = computer.pullSignal
  
  function k.panic(...)
    local msg = safe_concat(...)
  
    computer.beep(440, 0.25)
    computer.beep(380, 0.25)

    -- if there's no log I/O, just die
    if not k.logio then
      error(msg)
    end
    
    k.log(k.loglevels.panic, "-- \27[91mbegin stacktrace\27[37m --")
    
    local traceback = debug.traceback(msg, 2)
      :gsub("\t", "  ")
      :gsub("([^\n]+):(%d+):", "\27[96m%1\27[37m:\27[95m%2\27[37m:")
      :gsub("'([^']+)'\n", "\27[93m'%1'\27[37m\n")
    
    for line in traceback:gmatch("[^\n]+") do
      k.log(k.loglevels.panic, line)
    end

    k.log(k.loglevels.panic, "-- \27[91mend stacktrace\27[37m --")
    k.log(k.loglevels.panic, "\27[93m!! \27[91mPANIC\27[93m !!\27[37m")
    
    while true do raw_pullsignal() end
  end
end

k.log(math.huge, "Starting\27[93m", _OSVERSION, "\27[37m")
--#include "base/logger.lua"
-- kernel hooks

k.log(k.loglevels.info, "base/hooks")

do
  local hooks = {}
  k.hooks = {}
  
  function k.hooks.add(name, func)
    checkArg(1, name, "string")
    checkArg(2, func, "function")

    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], func)
  end

  function k.hooks.call(name, ...)
    checkArg(1, name, "string")

    k.logio:write(":: calling hook " .. name .. "\n")
    if hooks[name] then
      for k, v in ipairs(hooks[name]) do
        v(...)
      end
    end
  end
end
--#include "base/hooks.lua"
-- some utilities --

k.log(k.loglevels.info, "base/util")

do
  local util = {}
  
  function util.merge_tables(a, b)
    for k, v in pairs(b) do
      if not a[k] then
        a[k] = v
      end
    end
  
    return a
  end

  -- here we override rawset() in order to properly protect tables
  local _rawset = rawset
  local blacklist = setmetatable({}, {__mode = "k"})
  
  function _G.rawset(t, k, v)
    if not blacklist[t] then
      return _rawset(t, k, v)
    else
      -- this will error
      t[k] = v
    end
  end

  local function protecc()
    error("attempt to modify a write-protected table")
  end

  function util.protect(tbl)
    local new = {}
    local mt = {
      __index = tbl,
      __newindex = protecc,
      __pairs = function() return pairs(tbl) end,
      __ipairs = function() return ipairs(tbl) end,
      __metatable = {}
    }
  
    return setmetatable(new, mt)
  end

  -- create hopefully memory-friendly copies of tables
  -- uses metatable magic
  -- this is a bit like util.protect except tables are still writable
  -- even i still don't fully understand how this works, but it works
  -- nonetheless
  --[[disabled due to some issues i was having
  if computer.totalMemory() < 262144 then
    -- if we have 256k or less memory, use the mem-friendly function
    function util.copy_table(tbl)
      if type(tbl) ~= "table" then return tbl end
      local shadow = {}
      local copy_mt = {
        __index = function(_, k)
          local item = rawget(shadow, k) or rawget(tbl, k)
          return util.copy(item)
        end,
        __pairs = function()
          local iter = {}
          for k, v in pairs(tbl) do
            iter[k] = util.copy(v)
          end
          for k, v in pairs(shadow) do
            iter[k] = v
          end
          return pairs(iter)
        end
        -- no __metatable: leaving this metatable exposed isn't a huge
        -- deal, since there's no way to access `tbl` for writing using any
        -- of the functions in it.
      }
      copy_mt.__ipairs = copy_mt.__pairs
      return setmetatable(shadow, copy_mt)
    end
  else--]] do
    -- from https://lua-users.org/wiki/CopyTable
    local function deepcopy(orig, copies)
      copies = copies or {}
      local orig_type = type(orig)
      local copy
    
      if orig_type == 'table' then
        if copies[orig] then
          copy = copies[orig]
        else
          copy = {}
          copies[orig] = copy
      
          for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
          end
          
          setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
      else -- number, string, boolean, etc
        copy = orig
      end

      return copy
    end

    function util.copy_table(t)
      return deepcopy(t)
    end
  end

  function util.to_hex(str)
    local ret = ""
    
    for char in str:gmatch(".") do
      ret = string.format("%s%02x", ret, string.byte(char))
    end
    
    return ret
  end

  -- lassert: local assert
  -- removes the "init:123" from errors (fires at level 0)
  function util.lassert(a, ...)
    if not a then error(..., 0) else return a, ... end
  end

  -- pipes for IPC and shells and things
  do
    local _pipe = {}

    function _pipe:read(n)
      if self.closed and #self.rb == 0 then
        return nil
      end
      if not self.closed then
        while #self.rb < n do
          if self.from ~= 0 then
            k.scheduler.info().data.self.resume_next = self.from
          end
          coroutine.yield()
        end
      end
      local data = self.rb:sub(1, n)
      self.rb = self.rb:sub(n + 1)
      return data
    end

    function _pipe:write(dat)
      if self.closed then
        return nil
      end
      self.rb = self.rb .. dat
      return true
    end

    function _pipe:flush()
      return true
    end

    function _pipe:close()
      self.closed = true
      return true
    end

    function util.make_pipe()
      local new = k.create_fstream(setmetatable({
        from = 0, -- the process providing output
        to = 0, -- the process reading input
        rb = "",
      }, {__index = _pipe}), "rw")
      new.buffer_mode = "none"
      return new
    end

    k.hooks.add("sandbox", function()
      k.userspace.package.loaded.pipe = {
        create = util.make_pipe
      }
    end)
  end

  k.util = util
end
--#include "base/util.lua"
-- some security-related things --

k.log(k.loglevels.info, "base/security")

k.security = {}

-- users --

k.log(k.loglevels.info, "base/security/users")

-- from https://github.com/philanc/plc iirc

k.log(k.loglevels.info, "base/security/sha3.lua")

do
-- sha3 / keccak

local char	= string.char
local concat	= table.concat
local spack, sunpack = string.pack, string.unpack

-- the Keccak constants and functionality

local ROUNDS = 24

local roundConstants = {
0x0000000000000001,
0x0000000000008082,
0x800000000000808A,
0x8000000080008000,
0x000000000000808B,
0x0000000080000001,
0x8000000080008081,
0x8000000000008009,
0x000000000000008A,
0x0000000000000088,
0x0000000080008009,
0x000000008000000A,
0x000000008000808B,
0x800000000000008B,
0x8000000000008089,
0x8000000000008003,
0x8000000000008002,
0x8000000000000080,
0x000000000000800A,
0x800000008000000A,
0x8000000080008081,
0x8000000000008080,
0x0000000080000001,
0x8000000080008008
}

local rotationOffsets = {
-- ordered for [x][y] dereferencing, so appear flipped here:
{0, 36, 3, 41, 18},
{1, 44, 10, 45, 2},
{62, 6, 43, 15, 61},
{28, 55, 25, 21, 56},
{27, 20, 39, 8, 14}
}



-- the full permutation function
local function keccakF(st)
	local permuted = st.permuted
	local parities = st.parities
	for round = 1, ROUNDS do
--~ 		local permuted = permuted
--~ 		local parities = parities

		-- theta()
		for x = 1,5 do
			parities[x] = 0
			local sx = st[x]
			for y = 1,5 do parities[x] = parities[x] ~ sx[y] end
		end
		--
		-- unroll the following loop
		--for x = 1,5 do
		--	local p5 = parities[(x)%5 + 1]
		--	local flip = parities[(x-2)%5 + 1] ~ ( p5 << 1 | p5 >> 63)
		--	for y = 1,5 do st[x][y] = st[x][y] ~ flip end
		--end
		local p5, flip, s
		--x=1
		p5 = parities[2]
		flip = parities[5] ~ (p5 << 1 | p5 >> 63)
		s = st[1]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=2
		p5 = parities[3]
		flip = parities[1] ~ (p5 << 1 | p5 >> 63)
		s = st[2]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=3
		p5 = parities[4]
		flip = parities[2] ~ (p5 << 1 | p5 >> 63)
		s = st[3]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=4
		p5 = parities[5]
		flip = parities[3] ~ (p5 << 1 | p5 >> 63)
		s = st[4]
		for y = 1,5 do s[y] = s[y] ~ flip end
		--x=5
		p5 = parities[1]
		flip = parities[4] ~ (p5 << 1 | p5 >> 63)
		s = st[5]
		for y = 1,5 do s[y] = s[y] ~ flip end

		-- rhopi()
		for y = 1,5 do
			local py = permuted[y]
			local r
			for x = 1,5 do
				s, r = st[x][y], rotationOffsets[x][y]
				py[(2*x + 3*y)%5 + 1] = (s << r | s >> (64-r))
			end
		end

		local p, p1, p2
		--x=1
		s, p, p1, p2 = st[1], permuted[1], permuted[2], permuted[3]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=2
		s, p, p1, p2 = st[2], permuted[2], permuted[3], permuted[4]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=3
		s, p, p1, p2 = st[3], permuted[3], permuted[4], permuted[5]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=4
		s, p, p1, p2 = st[4], permuted[4], permuted[5], permuted[1]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end
		--x=5
		s, p, p1, p2 = st[5], permuted[5], permuted[1], permuted[2]
		for y = 1,5 do s[y] = p[y] ~ (~ p1[y]) & p2[y] end

		-- iota()
		st[1][1] = st[1][1] ~ roundConstants[round]
	end
end


local function absorb(st, buffer)

	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 8

	-- append 0x01 byte and pad with zeros to block size (rate/8 bytes)
	local totalBytes = #buffer + 1
	-- SHA3:
	buffer = buffer .. ( '\x06' .. char(0):rep(blockBytes - (totalBytes % blockBytes)))
	totalBytes = #buffer

	--convert data to an array of u64
	local words = {}
	for i = 1, totalBytes - (totalBytes % 8), 8 do
		words[#words + 1] = sunpack('<I8', buffer, i)
	end

	local totalWords = #words
	-- OR final word with 0x80000000 to set last bit of state to 1
	words[totalWords] = words[totalWords] | 0x8000000000000000

	-- XOR blocks into state
	for startBlock = 1, totalWords, blockWords do
		local offset = 0
		for y = 1, 5 do
			for x = 1, 5 do
				if offset < blockWords then
					local index = startBlock+offset
					st[x][y] = st[x][y] ~ words[index]
					offset = offset + 1
				end
			end
		end
		keccakF(st)
	end
end


-- returns [rate] bits from the state, without permuting afterward.
-- Only for use when the state will immediately be thrown away,
-- and not used for more output later
local function squeeze(st)
	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 4
	-- fetch blocks out of state
	local hasht = {}
	local offset = 1
	for y = 1, 5 do
		for x = 1, 5 do
			if offset < blockWords then
				hasht[offset] = spack("<I8", st[x][y])
				offset = offset + 1
			end
		end
	end
	return concat(hasht)
end


-- primitive functions (assume rate is a whole multiple of 64 and length is a whole multiple of 8)

local function keccakHash(rate, length, data)
	local state = {	{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
	}
	state.rate = rate
	-- these are allocated once, and reused
	state.permuted = { {}, {}, {}, {}, {}, }
	state.parities = {0,0,0,0,0}
	absorb(state, data)
	return squeeze(state):sub(1,length/8)
end

-- output raw bytestrings
local function keccak256Bin(data) return keccakHash(1088, 256, data) end
local function keccak512Bin(data) return keccakHash(576, 512, data) end

k.sha3 = {
	sha256 = keccak256Bin,
	sha512 = keccak512Bin,
}
end
--#include "base/security/sha3.lua"

do
  local api = {}

  -- default root data so we can at least run init as root
  -- the kernel should overwrite this with `users.prime()`
  -- and data from /etc/passwd later on
  -- but for now this will suffice
  local passwd = {
    [0] = {
      name = "root",
      home = "/root",
      shell = "/bin/lsh",
      acls = 8191,
      pass = k.util.to_hex(k.sha3.sha256("root")),
    }
  }

  k.hooks.add("shutdown", function()
    -- put this here so base/passwd_init can have it
    k.passwd = passwd
  end)

  function api.prime(data)
    checkArg(1, data, "table")
 
    api.prime = nil
    passwd = data
    k.passwd = data
    
    return true
  end

  function api.authenticate(uid, pass)
    checkArg(1, uid, "number")
    checkArg(2, pass, "string")
    
    pass = k.util.to_hex(k.sha3.sha256(pass))
    
    local udata = passwd[uid]
    
    if not udata then
      os.sleep(1)
      return nil, "no such user"
    end
    
    if pass == udata.pass then
      return true
    end
    
    os.sleep(1)
    return nil, "invalid password"
  end

  function api.exec_as(uid, pass, func, pname, wait)
    checkArg(1, uid, "number")
    checkArg(2, pass, "string")
    checkArg(3, func, "function")
    checkArg(4, pname, "string", "nil")
    checkArg(5, wait, "boolean", "nil")
    
    if k.scheduler.info().owner ~= 0 then
      if not k.security.acl.user_has_permission(k.scheduler.info().owner,
          k.security.acl.permissions.user.SUDO) then
        return nil, "permission denied: no permission"
      end
    end
    
    if not api.authenticate(uid, pass) then
      return nil, "permission denied: bad login"
    end
    
    local new = {
      func = func,
      name = pname or tostring(func),
      owner = uid,
      env = {
        USER = passwd[uid].name,
        UID = tostring(uid),
        SHELL = passwd[uid].shell,
        HOME = passwd[uid].home,
      }
    }
    
    local p = k.scheduler.spawn(new)
    
    if not wait then return end

    -- this is the only spot in the ENTIRE kernel where process.await is used
    return k.userspace.package.loaded.process.await(p.pid)
  end

  function api.get_uid(uname)
    checkArg(1, uname, "string")
    
    for uid, udata in pairs(passwd) do
      if udata.name == uname then
        return uid
      end
    end
    
    return nil, "no such user"
  end

  function api.attributes(uid)
    checkArg(1, uid, "number")
    
    local udata = passwd[uid]
    
    if not udata then
      return nil, "no such user"
    end
    
    return {
      name = udata.name,
      home = udata.home,
      shell = udata.shell,
      acls = udata.acls
    }
  end

  function api.usermod(attributes)
    checkArg(1, attributes, "table")
    attributes.uid = tonumber(attributes.uid) or (#passwd + 1)

    k.log(k.loglevels.debug, "changing attributes for user " .. attributes.uid)
    
    local current = k.scheduler.info().owner or 0
    
    if not passwd[attributes.uid] then
      assert(attributes.name, "usermod: a username is required")
      assert(attributes.pass, "usermod: a password is required")
      assert(attributes.acls, "usermod: ACL data is required")
      assert(type(attributes.acls) == "table","usermod: ACL data must be a table")
    else
      if attributes.pass and current ~= 0 and current ~= attributes.uid then
        -- only root can change someone else's password
        return nil, "cannot change password: permission denied"
      end
      for k, v in pairs(passwd[attributes.uid]) do
        attributes[k] = attributes[k] or v
      end
    end

    attributes.home = attributes.home or "/home/" .. attributes.name
    k.log(k.loglevels.debug, "shell = " .. attributes.shell)
    attributes.shell = (attributes.shell or "/bin/lsh"):gsub("%.lua$", "")
    k.log(k.loglevels.debug, "shell = " .. attributes.shell)

    local acl = k.security.acl
    if type(attributes.acls) == "table" then
      local acls = 0
      
      for k, v in pairs(attributes.acls) do
        if acl.permissions.user[k] and v then
          acls = acls | acl.permissions.user[k]
          if not acl.user_has_permission(current, acl.permissions.user[k])
              and current ~= 0 then
            return nil, k .. ": ACL permission denied"
          end
        else
          return nil, k .. ": no such ACL"
        end
      end

      attributes.acls = acls
    end

    passwd[tonumber(attributes.uid)] = attributes

    return true
  end

  function api.remove(uid)
    checkArg(1, uid, "number")
    if not passwd[uid] then
      return nil, "no such user"
    end

    if not k.security.acl.user_has_permission(k.scheduler.info().owner,
        k.security.acl.permissions.user.MANAGE_USERS) then
      return nil, "permission denied"
    end

    passwd[uid] = nil
    
    return true
  end
  
  k.security.users = api
end
--#include "base/security/users.lua"
-- access control lists, mostly --

k.log(k.loglevels.info, "base/security/access_control")

do
  -- this implementation of ACLs is fairly basic.
  -- it only supports boolean on-off permissions rather than, say,
  -- allowing users only to log on at certain times of day.
  local permissions = {
    user = {
      SUDO = 1,
      MOUNT = 2,
      OPEN_UNOWNED = 4,
      COMPONENTS = 8,
      HWINFO = 16,
      SETARCH = 32,
      MANAGE_USERS = 64,
      BOOTADDR = 128,
      HOSTNAME = 256,
    },
    file = {
      OWNER_READ = 1,
      OWNER_WRITE = 2,
      OWNER_EXEC = 4,
      GROUP_READ = 8,
      GROUP_WRITE = 16,
      GROUP_EXEC = 32,
      OTHER_READ = 64,
      OTHER_WRITE = 128,
      OTHER_EXEC = 256
    }
  }

  local acl = {}

  acl.permissions = permissions

  function acl.user_has_permission(uid, permission)
    checkArg(1, uid, "number")
    checkArg(2, permission, "number")
  
    local attributes, err = k.security.users.attributes(uid)
    
    if not attributes then
      return nil, err
    end
    
    return acl.has_permission(attributes.acls, permission)
  end

  function acl.has_permission(perms, permission)
    checkArg(1, perms, "number")
    checkArg(2, permission, "number")
    
    return perms & permission ~= 0
  end

  k.security.acl = acl
end
--#include "base/security/access_control.lua"
--#include "base/security.lua"
-- some shutdown related stuff

k.log(k.loglevels.info, "base/shutdown")

do
  local shutdown = computer.shutdown
  
  function k.shutdown(rbt)
    k.is_shutting_down = true
    k.hooks.call("shutdown", rbt)
    k.log(k.loglevels.info, "shutdown: shutting down")
    shutdown(rbt)
  end

  computer.shutdown = k.shutdown
end
--#include "base/shutdown.lua"
-- some component API conveniences

k.log(k.loglevels.info, "base/component")

do
  function component.get(addr, mkpx)
    checkArg(1, addr, "string")
    checkArg(2, mkpx, "boolean", "nil")
    
    for k, v in component.list() do
      if k:sub(1, #addr) == addr then
        return mkpx and component.proxy(k) or k
      end
    end
    
    return nil, "no such component"
  end

  setmetatable(component, {
    __index = function(t, k)
      local addr = component.list(k)()
      if not addr then
        error(string.format("no component of type '%s'", k))
      end
    
      return component.proxy(addr)
    end
  })
end
--#include "base/component.lua"
-- fsapi: VFS and misc filesystem infrastructure

k.log(k.loglevels.info, "base/fsapi")

do
  local fs = {}

  -- common error codes
  fs.errors = {
    file_not_found = "no such file or directory",
    is_a_directory = "is a directory",
    not_a_directory = "not a directory",
    read_only = "target is read-only",
    failed_read = "failed opening file for reading",
    failed_write = "failed opening file for writing",
    file_exists = "file already exists"
  }

  -- standard file types
  fs.types = {
    file = 1,
    directory = 2,
    link = 3,
    special = 4
  }

  -- This VFS should support directory overlays, fs mounting, and directory
  --    mounting, hopefully all seamlessly.
  -- mounts["/"] = { node = ..., children = {["bin"] = "usr/bin", ...}}
  local mounts = {}
  fs.mounts = mounts

  local function split(path)
    local segments = {}
    
    for seg in path:gmatch("[^/]+") do
      if seg == ".." then
        segments[#segments] = nil
      elseif seg ~= "." then
        segments[#segments + 1] = seg
      end
    end
    
    return segments
  end

  fs.split = split

  -- "clean" a path
  local function clean(path)
    return table.concat(split(path), "/")
  end

  local faux = {children = mounts}
  local resolving = {}

  local function resolve(path, must_exist)
    if resolving[path] then
      return nil, "recursive mount detected"
    end
    
    path = clean(path)
    resolving[path] = true

    local current, parent = mounts["/"] or faux

    if not mounts["/"] then
      resolving[path] = nil
      return nil, "root filesystem is not mounted!"
    end

    if path == "" or path == "/" then
      resolving[path] = nil
      return mounts["/"], nil, ""
    end
    
    if current.children[path] then
      resolving[path] = nil
      return current.children[path], nil, ""
    end
    
    local segments = split(path)
    
    local base_n = 1 -- we may have to traverse multiple mounts
    
    for i=1, #segments, 1 do
      local try = table.concat(segments, "/", base_n, i)
    
      if current.children[try] then
        base_n = i + 1 -- we are now at this stage of the path
        local next_node = current.children[try]
      
        if type(next_node) == "string" then
          local err
          next_node, err = resolve(next_node)
        
          if not next_node then
            resolving[path] = false
            return nil, err
          end
        end
        
        parent = current
        current = next_node
      elseif not current.node:stat(try) then
        resolving[path] = false

        return nil, fs.errors.file_not_found
      end
    end
    
    resolving[path] = false
    local ret = "/"..table.concat(segments, "/", base_n, #segments)
    
    if must_exist and not current.node:stat(ret) then
      return nil, fs.errors.file_not_found
    end
    
    return current, parent, ret
  end

  local registered = {partition_tables = {}, filesystems = {}}

  local _managed = {}
  function _managed:info()
    return {
      read_only = self.node.isReadOnly(),
      address = self.node.address
    }
  end

  function _managed:stat(file)
    checkArg(1, file, "string")

    if not self.node.exists(file) then
      return nil, fs.errors.file_not_found
    end
    
    local info = {
      permissions = self:info().read_only and 365 or 511,
      type        = self.node.isDirectory(file) and fs.types.directory or fs.types.file,
      isDirectory = self.node.isDirectory(file),
      owner       = -1,
      group       = -1,
      lastModified= self.node.lastModified(file),
      size        = self.node.size(file)
    }

    if file:sub(1, -4) == ".lua" then
      info.permissions = info.permissions | k.security.acl.permissions.file.OWNER_EXEC
      info.permissions = info.permissions | k.security.acl.permissions.file.GROUP_EXEC
      info.permissions = info.permissions | k.security.acl.permissions.file.OTHER_EXEC
    end

    return info
  end

  function _managed:touch(file, ftype)
    checkArg(1, file, "string")
    checkArg(2, ftype, "number", "nil")
    
    if self.node.isReadOnly() then
      return nil, fs.errors.read_only
    end
    
    if self.node.exists(file) then
      return nil, fs.errors.file_exists
    end
    
    if ftype == fs.types.file or not ftype then
      local fd = self.node.open(file, "w")
    
      if not fd then
        return nil, fs.errors.failed_write
      end
      
      self.node.write(fd, "")
      self.node.close(fd)
    elseif ftype == fs.types.directory then
      local ok, err = self.node.makeDirectory(file)
      
      if not ok then
        return nil, err or "unknown error"
      end
    elseif ftype == fs.types.link then
      return nil, "unsupported operation"
    end
    
    return true
  end
  
  function _managed:remove(file)
    checkArg(1, file, "string")
    
    if not self.node.exists(file) then
      return nil, fs.errors.file_not_found
    end
    
    if self.node.isDirectory(file) and #(self.node.list(file) or {}) > 0 then
      return nil, fs.errors.is_a_directory
    end
    
    return self.node.remove(file)
  end

  function _managed:list(path)
    checkArg(1, path, "string")
    
    if not self.node.exists(path) then
      return nil, fs.errors.file_not_found
    elseif not self.node.isDirectory(path) then
      return nil, fs.errors.not_a_directory
    end
    
    local files = self.node.list(path) or {}
    
    return files
  end
  
  local function fread(s, n)
    return s.node.read(s.fd, n)
  end

  local function fwrite(s, d)
    return s.node.write(s.fd, d)
  end

  local function fseek(s, w, o)
    return s.node.seek(s.fd, w, o)
  end

  local function fclose(s)
    return s.node.close(s.fd)
  end

  function _managed:open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
    
    if (mode == "r" or mode == "a") and not self.node.exists(file) then
      return nil, fs.errors.file_not_found
    end
    
    local fd = {
      fd = self.node.open(file, mode or "r"),
      node = self.node,
      read = fread,
      write = fwrite,
      seek = fseek,
      close = fclose
    }
    
    return fd
  end
  
  local fs_mt = {__index = _managed}
  local function create_node_from_managed(proxy)
    return setmetatable({node = proxy}, fs_mt)
  end

  local function create_node_from_unmanaged(proxy)
    local fs_superblock = proxy.readSector(1)
    
    for k, v in pairs(registered.filesystems) do
      if v.is_valid_superblock(superblock) then
        return v.new(proxy)
      end
    end
    
    return nil, "no compatible filesystem driver available"
  end

  fs.PARTITION_TABLE = "partition_tables"
  fs.FILESYSTEM = "filesystems"
  
  function fs.register(category, driver)
    if not registered[category] then
      return nil, "no such category: " .. category
    end
  
    table.insert(registered[category], driver)
    return true
  end

  function fs.get_partition_table_driver(filesystem)
    checkArg(1, filesystem, "string", "table")
    
    if type(filesystem) == "string" then
      filesystem = component.proxy(filesystem)
    end
    
    if filesystem.type == "filesystem" then
      return nil, "managed filesystem has no partition table"
    else -- unmanaged drive - perfect
      for k, v in pairs(registered.partition_tables) do
        if v.has_valid_superblock(proxy) then
          return v.create(proxy)
        end
      end
    end
    
    return nil, "no compatible partition table driver available"
  end

  function fs.get_filesystem_driver(filesystem)
    checkArg(1, filesystem, "string", "table")
    
    if type(filesystem) == "string" then
      filesystem = component.proxy(filesystem)
    end
    
    if filesystem.type == "filesystem" then
      return create_node_from_managed(filesystem)
    else
      return create_node_from_unmanaged(filesystem)
    end
  end

  -- actual filesystem API now
  fs.api = {}
  
  function fs.api.open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
  
    mode = mode or "r"

    if mode:match("[wa]") then
      fs.api.touch(file)
    end

    local node, err, path = resolve(file)
    if not node then
      return nil, err
    end
    
    local data = node.node:stat(path)
    local user = (k.scheduler.info() or {owner=0}).owner
    -- TODO: groups
    
    do
      local perms = k.security.acl.permissions.file
      local rperm, wperm
    
      if data.owner ~= user then
        rperm = perms.OTHER_READ
        wperm = perms.OTHER_WRITE
      else
        rperm = perms.OWNER_READ
        wperm = perms.OWNER_WRITE
      end
      
      if ((mode == "r" and not
          k.security.acl.has_permission(data.permissions, rperm)) or
          ((mode == "w" or mode == "a") and not
          k.security.acl.has_permission(data.permissions, wperm))) and not
          k.security.acl.user_has_permission(user,
          k.security.acl.permissions.OPEN_UNOWNED) then
        return nil, "permission denied"
      end
    end
    
    return node.node:open(path, mode)
  end

  function fs.api.stat(file)
    checkArg(1, file, "string")
    
    local node, err, path = resolve(file)
    
    if not node then
      return nil, err
    end

    return node.node:stat(path)
  end

  function fs.api.touch(file, ftype)
    checkArg(1, file, "string")
    checkArg(2, ftype, "number", "nil")
    
    ftype = ftype or fs.types.file
    
    local root, base = file:match("^(/?.+)/([^/]+)/?$")
    root = root or "/"
    base = base or file
    
    local node, err, path = resolve(root)
    
    if not node then
      return nil, err
    end
    
    return node.node:touch(path .. "/" .. base, ftype)
  end

  local n = {}
  function fs.api.list(path)
    checkArg(1, path, "string")
    
    local node, err, fpath = resolve(path, true)

    if not node then
      return nil, err
    end

    local ok, err = node.node:list(fpath)
    if not ok and err then
      return nil, err
    end

    ok = ok or {}
    local used = {}
    for _, v in pairs(ok) do used[v] = true end

    if node.children then
      for k in pairs(node.children) do
        if not k:match(".+/.+") then
          local info = fs.api.stat(path.."/"..k)
          if (info or n).isDirectory then
            k = k .. "/"
          end
          if info and not used[k] then
            ok[#ok + 1] = k
          end
        end
      end
    end
   
    return ok
  end

  function fs.api.remove(file)
    checkArg(1, file, "string")
    
    local node, err, path = resolve(file)
    
    if not node then
      return nil, err
    end
    
    return node.node:remove(path)
  end

  local mounted = {}

  fs.api.types = {
    RAW = 0,
    NODE = 1,
    OVERLAY = 2,
  }
  
  function fs.api.mount(node, fstype, path)
    checkArg(1, node, "string", "table")
    checkArg(2, fstype, "number")
    checkArg(2, path, "string")
    
    local device, err = node
    
    if fstype ~= fs.api.types.RAW then
      -- TODO: properly check object methods first
      goto skip
    end
    
    device, err = fs.get_filesystem_driver(node)
    if not device then
      local sdev, serr = k.sysfs.retrieve(node)
      if not sdev then return nil, serr end
      device, err = fs.get_filesystem_driver(sdev)
    end
    
    ::skip::

    if type(device) == "string" and fstype ~= fs.types.OVERLAY then
      device = component.proxy(device)
      if (not device) then
        return nil, "no such component"
      elseif device.type ~= "filesystem" and device.type ~= "drive" then
        return nil, "component is not a drive or filesystem"
      end

      if device.type == "filesystem" then
        device = create_node_from_managed(device)
      else
        device = create_node_from_unmanaged(device)
      end
    end

    if not device then
      return nil, err
    end

    if device.type == "filesystem" then
    end
    
    path = clean(path)
    if path == "" then path = "/" end
    
    local root, fname = path:match("^(/?.+)/([^/]+)/?$")
    root = root or "/"
    fname = fname or path
    
    local pnode, err, rpath
    
    if path == "/" then
      mounts["/"] = {node = device, children = {}}
      mounted["/"] = (device.node and device.node.getLabel
        and device.node.getLabel()) or device.node
        and device.node.address or "unknown"
      return true
    else
      pnode, err, rpath = resolve(root)
    end

    if not pnode then
      return nil, err
    end
    
    local full = clean(string.format("%s/%s", rpath, fname))
    if full == "" then full = "/" end

    if type(device) == "string" then
      pnode.children[full] = device
    else
      pnode.children[full] = {node=device, children={}}
      mounted[path]=(device.node and device.node.getLabel
        and device.node.getLabel()) or device.node
        and device.node.address or "unknown"
    end
    
    return true
  end

  function fs.api.umount(path)
    checkArg(1, path, "string")
    
    path = clean(path)
    
    local root, fname = path:match("^(/?.+)/([^/]+)/?$")
    root = root or "/"
    fname = fname or path
    
    local node, err, rpath = resolve(root)
    
    if not node then
      return nil, err
    end
    
    local full = clean(string.format("%s/%s", rpath, fname))
    node.children[full] = nil
    mounted[path] = nil
    
    return true
  end

  function fs.api.mounts()
    local new = {}
    -- prevent programs from meddling with these
    for k,v in pairs(mounted) do new[("/"..k):gsub("[\\/]+", "/")] = v end
    return new
  end

  k.fs = fs
end
--#include "base/fsapi.lua"
-- the Lua standard library --

-- stdlib: os

do
  function os.execute()
    error("os.execute must be implemented by userspace", 0)
  end

  function os.setenv(K, v)
    local info = k.scheduler.info()
    info.data.env[K] = v
  end

  function os.getenv(K)
    local info = k.scheduler.info()
    
    if not K then
      return info.data.env
    end

    return info.data.env[K]
  end

  function os.sleep(n)
    checkArg(1, n, "number")

    local max = computer.uptime() + n
    repeat
      coroutine.yield(max - computer.uptime())
    until computer.uptime() >= max

    return true
  end

  function os.exit(n)
    checkArg(1, n, "number", "nil")
    n = n or 0
    coroutine.yield("__internal_process_exit", n)
  end
end
--#include "base/stdlib/os.lua"
-- implementation of the FILE* API --

k.log(k.loglevels.info, "base/stdlib/FILE*")

do
  local buffer = {}
 
  function buffer:read_byte()
    if self.buffer_mode ~= "none" then
      if (not self.read_buffer) or #self.read_buffer == 0 then
        self.read_buffer = self.base:read(self.buffer_size)
      end
  
      if not self.read_buffer then
        self.closed = true
        return nil
      end
      
      local dat = self.read_buffer:sub(1,1)
      self.read_buffer = self.read_buffer:sub(2, -1)
      
      return dat
    else
      return self.base:read(1)
    end
  end

  function buffer:write_byte(byte)
    if self.buffer_mode ~= "none" then
      if #self.write_buffer >= self.buffer_size then
        self.base:write(self.write_buffer)
        self.write_buffer = ""
      end
      
      self.write_buffer = string.format("%s%s", self.write_buffer, byte)
    else
      return self.base:write(byte)
    end

    return true
  end

  function buffer:read_line()
    local line = ""
    
    repeat
      local c = self:read_byte()
      line = line .. (c or "")
    until c == "\n" or not c
    
    return line
  end

  local valid = {
    a = true,
    l = true,
    L = true,
    n = true
  }

  function buffer:read_formatted(fmt)
    checkArg(1, fmt, "string", "number")
    
    if type(fmt) == "number" then
      if fmt == 0 then return "" end
      local read = ""
    
      repeat
        local byte = self:read_byte()
        read = read .. (byte or "")
      until #read >= fmt or not byte
      
      return read
    else
      fmt = fmt:gsub("%*", ""):sub(1,1)
      
      if #fmt == 0 or not valid[fmt] then
        error("bad argument to 'read' (invalid format)")
      end
      
      if fmt == "l" or fmt == "L" then
        local line = self:read_line()
      
        if fmt == "l" then
          line = line:sub(1, -2)
        end
        
        return line
      elseif fmt == "a" then
        local read = ""
        
        repeat
          local byte = self:read_byte()
          read = read .. (byte or "")
        until not byte
        
        return read
      elseif fmt == "n" then
        local read = ""
        
        repeat
          local byte = self:read_byte()
          if not tonumber(byte) then
            -- TODO: this breaks with no buffering
            self.read_buffer = byte .. self.read_buffer
          else
            read = read .. (byte or "")
          end
        until not tonumber(byte)
        
        return tonumber(read)
      end

      error("bad argument to 'read' (invalid format)")
    end
  end

  function buffer:read(...)
    if self.closed or not self.mode.r then
      return nil, "bad file descriptor"
    end
    
    local args = table.pack(...)
    if args.n == 0 then args[1] = "l" args.n = 1 end
    
    local read = {}
    for i=1, args.n, 1 do
      read[i] = self:read_formatted(args[i])
    end
    
    return table.unpack(read)
  end

  function buffer:lines(format)
    format = format or "l"
    
    return function()
      return self:read(format)
    end
  end

  function buffer:write(...)
    if self.closed then
      return nil, "bad file descriptor"
    end
    
    local args = table.pack(...)
    local write = ""
    
    for i=1, #args, 1 do
      checkArg(i, args[i], "string", "number")
    
      args[i] = tostring(args[i])
      write = string.format("%s%s", write, args[i])
    end
    
    if self.buffer_mode == "none" then
      -- a-ha! performance shortcut!
      -- because writing in a chunk is much faster
      return self.base:write(write)
    end

    for i=1, #write, 1 do
      local char = write:sub(i,i)
      self:write_byte(char)
    end

    return true
  end

  function buffer:seek(whence, offset)
    checkArg(1, whence, "string")
    checkArg(2, offset, "number")
    
    if self.closed then
      return nil, "bad file descriptor"
    end
    
    self:flush()
    return self.base:seek()
  end

  function buffer:flush()
    if self.closed then
      return nil, "bad file descriptor"
    end
    
    if #self.write_buffer > 0 then
      self.base:write(self.write_buffer)
      self.write_buffer = ""
    end

    if self.base.flush then
      self.base:flush()
    end
    
    return true
  end

  function buffer:close()
    self:flush()
    self.closed = true
  end

  local fmt = {
    __index = buffer,
    -- __metatable = {},
    __name = "FILE*"
  }

  function k.create_fstream(base, mode)
    checkArg(1, base, "table")
    checkArg(2, mode, "string")
  
    local new = {
      base = base,
      buffer_size = 512,
      read_buffer = "",
      write_buffer = "",
      buffer_mode = "standard", -- standard, line, none
      closed = false,
      mode = {}
    }
    
    for c in mode:gmatch(".") do
      new.mode[c] = true
    end
    
    setmetatable(new, fmt)
    return new
  end
end
--#include "base/stdlib/FILE.lua"
-- io library --

k.log(k.loglevels.info, "base/stdlib/io")

do
  local fs = k.fs.api
  local im = {stdin = 0, stdout = 1, stderr = 2}
 
  local mt = {
    __index = function(t, f)
      if not k.scheduler then return k.logio end
      local info = k.scheduler.info()
  
      if info and info.data and info.data.io then
        return info.data.io[f]
      end
      
      return nil
    end,
    __newindex = function(t, f, v)
      local info = k.scheduler.info()
      if not info then return nil end
      info.data.io[f] = v
      info.data.handles[im[f]] = v
    end
  }

  _G.io = {}
  
  function io.open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
  
    mode = mode or "r"

    local handle, err = fs.open(file, mode)
    if not handle then
      return nil, err
    end

    local fstream = k.create_fstream(handle, mode)

    local info = k.scheduler.info()
    if info then
      info.data.handles[#info.data.handles + 1] = fstream
      fstream.n = #info.data.handles
      
      local close = fstream.close
      function fstream:close()
        close(self)
        info.data.handles[self.n] = nil
      end
    end
    
    return fstream
  end

  -- popen should be defined in userspace so the shell can handle it.
  -- tmpfile should be defined in userspace also.
  -- it turns out that defining things PUC Lua can pass off to the shell
  -- *when you don't have a shell* is rather difficult and so, instead of
  -- weird hacks like in Paragon or Monolith, I just leave it up to userspace.
  function io.popen()
    return nil, "io.popen unsupported at kernel level"
  end

  function io.tmpfile()
    return nil, "io.tmpfile unsupported at kernel level"
  end

  function io.read(...)
    return io.input():read(...)
  end

  function io.write(...)
    return io.output():write(...)
  end

  function io.lines(file, fmt)
    file = file or io.stdin

    if type(file) == "string" then
      file = assert(io.open(file, "r"))
    end
    
    checkArg(1, file, "FILE*")
    
    return file:lines(fmt)
  end

  local function stream(kk)
    return function(v)
      if v then checkArg(1, v, "FILE*") end

      if not k.scheduler.info() then
        return k.logio
      end
      local t = k.scheduler.info().data.io
    
      if v then
        t[kk] = v
      end
      
      return t[kk]
    end
  end

  io.input = stream("input")
  io.output = stream("output")

  function io.type(stream)
    assert(stream, "bad argument #1 (value expected)")
    
    if type(stream) == "FILE*" then
      if stream.closed then
        return "closed file"
      end
    
      return "file"
    end

    return nil
  end

  function io.flush(s)
    s = s or io.stdout
    checkArg(1, s, "FILE*")

    return s:flush()
  end

  function io.close(stream)
    checkArg(1, stream, "FILE*")

    if stream == io.stdin or stream == io.stdout or stream == io.stderr then
      return nil, "cannot close standard file"
    end
    
    return stream:close()
  end

  setmetatable(io, mt)
  k.hooks.add("sandbox", function()
    setmetatable(k.userspace.io, mt)
  end)

  function _G.print(...)
    local args = table.pack(...)
   
    for i=1, args.n, 1 do
      args[i] = tostring(args[i])
    end
    
    return (io.stdout or k.logio):write(
      table.concat(args, "  ", 1, args.n), "\n")
  end
end
--#include "base/stdlib/io.lua"
-- package API.  this is probably the lib i copy-paste the most. --

k.log(k.loglevels.info, "base/stdlib/package")

do
  _G.package = {}
 
  local loaded = {
    os = os,
    io = io,
    math = math,
    string = string,
    table = table,
    users = k.users,
    sha3 = k.sha3,
    unicode = unicode
  }
  
  package.loaded = loaded
  package.path = "/lib/?.lua;/lib/lib?.lua;/lib/?/init.lua;/usr/lib/?.lua;/usr/lib/lib?.lua;/usr/lib/?/init.lua"
  
  local fs = k.fs.api

  local function libError(name, searched)
    local err = "module '%s' not found:\n\tno field package.loaded['%s']"
    err = err .. ("\n\tno file '%s'"):rep(#searched)
  
    return string.format(err, name, name, table.unpack(searched))
  end

  function package.searchpath(name, path, sep, rep)
    checkArg(1, name, "string")
    checkArg(2, path, "string")
    checkArg(3, sep, "string", "nil")
    checkArg(4, rep, "string", "nil")
    
    sep = "%" .. (sep or ".")
    rep = rep or "/"
    
    local searched = {}
    
    name = name:gsub(sep, rep)
    
    for search in path:gmatch("[^;]+") do
      search = search:gsub("%?", name)
    
      if fs.stat(search) then
        return search
      end
      
      searched[#searched + 1] = search
    end

    return nil, libError(name, searched)
  end

  package.protect = k.util.protect

  function package.delay(lib, file)
    local mt = {
      __index = function(tbl, key)
        setmetatable(lib, nil)
        setmetatable(lib.internal or {}, nil)
        ; -- this is just in case, because Lua is weird
        (k.userspace.dofile or dofile)(file)
    
        return tbl[key]
      end
    }

    if lib.internal then
      setmetatable(lib.internal, mt)
    end
    
    setmetatable(lib, mt)
  end

  -- let's define this here because WHY NOT
  function _G.loadfile(file, mode, env)
    checkArg(1, file, "string")
    checkArg(2, mode, "string", "nil")
    checkArg(3, env, "table", "nil")
    
    local handle, err = io.open(file, "r")
    if not handle then
      return nil, err
    end
    
    local data = handle:read("a")
    handle:close()

    return load(data, "="..file, "bt", env or k.userspace or _G)
  end

  function _G.dofile(file)
    checkArg(1, file, "string")
    
    local ok, err = loadfile(file)
    if not ok then
      error(err, 0)
    end
    
    local stat, ret = xpcall(ok, debug.traceback)
    if not stat and ret then
      error(ret, 0)
    end
    
    return ret
  end

  local k = k
  k.hooks.add("sandbox", function()
    k.userspace.k = nil
    
    local acl = k.security.acl
    local perms = acl.permissions
    
    local function wrap(f, p)
      return function(...)
        if not acl.user_has_permission(k.scheduler.info().owner,
            p) then
          error("permission denied")
        end
    
        return f(...)
      end
    end

    k.userspace.component = nil
    k.userspace.computer = nil
    k.userspace.unicode = nil

    k.userspace.package.loaded.component = {}
    
    for f,v in pairs(component) do
      k.userspace.package.loaded.component[f] = wrap(v,
        perms.user.COMPONENTS)
    end
    
    k.userspace.package.loaded.computer = {
      getDeviceInfo = wrap(computer.getDeviceInfo, perms.user.HWINFO),
      setArchitecture = wrap(computer.setArchitecture, perms.user.SETARCH),
      addUser = wrap(computer.addUser, perms.user.MANAGE_USERS),
      removeUser = wrap(computer.removeUser, perms.user.MANAGE_USERS),
      setBootAddress = wrap(computer.setBootAddress, perms.user.BOOTADDR),
      pullSignal = coroutine.yield,
      pushSignal = function(...)
        return k.scheduler.info().data.self:push_signal(...)
      end
    }
    
    for f, v in pairs(computer) do
      k.userspace.package.loaded.computer[f] =
        k.userspace.package.loaded.computer[f] or v
    end
    
    k.userspace.package.loaded.unicode = k.util.copy_table(unicode)
    k.userspace.package.loaded.filesystem = k.util.copy_table(k.fs.api)
    
    local ufs = k.userspace.package.loaded.filesystem
    ufs.mount = wrap(k.fs.api.mount, perms.user.MOUNT)
    ufs.umount = wrap(k.fs.api.umount, perms.user.MOUNT)
    
    k.userspace.package.loaded.filetypes = k.util.copy_table(k.fs.types)

    k.userspace.package.loaded.users = k.util.copy_table(k.security.users)

    k.userspace.package.loaded.acls = k.util.copy_table(k.security.acl.permissions)

    local blacklist = {}
    for k in pairs(k.userspace.package.loaded) do blacklist[k] = true end

    local shadow = k.userspace.package.loaded
    k.userspace.package.loaded = setmetatable({}, {
      __newindex = function(t, k, v)
        if shadow[k] and blacklist[k] then
          error("cannot override protected library " .. k, 0)
        else
          shadow[k] = v
        end
      end,
      __index = shadow,
      __pairs = shadow,
      __ipairs = shadow,
      __metatable = {}
    })

    local loaded = k.userspace.package.loaded
    local loading = {}
    function k.userspace.require(module)
      if loaded[module] then
        return loaded[module]
      elseif not loading[module] then
        local library, status, step
  
        step, library, status = "not found",
            package.searchpath(module, package.path)
  
        if library then
          step, library, status = "loadfile failed", loadfile(library)
        end
  
        if library then
          loading[module] = true
          step, library, status = "load failed", pcall(library, module)
          loading[module] = false
        end
  
        assert(library, string.format("module '%s' %s:\n%s",
            module, step, status))
  
        loaded[module] = status
        return status
      else
        error("already loading: " .. module .. "\n" .. debug.traceback(), 2)
      end
    end
  end)
end
--#include "base/stdlib/package.lua"
--#include "base/stdlib.lua"
-- custom types

k.log(k.loglevels.info, "base/types")

do
  local old_type = type
  function _G.type(obj)
    if old_type(obj) == "table" then
      local s, mt = pcall(getmetatable, obj)
      
      if not s and mt then
        -- getting the metatable failed, so it's protected.
        -- instead, we should tostring() it - if the __name
        -- field is set, we can let the Lua VM get the
        -- """type""" for us.
        local t = tostring(obj):gsub(" [%x+]$", "")
        return t
      end
       
      -- either there is a metatable or ....not. If
      -- we have gotten this far, the metatable was
      -- at least not protected, so we can carry on
      -- as normal.  And yes, i have put waaaay too
      -- much effort into making this comment be
      -- almost a rectangular box :)
      mt = mt or {}
 
      return mt.__name or mt.__type or old_type(obj)
    else
      return old_type(obj)
    end
  end

  -- ok time for cursed shit: aliasing one type to another
  -- i will at least blacklist the default Lua types
  local cannot_alias = {
    string = true,
    number = true,
    boolean = true,
    ["nil"] = true,
    ["function"] = true,
    table = true,
    userdata = true
  }
  local defs = {}
  
  -- ex. typedef("number", "int")
  function _G.typedef(t1, t2)
    checkArg(1, t1, "string")
    checkArg(2, t2, "string")
  
    if cannot_alias[t2] then
      error("attempt to override default type")
    end

    if defs[t2] then
      error("cannot override existing typedef")
    end
    
    defs[t2] = t1
    
    return true
  end

  -- copied from machine.lua
  function _G.checkArg(n, have, ...)
    have = type(have)
    
    local function check(want, ...)
      if not want then
        return false
      else
        return have == want or defs[want] == have or check(...)
      end
    end
    
    if not check(...) then
      local msg = string.format("bad argument #%d (%s expected, got %s)",
                                n, table.concat(table.pack(...), " or "), have)
      error(msg, 3)
    end
  end
end
--#include "base/types.lua"
-- binary struct
-- note that to make something unsigned you ALWAYS prefix the type def with
-- 'u' rather than 'unsigned ' due to Lua syntax limitations.
-- ex:
-- local example = struct {
--   uint16("field_1"),
--   string[8]("field_2")
-- }
-- local copy = example "\0\14A string"
-- yes, there is lots of metatable hackery behind the scenes

k.log(k.loglevels.info, "ksrc/struct")

do
  -- step 1: change the metatable of _G so we can have convenient type notation
  -- without technically cluttering _G
  local gmt = {}
  
  local types = {
    int = "i",
    uint = "I",
    bool = "b", -- currently booleans are just signed 8-bit values because reasons
    short = "h",
    ushort = "H",
    long = "l",
    ulong = "L",
    size_t = "T",
    float = "f",
    double = "d",
    lpstr = "s",
  }

  -- char is a special case:
  --   - the user may want a single byte (char("field"))
  --   - the user may also want a fixed-length string (char[42]("field"))
  local char = {}
  setmetatable(char, {
    __call = function(field)
      return {fmtstr = "B", field = field}
    end,
    __index = function(t, k)
      if type(k) == "number" then
        return function(value)
          return {fmtstr = "c" .. k, field = value}
        end
      else
        error("invalid char length specifier")
      end
    end
  })

  function gmt.__index(t, k)
    if k == "char" then
      return char
    else
      local tp
  
      for t, v in pairs(types) do
        local match = k:match("^"..t)
        if match then tp = t break end
      end
      
      if not tp then return nil end
      
      return function(value)
        return {fmtstr = types[tp] .. tonumber(k:match("%d+$") or "0")//8,
          field = value}
      end
    end
  end

  -- step 2: change the metatable of string so we can have string length
  -- notation.  Note that this requires a null-terminated string.
  local smt = {}

  function smt.__index(t, k)
    if type(k) == "number" then
      return function(value)
        return {fmtstr = "z", field = value}
      end
    end
  end

  -- step 3: apply these metatable hacks
  setmetatable(_G, gmt)
  setmetatable(string, smt)

  -- step 4: ???

  -- step 5: profit

  function struct(fields, name)
    checkArg(1, fields, "table")
    checkArg(2, name, "string", "nil")
    
    local pat = "<"
    local args = {}
    
    for i=1, #fields, 1 do
      local v = fields[i]
      pat = pat .. v.fmtstr
      args[i] = v.field
    end
  
    return setmetatable({}, {
      __call = function(_, data)
        assert(type(data) == "string" or type(data) == "table",
          "bad argument #1 to struct constructor (string or table expected)")
    
        if type(data) == "string" then
          local set = table.pack(string.unpack(pat, data))
          local ret = {}
        
          for i=1, #args, 1 do
            ret[args[i]] = set[i]
          end
          
          return ret
        elseif type(data) == "table" then
          local set = {}
          
          for i=1, #args, 1 do
            set[i] = data[args[i]]
          end
          
          return string.pack(pat, table.unpack(set))
        end
      end,
      __len = function()
        return string.packsize(pat)
      end,
      __name = name or "struct"
    })
  end
end
--#include "base/struct.lua"
-- system log API hook for userspace

k.log(k.loglevels.info, "base/syslog")

do
  local mt = {
    __name = "syslog"
  }

  local syslog = {}
  local open = {}

  function syslog.open(pname)
    checkArg(1, pname, "string", "nil")

    pname = pname or k.scheduler.info().name

    local n = math.random(1, 999999999)
    open[n] = pname
    
    return n
  end

  function syslog.write(n, ...)
    checkArg(1, n, "number")
    
    if not open[n] then
      return nil, "bad file descriptor"
    end
    
    k.log(k.loglevels.info, open[n] .. ":", ...)

    return true
  end

  function syslog.close(n)
    checkArg(1, n, "number")
    
    if not open[n] then
      return nil, "bad file descriptor"
    end
    
    open[n] = nil

    return true
  end

  k.hooks.add("sandbox", function()
    k.userspace.package.loaded.syslog = k.util.copy_table(syslog)
  end)
end
--#include "base/syslog.lua"
-- wrap load() to forcibly insert yields --

k.log(k.loglevels.info, "base/load")

if (not k.cmdline.no_force_yields) then
  local patterns = {
    --[[
    { "if([ %(])(.-)([ %)])then([ \n])", "if%1%2%3then%4__internal_yield() " },
    { "elseif([ %(])(.-)([ %)])then([ \n])", "elseif%1%2%3then%4__internal_yield() " },
    { "([ \n])else([ \n])", "%1else%2__internal_yield() " },]]
    { "while([ %(])(.-)([ %)])do([ \n])", "while%1%2%3do%4__internal_yield() "},
    { "for([ %(])(.-)([ %)])do([ \n])", "for%1%2%3do%4__internal_yield() " },
    { "repeat([ \n])", "repeat%1__internal_yield() " },
  }

  local old_load = load

  local max_time = tonumber(k.cmdline.max_process_time) or 0.1

  local function process_section(s)
    for i=1, #patterns, 1 do
      s = s:gsub(patterns[i][1], patterns[i][2])
    end
    return s
  end

  local function process(chunk)
    local i = 1
    local ret = ""
    local nq = 0
    local in_blocks = {}
    while true do
      local nextquote = chunk:find("[^\\][\"']", i)
      if nextquote then
        local ch = chunk:sub(i, nextquote)
        i = nextquote + 1
        nq = nq + 1
        if nq % 2 == 1 then
          ch = process_section(ch)
        end
        ret = ret .. ch
      else
        local nbs, nbe = chunk:find("%[=*%[", i)
        if nbs and nbe then
          ret = ret .. process_section(chunk:sub(i, nbs - 1))
          local match = chunk:find("%]" .. ("="):rep((nbe - nbs) - 1) .. "%]")
          if not match then
            -- the Lua parser will error here, no point in processing further
            ret = ret .. chunk:sub(nbs)
            break
          end
          local ch = chunk:sub(nbs, match)
          ret = ret .. ch --:sub(1,-2)
          i = match + 1
        else
          ret = ret .. process_section(chunk:sub(i))
          i = #chunk
          break
        end
      end
    end

    if i < #chunk then ret = ret .. process_section(chunk:sub(i)) end

    return ret
  end

  function _G.load(chunk, name, mode, env)
    checkArg(1, chunk, "function", "string")
    checkArg(2, name, "string", "nil")
    checkArg(3, mode, "string", "nil")
    checkArg(4, env, "table", "nil")

    local data = ""
    if type(chunk) == "string" then
      data = chunk
    else
      repeat
        local ch = chunk()
        data = data .. (ch or "")
      until not ch
    end

    chunk = process(chunk)

    if k.cmdline.debug_load then
      local handle = io.open("/load.txt", "a")
      handle:write(" -- load: ", name or "(no name)", " --\n", chunk)
      handle:close()
    end

    env = env or k.userspace or _G

    local ok, err = old_load(chunk, name, mode, env)
    if not ok then
      return nil, err
    end
    
    local ysq = {}
    return function(...)
      local last_yield = computer.uptime()
      local old_iyield = env.__internal_yield
      local old_cyield = env.coroutine.yield
      
      env.__internal_yield = function()
        if computer.uptime() - last_yield >= max_time then
          last_yield = computer.uptime()
          local msg = table.pack(old_cyield(0.05))
          if msg.n > 0 then ysq[#ysq+1] = msg end
        end
      end
      
      env.coroutine.yield = function(...)
        if #ysq > 0 then
          return table.unpack(table.remove(ysq, 1))
        end
        last_yield = computer.uptime()
        local msg = table.pack(old_cyield(...))
        ysq[#ysq+1] = msg
        return table.unpack(table.remove(ysq, 1))
      end
      
      local result = table.pack(ok(...))
      env.__internal_yield = old_iyield
      env.coroutine.yield = old_cyield

      return table.unpack(result)
    end
  end
end
--#include "base/load.lua"
-- thread: wrapper around coroutines

k.log(k.loglevels.info, "base/thread")

do
  local function handler(err)
    return debug.traceback(err, 3)
  end

  local old_coroutine = coroutine
  local _coroutine = {}
  _G.coroutine = _coroutine
  if k.cmdline.no_wrap_coroutine then
    k.hooks.add("sandbox", function()
      k.userspace.coroutine = old_coroutine
    end)
  end
  
  function _coroutine.create(func)
    checkArg(1, func, "function")
  
    return setmetatable({
      __thread = old_coroutine.create(function()
        return select(2, k.util.lassert(xpcall(func, handler)))
      end)
    }, {
      __index = _coroutine,
      __name = "thread"
    })
  end

  function _coroutine.wrap(fnth)
    checkArg(1, fnth, "function", "thread")
    
    if type(fnth) == "function" then fnth = _coroutine.create(fnth) end
    
    return function(...)
      return select(2, fnth:resume(...))
    end
  end

  function _coroutine:resume(...)
    return old_coroutine.resume(self.__thread, ...)
  end

  function _coroutine:status()
    return old_coroutine.status(self.__thread)
  end

  for k,v in pairs(old_coroutine) do
    _coroutine[k] = _coroutine[k] or v
  end
end
--#include "base/thread.lua"
-- processes
-- mostly glorified coroutine sets

k.log(k.loglevels.info, "base/process")

do
  local process = {}
  local proc_mt = {
    __index = process,
    __name = "process"
  }

  function process:resume(...)
    local result
    for k, v in ipairs(self.threads) do
      result = result or table.pack(v:resume(...))
  
      if v:status() == "dead" then
        table.remove(self.threads, k)
      
        if not result[1] then
          self:push_signal("thread_died", v.id)
        
          return nil, result[2]
        end
      end
    end

    if not next(self.threads) then
      self.dead = true
    end
    
    return table.unpack(result)
  end

  local id = 0
  function process:add_thread(func)
    checkArg(1, func, "function")
    
    local new = coroutine.create(func)
    
    id = id + 1
    new.id = id
    
    self.threads[#self.threads + 1] = new
    
    return id
  end

  function process:status()
    return self.coroutine:status()
  end

  local c_pushSignal = computer.pushSignal
  
  function process:push_signal(...)
    local signal = table.pack(...)
    table.insert(self.queue, signal)
    return true
  end

  -- there are no timeouts, the scheduler manages that
  function process:pull_signal()
    if #self.queue > 0 then
      return table.remove(self.queue, 1)
    end
  end

  local pid = 0

  -- default signal handlers
  local defaultHandlers = {
    [0] = function() end,
    [1] = function(self) self.status = "" self.dead = true end,
    [2] = function(self) self.status = "interrupted" self.dead = true end,
    [9] = function(self) self.dead = true end,
    [18] = function(self) self.stopped = true end,
  }
  
  function k.create_process(args)
    pid = pid + 1
  
    local new
    new = setmetatable({
      name = args.name,
      pid = pid,
      io = {
        stdin = args.stdin or {},
        input = args.input or args.stdin or {},
        stdout = args.stdout or {},
        output = args.output or args.stdout or {},
        stderr = args.stderr or args.stdout or {}
      },
      queue = {},
      threads = {},
      waiting = true,
      stopped = false,
      handles = {},
      coroutine = {},
      cputime = 0,
      deadline = 0,
      env = args.env and k.util.copy_table(args.env) or {},
      signal = setmetatable({}, {
        __call = function(_, self, s)
          -- don't block SIGSTOP or SIGCONT
          if s == 17 or s == 19 then
            self.stopped = s == 17
            return true
          end
          -- and don't block SIGKILL, unless we're init
          if self.pid ~= 1 and s == 9 then
            self.status = "killed" self.dead = true return true end
          if self.signal[s] then
            return self.signal[s](self)
          else
            return (defaultHandlers[s] or defaultHandlers[0])(self)
          end
        end,
        __index = defaultHandlers
      })
    }, proc_mt)
    
    args.stdin, args.stdout, args.stderr,
                  args.input, args.output = nil, nil, nil, nil, nil
    
    for k, v in pairs(args) do
      new[k] = v
    end

    new.handles[0] = new.stdin
    new.handles[1] = new.stdout
    new.handles[2] = new.stderr
    
    new.coroutine.status = function(self)
      if self.dead then
        return "dead"
      elseif self.stopped then
        return "stopped"
      elseif self.waiting then
        return "waiting"
      else
        return "running"
      end
    end
    
    return new
  end
end
--#include "base/process.lua"
-- scheduler

k.log(k.loglevels.info, "base/scheduler")

do
  local globalenv = {
    UID = 0,
    USER = "root",
    TERM = "cynosure"
  }

  local processes = {}
  local current

  local api = {}

  api.signals = {
    hangup = 1,
    interrupt = 2,
    kill = 9,
    stop = 17,
    kbdstop = 18,
    continue = 19
  }

  function api.spawn(args)
    checkArg(1, args.name, "string")
    checkArg(2, args.func, "function")
    
    local parent = processes[current or 0] or
      (api.info() and api.info().data.self) or {}
    
    local new = k.create_process {
      name = args.name,
      parent = parent.pid or 0,
      stdin = args.stdin or parent.stdin or (io and io.input()),
      stdout = args.stdout or parent.stdout or (io and io.output()),
      stderr = args.stderr or parent.stderr or (io and io.stderr),
      input = args.input or parent.stdin or (io and io.input()),
      output = args.output or parent.stdout or (io and io.output()),
      owner = args.owner or parent.owner or 0,
      env = args.env or {}
    }

    for k, v in pairs(parent.env or globalenv) do
      new.env[k] = new.env[k] or v
    end

    new:add_thread(args.func)
    processes[new.pid] = new
    
    assert(k.sysfs.register(k.sysfs.types.process, new, "/proc/"..math.floor(
        new.pid)))
    
    return new
  end

  function api.info(pid)
    checkArg(1, pid, "number", "nil")
    
    pid = pid or current
    
    local proc = processes[pid]
    if not proc then
      return nil, "no such process"
    end

    local info = {
      pid = proc.pid,
      name = proc.name,
      waiting = proc.waiting,
      stopped = proc.stopped,
      deadline = proc.deadline,
      n_threads = #proc.threads,
      status = proc:status(),
      cputime = proc.cputime,
      owner = proc.owner
    }
    
    if proc.pid == current then
      info.data = {
        io = proc.io,
        self = proc,
        handles = proc.handles,
        coroutine = proc.coroutine,
        env = proc.env
      }
    end
    
    return info
  end

  function api.kill(proc, signal)
    checkArg(1, proc, "number", "nil")
    checkArg(2, signal, "number")
    
    proc = proc or current.pid
    
    if not processes[proc] then
      return nil, "no such process"
    end
    
    processes[proc]:signal(signal)
    
    return true
  end

  -- XXX: this is specifically for kernel use ***only*** - userspace does NOT
  -- XXX: get this function.  it is incredibly dangerous and should be used with
  -- XXX: the utmost caution.
  api.processes = processes
  function api.get(pid)
    checkArg(1, pid, "number", current and "nil")
    pid = pid or current
    if not processes[pid] then
      return nil, "no such process"
    end
    return processes[pid]
  end

  local function handleDeath(proc, exit, err, ok)
    local exit = err or 0
    err = err or ok

    if type(err) == "string" then
      exit = 127
    else
      exit = err or 0
      err = "exited"
    end

    err = err or "died"
    if (k.cmdline.log_process_death and
        k.cmdline.log_process_death ~= 0) then
      -- if we can, put the process death info on the same stderr stream
      -- belonging to the process that died
      if proc.io.stderr and proc.io.stderr.write then
        local old_logio = k.logio
        k.logio = proc.io.stderr
        k.log(k.loglevels.info, "process died:", proc.pid, exit, err)
        k.logio = old_logio
      else
        k.log(k.loglevels.warn, "process died:", proc.pid, exit, err)
      end
    end

    computer.pushSignal("process_died", proc.pid, exit, err)

    for k, v in pairs(proc.handles) do
      pcall(v.close, v)
    end

    local ppt = "/proc/" .. math.floor(proc.pid)
    k.sysfs.unregister(ppt)
    
    processes[proc.pid] = nil
  end

  local pullSignal = computer.pullSignal
  function api.loop()
    while next(processes) do
      local to_run = {}
      local going_to_run = {}
      local min_timeout = math.huge
    
      for _, v in pairs(processes) do
        if not v.stopped then
          min_timeout = math.min(min_timeout, v.deadline - computer.uptime())
        end
      
        if min_timeout <= 0 then
          min_timeout = 0
          break
        end
      end
      
      --k.log(k.loglevels.info, min_timeout)
      
      local sig = table.pack(pullSignal(min_timeout))
      k.event.handle(sig)

      for _, v in pairs(processes) do
        if (v.deadline <= computer.uptime() or #v.queue > 0 or sig.n > 0) and
            not (v.stopped or going_to_run[v.pid] or v.dead) then
          to_run[#to_run + 1] = v
      
          if v.resume_next then
            to_run[#to_run + 1] = v.resume_next
            going_to_run[v.resume_next.pid] = true
          end
        elseif v.dead then
          handleDeath(v, v.exit_code or 1, v.status or "Killed")
        end
      end

      for i, proc in ipairs(to_run) do
        local psig = sig
        current = proc.pid
      
        if #proc.queue > 0 then
          -- the process has queued signals
          -- but we don't want to drop this signal
          proc:push_signal(table.unpack(sig))
          
          psig = proc:pull_signal() -- pop a signal
        end
        
        local start_time = computer.uptime()
        local aok, ok, err = proc:resume(table.unpack(psig))

        if proc.dead or ok == "__internal_process_exit" or not aok then
          handleDeath(proc, exit, err, ok)
        else
          proc.cputime = proc.cputime + computer.uptime() - start_time
          proc.deadline = computer.uptime() + (tonumber(ok) or tonumber(err)
            or math.huge)
        end
      end
    end

    if not k.is_shutting_down then
      -- !! PANIC !!
      k.panic("all user processes died")
    end
  end

  k.scheduler = api

  k.hooks.add("shutdown", function()
    if not k.is_shutting_down then
      return
    end

    k.log(k.loglevels.info, "shutdown: sending shutdown signal")

    for pid, proc in pairs(processes) do
      proc:resume("shutdown")
    end

    k.log(k.loglevels.info, "shutdown: waiting 1s for processes to exit")
    os.sleep(1)

    k.log(k.loglevels.info, "shutdown: killing all processes")

    for pid, proc in pairs(processes) do
      if pid ~= current then -- hack to make sure shutdown carries on
        proc.dead = true
      end
    end

    coroutine.yield(0) -- clean up
  end)
  
  -- sandbox hook for userspace 'process' api
  k.hooks.add("sandbox", function()
    local p = {}
    k.userspace.package.loaded.process = p
    
    function p.spawn(args)
      checkArg(1, args.name, "string")
      checkArg(2, args.func, "function")
    
      local sanitized = {
        func = args.func,
        name = args.name,
        stdin = args.stdin,
        stdout = args.stdout,
        input = args.input,
        output = args.output,
        stderr = args.stderr,
      }
      
      local new = api.spawn(sanitized)
      
      return new.pid
    end
    
    function p.kill(pid, signal)
      checkArg(1, pid, "number", "nil")
      checkArg(2, signal, "number")
      
      local cur = processes[current]
      local atmp = processes[pid]
      
      if not atmp then
        return true
      end
      
      if (atmp or {owner=processes[current].owner}).owner ~= cur.owner and
         cur.owner ~= 0 then
        return nil, "permission denied"
      end
      
      return api.kill(pid, signal)
    end
    
    function p.list()
      local pr = {}
      
      for k, v in pairs(processes) do
        pr[#pr+1]=k
      end
      
      table.sort(pr)
      return pr
    end

    -- this is not provided at the kernel level
    -- largely because there is no real use for it
    -- returns: exit status, exit message
    function p.await(pid)
      checkArg(1, pid, "number")
      
      local signal = {}
      
      if not processes[pid] then
        return nil, "no such process"
      end
      
      repeat
        -- busywait until the process dies
        signal = table.pack(coroutine.yield())
      until signal[1] == "process_died" and signal[2] == pid
      
      return signal[3], signal[4]
    end
    
    p.info = api.info

    p.signals = k.util.copy_table(api.signals)
  end)
end
--#include "base/scheduler.lua"
-- sysfs API --

k.log(k.loglevels.info, "sysfs/sysfs")

do
  local cmdline = table.concat(k.__original_cmdline, " ") .. "\n"
  local tree = {
    dir = true,
    components = {
      dir = true,
      ["by-address"] = {dir = true},
      ["by-type"] = {dir = true}
    },
    proc = {dir = true},
    dev = {
      dir = true,
      stdin = {
        dir = false,
        open = function()
          return io.stdin
        end
      },
      stdout = {
        dir = false,
        open = function()
          return io.stdout
        end
      },
      stderr = {
        dir = false,
        open = function()
          return io.stderr
        end
      },
    },
    mounts = {
      dir = false,
      read = function(h)
        if h.__read then
          return nil
        end

        local mounts = k.fs.api.mounts()
        local ret = ""
        
        for k, v in pairs(mounts) do
          ret = string.format("%s%s\n", ret, k..": "..v)
        end
        
        h.__read = true
        
        return ret
      end,
      write = function()
        return nil, "bad file descriptor"
      end
    },
    cmdline = {
      dir = false,
      read = function(self, n)
        self.__ptr = self.__ptr or 0
        if self.__ptr >= #cmdline then
          return nil
        else
          self.__ptr = self.__ptr + n
          return cmdline:sub(self.__ptr - n, self.__ptr)
        end
      end
    }
  }

  local function find(f)
    if f == "/" or f == "" then
      return tree
    end

    local s = k.fs.split(f)
    local c = tree
    
    for i=1, #s, 1 do
      if s[i] == "dir" then
        return nil, k.fs.errors.file_not_found
      end
    
      if not c[s[i]] then
        return nil, k.fs.errors.file_not_found
      end

      c = c[s[i]]
    end

    return c
  end

  local obj = {}

  function obj:stat(f)
    checkArg(1, f, "string")
    
    local n, e = find(f)
    
    if n then
      return {
        permissions = 365,
        owner = 0,
        group = 0,
        lastModified = 0,
        size = 0,
        isDirectory = not not n.dir,
        type = n.dir and k.fs.types.directory or k.fs.types.special
      }
    else
      return nil, e
    end
  end

  function obj:touch()
    return nil, k.fs.errors.read_only
  end

  function obj:remove()
    return nil, k.fs.errors.read_only
  end

  function obj:list(d)
    local n, e = find(d)
    
    if not n then return nil, e end
    if not n.dir then return nil, k.fs.errors.not_a_directory end
    
    local f = {}
    
    for k, v in pairs(n) do
      if k ~= "dir" then
        f[#f+1] = tostring(k)
      end
    end
    
    return f
  end

  local function ferr()
    return nil, "bad file descriptor"
  end

  local function fclose(self)
    if self.closed then
      return ferr()
    end
    
    self.closed = true
  end

  function obj:open(f, m)
    checkArg(1, f, "string")
    checkArg(2, m, "string")
    
    local n, e = find(f)
    
    if not n then return nil, e end
    if n.dir then return nil, k.fs.errors.is_a_directory end

    if n.open then return n.open(m) end
    
    return {
      read = n.read or ferr,
      write = n.write or ferr,
      seek = n.seek or ferr,
      flush = n.flush,
      close = n.close or fclose
    }
  end

  obj.node = {getLabel = function() return "sysfs" end}

  -- now here's the API
  local api = {}
  api.types = {
    generic = "generic",
    process = "process",
    directory = "directory"
  }
  typedef("string", "SYSFS_NODE")

  local handlers = {}

  function api.register(otype, node, path)
    checkArg(1, otype, "SYSFS_NODE")
    assert(type(node) ~= "nil", "bad argument #2 (value expected, got nil)")
    checkArg(3, path, "string")

    if not handlers[otype] then
      return nil, string.format("sysfs: node type '%s' not handled", otype)
    end

    local segments = k.fs.split(path)
    local nname = segments[#segments]
    local n, e = find(table.concat(segments, "/", 1, #segments - 1))

    if not n then
      return nil, e
    end

    local nn, ee = handlers[otype](node)
    if not nn then
      return nil, ee
    end

    n[nname] = nn

    return true
  end

  function api.retrieve(path)
    checkArg(1, path, "string")
    return find(path)
  end

  function api.unregister(path)
    checkArg(1, path, "string")
    
    local segments = k.fs.split(path)
    local ppath = table.concat(segments, "/", 1, #segments - 1)
    
    local node = segments[#segments]
    if node == "dir" then
      return nil, k.fs.errors.file_not_found
    end

    local n, e = find(ppath)
    if not n then
      return nil, e
    end

    if not n[node] then
      return nil, fs.errors.file_not_found
    end

    n[node] = nil

    return true
  end
  
  function api.handle(otype, mkobj)
    checkArg(1, otype, "SYSFS_NODE")
    checkArg(2, mkobj, "function")

    api.types[otype] = otype
    handlers[otype] = mkobj

    return true
  end
  
  k.sysfs = api

  -- we have to hook this here since the root filesystem isn't mounted yet
  -- when the kernel reaches this point.
  k.hooks.add("sandbox", function()
    assert(k.fs.api.mount(obj, k.fs.api.types.NODE, "sys"))
    -- Adding the sysfs API to userspace is probably not necessary for most
    -- things.  If it does end up being necessary I'll do it.
    --k.userspace.package.loaded.sysfs = k.util.copy_table(api)
  end)
end

-- sysfs handlers

k.log(k.loglevels.info, "sysfs/handlers")

do
  local util = {}
  function util.mkfile(data)
    local data = data
    return {
      dir = false,
      read = function(self, n)
        self.__ptr = self.__ptr or 0
        if self.__ptr >= #data then
          return nil
        else
          self.__ptr = self.__ptr + n
          return data:sub(self.__ptr - n, self.__ptr)
        end
      end
    }
  end

  function util.fmkfile(tab, k, w)
    return {
      dir = false,
      read = function(self)
        if self.__read then
          return nil
        end

        self.__read = true
        return tostring(tab[k])
      end,
      write = w and function(self, d)
        tab[k] = tonumber(d) or d
      end or nil
    }
  end

  function util.fnmkfile(r, w)
    return {
      dir = false,
      read = function(s)
        if s.__read then
          return nil
        end

        s.__read = true
        return r()
      end,
      write = w
    }
  end

-- sysfs: Generic component handler

k.log(k.loglevels.info, "sysfs/handlers/generic")

do
  local function mknew(addr)
    return {
      dir = true,
      address = util.mkfile(addr),
      type = util.mkfile(component.type(addr)),
      slot = util.mkfile(tostring(component.slot(addr)))
    }
  end

  k.sysfs.handle("generic", mknew)
end
--#include "sysfs/handlers/generic.lua"
-- sysfs: Directory generator

k.log(k.loglevels.info, "sysfs/handlers/directory")

do
  local function mknew()
    return { dir = true }
  end

  k.sysfs.handle("directory", mknew)
end
--#include "sysfs/handlers/directory.lua"
-- sysfs: Process handler

k.log(k.loglevels.info, "sysfs/handlers/process")

do
  local function mknew(proc)
    checkArg(1, proc, "process")
    
    local base = {
      dir = true,
      handles = {
        dir = true,
      },
      cputime = util.fmkfile(proc, "cputime"),
      name = util.mkfile(proc.name),
      threads = util.fmkfile(proc, "threads"),
      owner = util.mkfile(tostring(proc.owner)),
      deadline = util.fmkfile(proc, "deadline"),
      stopped = util.fmkfile(proc, "stopped"),
      waiting = util.fmkfile(proc, "waiting"),
      status = util.fnmkfile(function() return proc.coroutine.status(proc) end)
    }

    local mt = {
      __index = function(t, k)
        k = tonumber(k) or k
        if not proc.handles[k] then
          return nil, k.fs.errors.file_not_found
        else
          return {dir = false, open = function(m)
            -- you are not allowed to access other
            -- people's files!
            return nil, "permission denied"
          end}
        end
      end,
      __pairs = function()
        return pairs(proc.handles)
      end
    }
    mt.__ipairs = mt.__pairs

    setmetatable(base.handles, mt)

    return base
  end

  k.sysfs.handle("process", mknew)
end
--#include "sysfs/handlers/process.lua"
-- sysfs: TTY device handling

k.log(k.loglevels.info, "sysfs/handlers/tty")

do
  local function mknew(tty)
    return {
      dir = false,
      read = function(_, n)
        return tty:read(n)
      end,
      write = function(_, d)
        return tty:write(d)
      end,
      flush = function() return tty:flush() end
    }
  end

  k.sysfs.handle("tty", mknew)

  k.sysfs.register("tty", k.logio, "/dev/console")
  k.sysfs.register("tty", k.logio, "/dev/tty0")
end
--#include "sysfs/handlers/tty.lua"

-- component-specific handlers
-- sysfs: GPU hander

k.log(k.loglevels.info, "sysfs/handlers/gpu")

do
  local function mknew(addr)
    local proxy = component.proxy(addr)
    local new = {
      dir = true,
      address = util.mkfile(addr),
      slot = util.mkfile(proxy.slot),
      type = util.mkfile(proxy.type),
      resolution = util.fnmkfile(
        function()
          return string.format("%d %d", proxy.getResolution())
        end,
        function(_, s)
          local w, h = s:match("(%d+) (%d+)")
        
          w = tonumber(w)
          h = tonumber(h)
        
          if not (w and h) then
            return nil
          end

          proxy.setResolution(w, h)
        end
      ),
      foreground = util.fnmkfile(
        function()
          return tostring(proxy.getForeground())
        end,
        function(_, s)
          s = tonumber(s)
          if not s then
            return nil
          end

          proxy.setForeground(s)
        end
      ),
      background = util.fnmkfile(
        function()
          return tostring(proxy.getBackground())
        end,
        function(_, s)
          s = tonumber(s)
          if not s then
            return nil
          end

          proxy.setBackground(s)
        end
      ),
      maxResolution = util.fnmkfile(
        function()
          return string.format("%d %d", proxy.maxResolution())
        end
      ),
      maxDepth = util.fnmkfile(
        function()
          return tostring(proxy.maxDepth())
        end
      ),
      depth = util.fnmkfile(
        function()
          return tostring(proxy.getDepth())
        end,
        function(_, s)
          s = tonumber(s)
          if not s then
            return nil
          end

          proxy.setDepth(s)
        end
      ),
      screen = util.fnmkfile(
        function()
          return tostring(proxy.getScreen())
        end,
        function(_, s)
          if not component.type(s) == "screen" then
            return nil
          end

          proxy.bind(s)
        end
      )
    }

    return new
  end

  k.sysfs.handle("gpu", mknew)
end
--#include "sysfs/handlers/gpu.lua"
-- sysfs: filesystem handler

k.log(k.loglevels.info, "sysfs/handlers/filesystem")

do
  local function mknew(addr)
    local proxy = component.proxy(addr)
    
    local new = {
      dir = true,
      address = util.mkfile(addr),
      slot = util.mkfile(proxy.slot),
      type = util.mkfile(proxy.type),
      label = util.fnmkfile(
        function()
          return proxy.getLabel() or "unlabeled"
        end,
        function(_, s)
          proxy.setLabel(s)
        end
      ),
      spaceUsed = util.fnmkfile(
        function()
          return string.format("%d", proxy.spaceUsed())
        end
      ),
      spaceTotal = util.fnmkfile(
        function()
          return string.format("%d", proxy.spaceTotal())
        end
      ),
      isReadOnly = util.fnmkfile(
        function()
          return tostring(proxy.isReadOnly())
        end
      ),
      mounts = util.fnmkfile(
        function()
          local mounts = k.fs.api.mounts()
          local ret = ""
          for k,v in pairs(mounts) do
            if v == addr then
              ret = ret .. k .. "\n"
            end
          end
          return ret
        end
      )
    }

    return new
  end

  k.sysfs.handle("filesystem", mknew)
end
--#include "sysfs/handlers/filesystem.lua"

-- component event handler
-- sysfs: component event handlers

k.log(k.loglevels.info, "sysfs/handlers/component")

do
  local n = {}
  local gpus, screens = {}, {}
  gpus[k.logio.gpu.address] = true
  screens[k.logio.gpu.getScreen()] = true

  local function update_ttys(a, c)
    if c == "gpu" then
      gpus[a] = gpus[a] or false
    elseif c == "screen" then
      screens[a] = screens[a] or false
    else
      return
    end

    for gk, gv in pairs(gpus) do
      if not gpus[gk] then
        for sk, sv in pairs(screens) do
          if not screens[sk] then
            k.log(k.loglevels.info, string.format(
              "Creating TTY on [%s:%s]", gk:sub(1, 8), (sk:sub(1, 8))))
            k.create_tty(gk, sk)
            gpus[gk] = true
            screens[sk] = true
            gv, sv = true, true
          end
        end
      end
    end
  end

  local function added(_, addr, ctype)
    n[ctype] = n[ctype] or 0

    k.log(k.loglevels.info, "Detected component:", addr .. ", type", ctype)
    
    local path = "/components/by-address/" .. addr:sub(1, 6)
    local path_ = "/components/by-type/" .. ctype
    local path2 = "/components/by-type/" .. ctype .. "/" .. n[ctype]
    
    n[ctype] = n[ctype] + 1

    if not k.sysfs.retrieve(path_) then
      k.sysfs.register("directory", true, path_)
    end

    local s = k.sysfs.register(ctype, addr, path)
    if not s then
      s = k.sysfs.register("generic", addr, path)
      k.sysfs.register("generic", addr, path2)
    else
      k.sysfs.register(ctype, addr, path2)
    end

    if ctype == "gpu" or ctype == "screen" then
      update_ttys(addr, ctype)
    end
    
    return s
  end

  local function removed(_, addr, ctype)
    local path = "/sys/components/by-address/" .. addr
    local path2 = "/sys/components/by-type/" .. addr
    k.sysfs.unregister(path2)
    return k.sysfs.unregister(path)
  end

  k.event.register("component_added", added)
  k.event.register("component_removed", removed)
end
--#include "sysfs/handlers/component.lua"

end -- sysfs handlers: Done
--#include "sysfs/handlers.lua"
--#include "sysfs/sysfs.lua"
-- base networking --

k.log(k.loglevels.info, "extra/net/base")

do
  local protocols = {}
  k.net = {}

  local ppat = "^(.-)://(.+)"

  function k.net.socket(url, ...)
    checkArg(1, url, "string")
    local proto, rest = url:match(ppat)
    if not proto then
      return nil, "protocol unspecified"
    elseif not protocols[proto] then
      return nil, "bad protocol: " .. proto
    end

    return protocols[proto].socket(proto, rest, ...)
  end

  function k.net.request(url, ...)
    checkArg(1, url, "string")
    local proto, rest = url:match(ppat)
    if not proto then
      return nil, "protocol unspecified"
    elseif not protocols[proto] then
      return nil, "bad protocol: " .. proto
    end

    return protocols[proto].request(proto, rest, ...)
  end

  local hostname = "localhost"

  function k.net.hostname()
    return hostname
  end

  function k.net.sethostname(hn)
    checkArg(1, hn, "string")
    local perms = k.security.users.attributes(k.scheduler.info().owner).acls
    if not k.security.acl.has_permission(perms,
        k.security.acl.permissions.user.HOSTNAME) then
      return nil, "insufficient permission"
    end
    hostname = hn
    return true
  end

  k.hooks.add("sandbox", function()
    k.userspace.package.loaded.network = k.util.copy_table(k.net)
  end)

-- internet component for the 'net' api --

k.log(k.loglevels.info, "extra/net/internet")

do
  local proto = {}

  local iaddr, ipx
  local function get_internet()
    if not (iaddr and component.methods(iaddr)) then
      iaddr = component.list("internet")()
    end
    if iaddr and ((ipx and ipx.address ~= iaddr) or not ipx) then
      ipx = component.proxy(iaddr)
    end
    return ipx
  end

  local _base_stream = {}

  function _base_stream:read(n)
    checkArg(1, n, "number")
    if not self.base then
      return nil, "_base_stream is closed"
    end
    local data = ""
    repeat
      local chunk = self.base.read(n - #data)
      data = data .. (chunk or "")
    until (not chunk) or #data == n
    if #data == 0 then return nil end
    return data
  end

  function _base_stream:write(data)
    checkArg(1, data, "string")
    if not self.base then
      return nil, "_base_stream is closed"
    end
    while #data > 0 do
      local written, err = self.base.write(data)
      if not written then
        return nil, err
      end
      data = data:sub(written + 1)
    end
    return true
  end

  function _base_stream:close()
    if self._base_stream then
      self._base_stream.close()
      self._base_stream = nil
    end
    return true
  end

  function proto:socket(url, port)
    local inetcard = get_internet()
    if not inetcard then
      return nil, "no internet card installed"
    end
    local base, err = inetcard._base_stream(self .. "://" .. url, port)
    if not base then
      return nil, err
    end
    return setmetatable({base = base}, {__index = _base_stream})
  end

  function proto:request(url, data, headers, method)
    checkArg(1, url, "string")
    checkArg(2, data, "string", "table", "nil")
    checkArg(3, headers, "table", "nil")
    checkArg(4, method, "string", "nil")

    local inetcard = get_internet()
    if not inetcard then
      return nil, "no internet card installed"
    end

    local post
    if type(data) == "string" then
      post = data
    elseif type(data) == "table" then
      for k,v in pairs(data) do
        post = (post and (post .. "&") or "")
          .. tostring(k) .. "=" .. tostring(v)
      end
    end

    local base, err = inetcard.request(self .. "://" .. url, post, headers, method)
    if not base then
      return nil, err
    end

    local ok, err
    repeat
      ok, err = base.finishConnect()
    until ok or err
    if not ok then return nil, err end

    return setmetatable({base = base}, {__index = _base_stream})
  end

  protocols.https = proto
  protocols.http = proto
end
  --#include "extra/net/internet.lua"
end
--#include "extra/net/base.lua"
-- getgpu - get the gpu associated with a tty --

k.log(k.loglevels.info, "extra/ustty")

do
  k.gpus = {}
  local deletable = {}

  k.gpus[0] = k.logio.gpu

  k.hooks.add("sandbox", function()
    k.userspace.package.loaded.tty = {
      -- get the GPU associated with a TTY
      getgpu = function(id)
        checkArg(1, id, "number")

        if not k.gpus[id] then
          return nil, "terminal not registered"
        end

        return k.gpus[id]
      end,

      -- create a TTY on top of a GPU and optional screen
      create = function(gpu, screen)
        if type(gpu) == "table" then screen = screen or gpu.getScreen() end
        local raw = k.create_tty(gpu, screen)
        deletable[raw.ttyn] = raw
        local prox = io.open(string.format("/sys/dev/tty%d", raw.ttyn), "rw")
        prox.tty = raw.ttyn
        prox.buffer_mode = "none"
        return prox
      end,

      -- cleanly delete a user-created TTY
      delete = function(id)
        checkArg(1, id, "number")
        if not deletable[id] then
          return nil, "tty " .. id
            .. " is not user-created and cannot be deregistered"
        end
        deletable[id]:close()
        return true
      end
    }
  end)
end
--#include "extra/ustty.lua"
-- sound api v2:  emulate the sound card for everything --

k.log(k.loglevels.info, "extra/sound")

do
  local api = {}
  local tiers = {
    internal = 0,
    beep = 1,
    noise = 2,
    sound = 3,
    [0] = "internal",
    "beep",
    "noise",
    "sound"
  }

  local available = {
    internal = 1,
    beep = 0,
    noise = 0,
    sound = 0,
  }

  local proxies = {
    internal = {
      [computer.address()] = {
        beep = function(tab)
          return computer.beep(tab[1][1], tab[1][2])
        end
      }
    },
    beep = {},
    noise = {},
    sound = {}
  }
  
  local current = "internal"
  local caddr = computer.address()

  local function component_changed(sig, addr, ctype)
    if sig == "component_added" then
      if tiers[ctype] and tiers[ctype] > tiers[current] then
        current = ctype
        available[ctype] = math.max(1, available[ctype] + 1)
        proxies[ctype][addr] = component.proxy(addr)
      end
    else
      if tiers[ctype] then
        available[ctype] = math.min(0, available[ctype] - 1)
        proxies[ctype][addr] = nil
        if caddr == addr then
          for i=#tiers, 0, -1 do
            if available[tiers[i]] > 0 then
              current = tiers[i]
              caddr = next(proxies[current])
            end
          end
        end
      end
    end
  end

  k.event.register("component_added", component_changed)
  k.event.register("component_removed", component_changed)

  local handlers = {
    internal = {play = select(2, next(proxies.internal)).beep},
    --#include "extra/sound/beep.lua"
    --#include "extra/sound/noise.lua"
    --#include "extra/sound/sound.lua"
  }

  function api.play(notes)
    return handlers[current].play(notes)
  end
end
--#include "extra/sound.lua"
--#include "includes.lua"
-- load /etc/passwd, if it exists

k.log(k.loglevels.info, "base/passwd_init")

k.hooks.add("rootfs_mounted", function()
  local p1 = "(%d+):([^:]+):([0-9a-fA-F]+):(%d+):([^:]+):([^:]+)"
  local p2 = "(%d+):([^:]+):([0-9a-fA-F]+):(%d+):([^:]+)"
  local p3 = "(%d+):([^:]+):([0-9a-fA-F]+):(%d+)"

  k.log(k.loglevels.info, "Reading /etc/passwd")

  local handle, err = io.open("/etc/passwd", "r")
  if not handle then
    k.log(k.loglevels.info, "Failed opening /etc/passwd:", err)
  else
    local data = {}
    
    for line in handle:lines("l") do
      -- user ID, user name, password hash, ACLs, home directory,
      -- preferred shell
      local uid, uname, pass, acls, home, shell
      uid, uname, pass, acls, home, shell = line:match(p1)
      if not uid then
        uid, uname, pass, acls, home = line:match(p2)
      end
      if not uid then
        uid, uname, pass, acls = line:match(p3)
      end
      uid = tonumber(uid)
      if not uid then
        k.log(k.loglevels.info, "Invalid line:", line, "- skipping")
      else
        data[uid] = {
          name = uname,
          pass = pass,
          acls = tonumber(acls),
          home = home,
          shell = shell
        }
      end
    end
  
    handle:close()
  
    k.log(k.loglevels.info, "Registering user data")
  
    k.security.users.prime(data)

    k.log(k.loglevels.info,
      "Successfully registered user data from /etc/passwd")
  end

  k.hooks.add("shutdown", function()
    k.log(k.loglevels.info, "Saving user data to /etc/passwd")
    local handle, err = io.open("/etc/passwd", "w")
    if not handle then
      k.log(k.loglevels.warn, "failed saving /etc/passwd:", err)
      return
    end
    for k, v in pairs(k.passwd) do
      local data = string.format("%d:%s:%s:%d:%s:%s\n",
        k, v.name, v.pass, v.acls, v.home or ("/home/"..v.name),
        v.shell or "/bin/lsh")
      handle:write(data)
    end
    handle:close()
  end)
end)
--#include "base/passwd_init.lua"
-- load init, i guess

k.log(k.loglevels.info, "base/load_init")

-- we need to mount the root filesystem first
do
  if _G.__mtar_fs_tree then
    k.log(k.loglevels.info, "using MTAR filesystem tree as rootfs")
    k.fs.api.mount(__mtar_fs_tree, k.fs.api.types.NODE, "/")
  else
    local root, reftype = nil, "UUID"
    
    if k.cmdline.root then
      local rtype, ref = k.cmdline.root:match("^(.-)=(.+)$")
      reftype = rtype:upper() or "UUID"
      root = ref or k.cmdline.root
    elseif not computer.getBootAddress then
      -- still error, but slightly less hard
      k.panic("Cannot determine root filesystem!")
    else
      k.log(k.loglevels.warn,
        "\27[101;97mWARNING\27[39;49m use of computer.getBootAddress to detect the root filesystem is discouraged.")
      k.log(k.loglevels.warn,
        "\27[101;97mWARNING\27[39;49m specify root=UUID=<address> on the kernel command line to suppress this message.")
      root = computer.getBootAddress()
      reftype = "UUID"
    end
  
    local ok, err
    
    if reftype ~= "LABEL" then
      if reftype ~= "UUID" then
        k.log(k.loglevels.warn, "invalid rootspec type (expected LABEL or UUID, got ", reftype, ") - assuming UUID")
      end
    
      if not component.list("filesystem")[root] then
        for k, v in component.list("drive", true) do
          local ptable = k.fs.get_partition_table_driver(k)
      
          if ptable then
            for i=1, #ptable:list(), 1 do
              local part = ptable:partition(i)
          
              if part and (part.address == root) then
                root = part
                break
              end
            end
          end
        end
      end
  
      ok, err = k.fs.api.mount(root, k.fs.api.types.RAW, "/")
    elseif reftype == "LABEL" then
      local comp
      
      for k, v in component.list() do
        if v == "filesystem" then
          if component.invoke(k, "getLabel") == root then
            comp = root
            break
          end
        elseif v == "drive" then
          local ptable = k.fs.get_partition_table_driver(k)
      
          if ptable then
            for i=1, #ptable:list(), 1 do
              local part = ptable:partition(i)
          
              if part then
                if part.getLabel() == root then
                  comp = part
                  break
                end
              end
            end
          end
        end
      end
  
      if not comp then
        k.panic("Could not determine root filesystem from root=", k.cmdline.root)
      end
      
      ok, err = k.fs.api.mount(comp, k.fs.api.types.RAW, "/")
    end
  
    if not ok then
      k.panic(err)
    end
  end

  k.log(k.loglevels.info, "Mounted root filesystem")
  
  k.hooks.call("rootfs_mounted")

  -- mount the tmpfs
  k.fs.api.mount(component.proxy(computer.tmpAddress()), k.fs.api.types.RAW, "/tmp")
end

-- register components with the sysfs, if possible
do
  for k, v in component.list("carddock") do
    component.invoke(k, "bindComponent")
  end

  k.log(k.loglevels.info, "Registering components")
  for kk, v in component.list() do
    computer.pushSignal("component_added", kk, v)
   
    repeat
      local x = table.pack(computer.pullSignal())
      k.event.handle(x)
    until x[1] == "component_added"
  end
end

do
  k.log(k.loglevels.info, "Creating userspace sandbox")
  
  local sbox = k.util.copy_table(_G)
  
  k.userspace = sbox
  sbox._G = sbox
  
  k.hooks.call("sandbox", sbox)

  k.log(k.loglevels.info, "Loading init from",
                               k.cmdline.init or "/sbin/init.lua")
  
  local ok, err = loadfile(k.cmdline.init or "/sbin/init.lua")
  
  if not ok then
    k.panic(err)
  end
  
  local ios = k.create_fstream(k.logio, "rw")
  ios.buffer_mode = "none"
  ios.tty = 0
  
  k.scheduler.spawn {
    name = "init",
    func = ok,
    input = ios,
    output = ios,
    stdin = ios,
    stdout = ios,
    stderr = ios
  }

  k.log(k.loglevels.info, "Starting scheduler loop")
  k.scheduler.loop()
end
--#include "base/load_init.lua"
k.panic("Premature exit!")
