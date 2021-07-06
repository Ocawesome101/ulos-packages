-- UPM: the ULOS Package Manager --

local fs = require("filesystem")
local path = require("path")
local tree = require("futil").tree
local mtar = require("mtar")
local config = require("config")
local network = require("network")
local filetypes = require("filetypes")

local args, opts = require("argutil").parse(...)

local cfg = config.bracket:load("/etc/upm.cfg") or {}

cfg.General = cfg.General or {}
cfg.General.dataDirectory = cfg.General.dataDirectory or "/etc/upm"
cfg.General.cacheDirectory = cfg.General.cacheDirectory or "/etc/upm/cache"
cfg.Repositories = cfg.Repositories or {main = "https://oz-craft.pickardayune.com/upm/main/"}

config.bracket:save("/etc/upm.cfg", cfg)

if type(opts.root) ~= "string" then opts.root = "/" end
opts.root = path.canonical(opts.root)

-- create directories
os.execute("mkdir -p " .. path.concat(opts.root, cfg.General.dataDirectory))
os.execute("mkdir -p " .. path.concat(opts.root, cfg.General.cacheDirectory))

if opts.root ~= "/" then
  config.bracket:save(path.concat(opts.root, "/etc/upm.cfg"), cfg)
end

local usage = "\
UPM - the ULOS Package Manager\
\
usage: \27[36mupm \27[39m[\27[93moptions\27[39m] \27[96mCOMMAND \27[39m[\27[96m...\27[39m]\
\
Available \27[96mCOMMAND\27[39ms:\
  \27[96minstall \27[91mPACKAGE ...\27[39m\
    Install the specified \27[91mPACKAGE\27[39m(s).\
\
  \27[96mremove \27[91mPACKAGE ...\27[39m\
    Remove the specified \27[91mPACKAGE\27[39m(s).\
\
  \27[96mupdate\27[39m\
    Update (refetch) the repository package lists.\
\
  \27[96mupgrade\27[39m\
    Upgrade installed packages.\
\
  \27[96msearch \27[91mPACKAGE\27[39m\
    Search local package lists for \27[91mPACKAGE\27[39m, and\
    display information about it.\
\
  \27[96mlist\27[39m [\27[91mTARGET\27[39m]\
    List packages.  If \27[91mTARGET\27[39m is 'all',\
    then list packages from all repos;  if \27[91mTARGET\27[37m\
    is 'installed', then print all installed\
    packages;  otherewise, print all the packages\
    in the repo specified by \27[91mTARGET\27[37m.\
    \27[91mTARGET\27[37m defaults to 'installed'.\
\
Available \27[93moption\27[39ms:\
  \27[93m-q\27[39m            Be quiet;  no log output.\
  \27[93m-f\27[39m            Skip checks for package version and\
                              installation status.\
  \27[93m-v\27[39m            Be verbose;  overrides \27[93m-q\27[39m.\
  \27[93m-y\27[39m            Automatically assume 'yes' for\
                              all prompts.\
  \27[93m--root\27[39m=\27[33mPATH\27[39m   Treat \27[33mPATH\27[39m as the root filesystem\
                instead of /.\
\
The ULOS Package Manager is copyright (c) 2021\
Ocawesome101 under the DSLv2.\
"

local pfx = {
  info = "\27[92m::\27[39m ",
  warn = "\27[93m::\27[39m ",
  err = "\27[91m::\27[39m "
}

local function log(...)
  if opts.v or not opts.q then
    io.stderr:write(...)
    io.stderr:write("\n")
  end
end

local function exit(reason)
  log(pfx.err, reason)
  os.exit(1)
end

local installed, ipath
do
  ipath = path.concat(opts.root, cfg.General.dataDirectory, "installed.list")

  local ilist = path.concat(opts.root, cfg.General.dataDirectory, "installed.list")
  
  if not fs.stat(ilist) then
    local handle, err = io.open(ilist, "w")
    if not handle then
      exit("cannot create installed.list: " .. err)
    end
    handle:write("{}")
    handle:close()
  end

  local inst, err = config.table:load(ipath)

  if not inst and err then
    exit("cannot open installed.list: " .. err)
  end
  installed = inst
