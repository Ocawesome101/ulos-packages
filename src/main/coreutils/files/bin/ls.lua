-- coreutils: ls --

local text = require("text")
local size = require("size")
local path = require("path")
local users = require("users")
local termio = require("termio")
local filetypes = require("filetypes")
local fs = require("filesystem")

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([=[
usage: ls [options] [file1 [file2 ...]]
Lists information about file(s).  Defaults to the
current directory.  Sorts entries alphabetically.
  -1            one file per line
  -a            show hidden files
  --color=WHEN  If "no", disable coloration;  if
                "always", force coloration even
                if the standard output is not
                connected to a terminal;
                otherwise, decide automatically.
  -d            Display information about a
                directory as though it were a
                file.
  -h            Use human-readable file sizes.
  --help        Display this help message and
                exit.
  -l            Display full file information
                (permissions, last modification
                date, etc.) instead of just file
                names.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]=])
  os.exit(1)
end

local colors = {
  default = "39;49",
  dir = "49;94",
  exec = "49;92",
  link = "49;96",
  special = "49;93"
}

local dfa = {name = "n/a"}
local function infoify(base, files, hook, hka)
  local infos = {}
  local maxn_user = 0
  local maxn_size = 0
  
  for i=1, #files, 1 do
    local fpath = files[i]
    
    if base ~= files[i] then
      fpath = path.canonical(path.concat(base, files[i]))
    end
    
    local info, err = fs.stat(fpath)
    if not info then
      io.stderr:write("ls: failed getting information for ", fpath, ": ",
        err, "\n")
      return nil
    end
    
    local perms = string.format(
      "%s%s%s%s%s%s%s%s%s%s",
      info.type == filetypes.directory and "d" or
        info.type == filetypes.special and "c" or
        "-",
      info.permissions & 0x1 and "r" or "-",
      info.permissions & 0x2 and "w" or "-",
      info.permissions & 0x4 and "x" or "-",
      info.permissions & 0x8 and "r" or "-",
      info.permissions & 0x10 and "w" or "-",
      info.permissions & 0x20 and "x" or "-",
      info.permissions & 0x40 and "r" or "-",
      info.permissions & 0x80 and "w" or "-",
      info.permissions & 0x100 and "x" or "-")
    
    local user = (users.attributes(info.owner) or dfa).name
    maxn_user = math.max(maxn_user, #user)
    infos[i] = {
      perms = perms,
      user = user,
      size = size.format(math.floor(info.size), not opts.h),
      modified = os.date("%b %d %H:%M", info.lastModified),
    }
  
    maxn_size = math.max(maxn_size, #infos[i].size)
    if hook then files[i] = hook(files[i], hka) end
  end

  for i=1, #files, 1 do
    files[i] = string.format(
      "%s %s %s %s %s",
      infos[i].perms,
      text.padRight(maxn_user, infos[i].user),
      text.padRight(maxn_size, infos[i].size),
      infos[i].modified,
      files[i])
  end
end

local function colorize(f, p)
  if opts.color == "no" or ((not io.output().tty) and opts.color ~= "always") then
    return f
  end
  if type(f) == "table" then
    for i=1, #f, 1 do
      f[i] = colorize(f[i], p)
    end
  else
    local full = f
    if p ~= f then full = path.concat(p, f) end
    
    local info, err = fs.stat(full)
    
    if not info then
      io.stderr:write("ls: failed getting color information for ", f, ": ", err, "\n")
      return nil
    end
    
    local color = colors.default
  
    if info.type == filetypes.directory then
      color = colors.dir
    elseif info.type == filetypes.link then
      color = colors.link
    elseif info.type == filetypes.special then
      color = colors.special
    elseif info.permissions & 4 ~= 0 then
      color = colors.exec
    end
    return string.format("\27[%sm%s\27[39;49m", color, f)
  end
end

local function list(dir)
  local odir = dir
  dir = path.canonical(dir)
  
  local files, err
  local info, serr = fs.stat(dir)
  
  if not info then
    err = serr
  elseif opts.d or not info.isDirectory then
    files = {dir}
  else
    files, err = fs.list(dir)
  end
  
  if not files then
    return nil, string.format("cannot access '%s': %s", odir, err)
  end
  
  local rm = {}
  for i=1, #files, 1 do
    files[i] = files[i]:gsub("[/]+$", "")
    if files[i]:sub(1,1) == "." and not opts.a then
      rm[#rm + 1] = i
    end
  end

  for i=#rm, 1, -1 do
    table.remove(files, rm[i])
  end

  table.sort(files)
  
  if opts.l then
    infoify(dir, files, colorize, dir)
  
    for i=1, #files, 1 do
      print(files[i])
    end
  elseif opts["1"] then
    for i=1, #files, 1 do
      print(colorize(files[i], dir))
    end
  elseif not (io.stdin.tty and io.stdout.tty) then
    for i=1, #files, 1 do
      print(files[i])
    end
  else
    print(text.mkcolumns(files, { hook = function(f)
        return colorize(f, dir)
      end,
      maxWidth = termio.getTermSize() }))
  end

  return true
end

if #args == 0 then
  args[1] = os.getenv("PWD")
end

local ex = 0
for i=1, #args, 1 do
  if #args > 1 then
    if i > 1 then
      io.write("\n")
    end
    print(args[i] .. ":")
  end
  
  local ok, err = list(args[i])
  if not ok and err then
    io.stderr:write("ls: ", err, "\n")
    ex = 1
  end
end

os.exit(ex)
