-- argutil: common argument parsing library

local lib = {}

function lib.parse(...)
  local top = table.pack(...)
  local do_done = true
  
  if type(top[1]) == "boolean" then
    do_done = top[1]
    table.remove(top, 1)
  end

  local args, opts = {}, {}
  local done = false
  
  for i=1, #top, 1 do
    local arg = top[i]
    
    if done or arg:sub(1,1) ~= "-" then
      args[#args+1] = arg
    else
      if arg == "--" and do_done then
        done = true
      elseif arg:sub(1,2) == "--" and #arg > 2 then
        local opt, oarg = arg:match("^%-%-(.-)=(.+)")
  
        opt, oarg = opt or arg:sub(3), oarg or true
        opts[opt] = oarg
      elseif arg:sub(1,2) ~= "--" then
        for c in arg:sub(2):gmatch(".") do
          opts[c] = true
        end
      end
    end
  end

  return args, opts
end

function lib.getopt(_opts, ...)
  checkArg(1, _opts, "table")
  local _args = table.pack(...)
  local args, opts = {}, {}
  local skip_next, done = false, false
  for i, arg in ipairs(_args) do
    if skip_next then skip_next = false
    elseif arg:sub(1,1) == "-" and not done then
      if arg == "--" and opts.allow_finish then
        done = true
      elseif arg:match("%-%-(.+)") then
        arg = arg:sub(3)
        if _opts.options[arg] ~= nil then
          if _opts.options[arg] then
            if (not _args[i+1]) then
              io.stderr:write("option '", arg, "' requires an argument\n")
              os.exit(1)
            end
            opts[arg] = _args[i+1]
            skip_next = true
          else
            opts[arg] = true
          end
        elseif _opts.exit_on_bad_opt then
          io.stderr:write("unrecognized option '", arg, "'\n")
          os.exit(1)
        end
      else
        arg = arg:sub(2)
        if _opts.options[arg:sub(1,1)] then
          local a = arg:sub(1,1)
          if #arg == 1 then
            if not _args[i+1] then
              io.stderr:write("option '", arg, "' requires an argument\n")
              os.exit(1)
            end
            opts[a] = _args[i+1]
            skip_next = true
          else
            opts[a] = arg:sub(2)
          end
        else
          for c in arg:gmatch(".") do
            if _opts.options[c] == nil then
              if _opts.exit_on_bad_opt then
                io.stderr:write("unreciognized option '", arg, "'\n")
                os.exit(1)
              end
            elseif _opts.options[c] then
              if not _args[i+1] then
                io.stderr:write("option '", arg, "' requires an argument\n")
                os.exit(1)
              end
              opts[c] = true
            else
              opts[c] = true
            end
          end
        end
      end
    else
      if _opts.finish_after_arg then
        done = true
      end
      args[#args+1] = arg
    end
  end
  return args, opts
end

return lib