end

local search, update, download, extract, install_package, install

function search(name, re)
  if opts.v then log(pfx.info, "querying repositories for package ", name) end
  local repos = cfg.Repositories
  for k, v in pairs(repos) do
    if opts.v then log(pfx.info, "searching list ", k) end
    local data, err = config.table:load(path.concat(opts.root,
      cfg.General.dataDirectory, k .. ".list"))
    if not data then
      log(pfx.warn, "list ", k, " is nonexistent; run 'upm update' to refresh")
    else
      if data.packages[name] then
        return data.packages[name], k
      end
      if re then
        for k,v in pairs(data.packages) do
          if k:match(name) then
            return data.packages[name], k
          end
        end
      end
    end
  end
  exit("package " .. name .. " not found")
end

function update()
  log(pfx.info, "refreshing package lists")
  local repos = cfg.Repositories
  for k, v in pairs(repos) do
    log(pfx.info, "refreshing list: ", k)
    local url = v .. "/packages.list"
    download(url, path.concat(opts.root, cfg.General.dataDirectory, k .. ".list"))
  end
end

function download(url, dest)
  log(pfx.warn, "downloading ", url, " as ", dest)
  local out, err = io.open(dest, "w")
  if not out then
    exit(dest .. ": " .. err)
  end

  local handle, err = network.request(url)
  if not handle then
    out:close() -- just in case
    exit(err)
  end

  repeat
    local chunk = handle:read(2048)
    if chunk then out:write(chunk) end
  until not chunk
  handle:close()
  out:close()
end

