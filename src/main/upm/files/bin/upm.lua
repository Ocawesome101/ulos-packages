-- UPM: the ULOS Package Manager --

local config = require("config")
local path = require("path")
local upm = require("upm")

local args, opts = require("argutil").parse(...)

local cfg = config.bracket:load("/etc/upm.cfg") or
  {__load_order={"General","Repositories"}}

cfg.General = cfg.General or {__load_order={"dataDirectory","cacheDirectory"}}
cfg.General.dataDirectory = cfg.General.dataDirectory or "/etc/upm"
cfg.General.cacheDirectory = cfg.General.cacheDirectory or "/etc/upm/cache"
cfg.Repositories = cfg.Repositories or {__load_order={"main","extra"},
  main = "https://oz-craft.pickardayune.com/upm/main/",
 extra = "https://oz-craft.pickardayune.com/upm/extra/"}

config.bracket:save("/etc/upm.cfg", cfg)

if type(opts.root) ~= "string" then opts.root = "/" end
opts.root = path.canonical(opts.root)

-- create directories
os.execute("mkdir -p " .. path.concat(opts.root, cfg.General.dataDirectory))
os.execute("mkdir -p " .. path.concat(opts.root, cfg.General.cacheDirectory))

if opts.root ~= "/" then
  config.bracket:save(path.concat(opts.root, "/etc/upm.cfg"), cfg)
end

upm.preload(cfg, opts)

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

if opts.help or args[1] == "help" then
  io.stderr:write(usage)
  os.exit(1)
end

if #args == 0 then
  exit("an operation is required; see 'upm --help'")
end

local installed = upm.installed

cfg.__load_order = nil
for k,v in pairs(cfg) do v.__load_order = nil end

if args[1] == "install" then
  if not args[2] then
    exit("command verb 'install' requires at least one argument")
  end
  
  table.remove(args, 1)
  upm.install(cfg, opts, args)
elseif args[1] == "upgrade" then
  upm.upgrade(cfg, opts)
elseif args[1] == "remove" then
  if not args[2] then
    exit("command verb 'remove' requires at least one argument")
  end

  table.remove(args, 1)
  upm.remove(cfg, opts, args)
elseif args[1] == "update" then
  upm.update(cfg, opts)
elseif args[1] == "search" then
  if not args[2] then
    exit("command verb 'search' requires at least one argument")
  end
  table.remove(args, 1)
  upm.cli_search(cfg, opts, args)
elseif args[1] == "list" then
  table.remove(args, 1)
  upm.cli_list(cfg, opts, args)
else
  exit("operation '" .. args[1] .. "' is unrecognized")
end