function extract(package)
  log(pfx.info, "extracting ", package)
  local base, err = io.open(package, "r")
  if not base then
    exit(package .. ": " .. err)
  end
  local files = {}
  for file, diter, len in mtar.unarchive(base) do
    files[#files+1] = file
    if opts.v then
      log("  ", pfx.info, "extract file: ", file, " (length ", len, ")")
    end
    local absolute = path.concat(opts.root, file)
    local segments = path.split(absolute)
    for i=1, #segments - 1, 1 do
      local create = table.concat(segments, "/", 1, i)
      if not fs.stat(create) then
        local ok, err = fs.touch(create, filetypes.directory)
        if not ok and err then
          log(pfx.err, "failed to create directory " .. create .. ": " .. err)
          exit("leaving any already-created files - manual cleanup may be required!")
        end
      end
    end
    if opts.v then
      log("   ", pfx.info, "writing to: ", absolute)
    end
    local handle, err = io.open(absolute, "w")
    if not handle then
      exit(absolute .. ": " .. err)
    end
    while true do
      local chunk = diter(math.min(len, 2048))
      if not chunk then break end
      handle:write(chunk)
    end
    handle:close()
  end
  base:close()
  log(pfx.info, "ok")
  return files
end

function install_package(name)
  local data, err = search(name)
  if not data then
    exit("failed reading metadata for package " .. name .. ": " .. err)
  end
  local files = extract(path.concat(opts.root, cfg.General.cacheDirectory, name .. ".mtar"))
  installed[name] = {info = data, files = files}
end

local function dl_pkg(name, repo, data)
  download(cfg.Repositories[repo] .. data.mtar,
    path.concat(opts.root, cfg.General.cacheDirectory, name .. ".mtar"))
end

local function install(packages)
  if #packages == 0 then
    exit("no packages to install")
  end
  
  local to_install = {}
  local resolve, resolving = nil, {}
  resolve = function(pkg)
    local data, repo = search(pkg)
    if installed[pkg] and installed[pkg].info.version >= data.version
        and not opts.f then
      log(pfx.err, pkg .. ": package is already installed")
    elseif resolving[pkg] then
      log(pfx.warn, pkg .. ": circular dependency detected")
    else
      to_install[pkg] = {data = data, repo = repo}
      if data.dependencies then
        local orp = resolving[pkg]
        resolving[pkg] = true
        for i, dep in pairs(data.dependencies) do
          resolve(dep)
        end
        resolving[pkg] = orp
      end
    end
  end

  log(pfx.info, "resolving dependencies")
  for i=1, #packages, 1 do
    resolve(packages[i])
  end

  log(pfx.info, "packages to install: ")
  for k in pairs(to_install) do
    io.write(k, "  ")
  end
  
  if not opts.y then
    io.write("\n\nContinue? [Y/n] ")
    repeat
      local c = io.read("l")
      if c == "n" then os.exit() end
      if c ~= "y" and c ~= "" then io.write("Please enter 'y' or 'n': ") end
    until c == "y" or c == ""
  end

  log(pfx.info, "downloading packages")
  for k, v in pairs(to_install) do
    dl_pkg(k, v.repo, v.data)
  end

  log(pfx.info, "installing packages")
  for k in pairs(to_install) do
    install_package(k)
  end

  config.table:save(ipath, installed)
end

if opts.help or args[1] == "help" then
  io.stderr:write(usage)
  os.exit(1)
end

if #args == 0 then
  exit("an operation is required; see 'upm --help'")
end

if args[1] == "install" then
  if not args[2] then
    exit("command verb 'install' requires at least one argument")
  end
  
  table.remove(args, 1)
  install(args)
elseif args[1] == "upgrade" then
  local to_upgrade = {}
  for k, v in pairs(installed) do
    local data, repo = search(k)
    if not (installed[k] and installed[k].info.version >= data.version
        and not opts.f) then
      log(pfx.info, "updating ", k)
      to_upgrade[#to_upgrade+1] = k
    end
  end
  install(to_upgrade)
elseif args[1] == "remove" then
  if not args[2] then
    exit("command verb 'remove' requires at least one argument")
  end
  local rm = assert(loadfile("/bin/rm.lua"))
  for i=2, #args, 1 do
    local ent = installed[args[i]]
    if not ent then
      log(pfx.err, "package ", args[i], " is not installed")
    else
      log(pfx.info, "removing files")
      for i, file in ipairs(ent.files) do
        rm("-rf", path.concat(opts.root, file))
      end
      log(pfx.info, "unregistering package")
      installed[args[i]] = nil
    end
  end
  config.table:save(ipath, installed)
elseif args[1] == "update" then
  update()
elseif args[1] == "search" then
  if not args[2] then
    exit("command verb 'search' requires at least one argument")
  end
  for i=2, #args, 1 do
    local data, repo = search(args[i], true)
    io.write("\27[94m", repo, "\27[39m/", args[i], " ",
      installed[args[i]] and "\27[96m(installed)\27[39m" or "", "\n")
    io.write("  \27[92mAuthor: \27[39m", data.author or "(unknown)", "\n")
    io.write("  \27[92mDesc: \27[39m", data.description or "(no description)", "\n")
  end
elseif args[1] == "list" then
  if args[2] == "installed" then
    for k in pairs(installed) do
      print(k)
    end
  elseif args[2] == "all" or not args[2] then
    for k, v in pairs(cfg.Repositories) do
      if opts.v then log(pfx.info, "searching list ", k) end
      local data, err = config.table:load(path.concat(opts.root,
        cfg.General.dataDirectory, k .. ".list"))
      if not data then
        log(pfx.warn, "list ", k, " is nonexistent; run 'upm update' to refresh")
      else
        for p in pairs(data.packages) do
          print(p)
        end
      end
    end
  elseif cfg.Repositories[args[2]] then
    local data, err = config.table:load(path.concat(opts.root,
      cfg.General.dataDirectory, args[2] .. ".list"))
    if not data then
      log(pfx.warn, "list ", args[2], " is nonexistent; run 'upm update' to refresh")
    else
      for p in pairs(data.packages) do
        print(p)
      end
    end
  else
    exit("cannot determine target '" .. args[2] .. "'")
  end
else
  exit("operation '" .. args[1] .. "' is unrecognized")
end
