-- UPM: the ULOS Package Manager, but a library version --

local fs = require("filesystem")
local path = require("path")
local mtar = require("mtar")
local size = require("size")
local config = require("config")
local semver = require("semver")
local network = require("network")
local computer = require("computer")
local filetypes = require("filetypes")

local pfx = {
  info = "\27[92m::\27[39m ",
  warn = "\27[93m::\27[39m ",
  err = "\27[91m::\27[39m "
}

local function log(opts, ...)
  if opts.v or not opts.q then
    io.stderr:write(...)
    io.stderr:write("\n")
  end
end

local function exit(opts, reason)
  log(opts, pfx.err, reason)
  os.exit(1)
end

local function cmpver(a, b)
  local v1 = semver.parse(a)
  local v2 = semver.parse(b)
  v1.build = nil
  v2.build = nil
  return semver.isGreater(v1, v2) or semver.build(v1) == semver.build(v2)
end

local installed, ipath, preloaded

local lib = {}

function lib.preload(cfg, opts)
  if installed then return end
  ipath = path.concat(opts.root, cfg.General.dataDirectory, "installed.list")

  local ilist = path.concat(opts.root, cfg.General.dataDirectory, "installed.list")
  
  if not fs.stat(ilist) then
    local handle, err = io.open(ilist, "w")
    if not handle then
      exit(opts, "cannot create installed.list: " .. err)
    end
    handle:write("{}")
    handle:close()
  end

  local inst, err = config.table:load(ipath)

  if not inst and err then
    exit(opts, "cannot open installed.list: " .. err)
  end

  installed = inst
  
  lib.installed = installed
end

local search, update, download, extract, install_package, install

function search(cfg, opts, name, re)
  if opts.v then log(opts, pfx.info, "querying repositories for package ", name) end
  local repos = cfg.Repositories
  local results = {}
  for k, v in pairs(repos) do
    if opts.v then log(opts, pfx.info, "searching list ", k) end
    local data, err = config.table:load(path.concat(opts.root,
      cfg.General.dataDirectory, k .. ".list"))
    if not data then
      log(opts, pfx.warn, "list ", k, " is nonexistent; run 'upm update' to refresh")
      if err then log(opts, pfx.warn, "(err: ", err, ")") end
    else
      local found
      if data.packages[name] then
        if re then
          found = true
          results[#results+1] = {data.packages[name], k, name}
        else
          return data.packages[name], k
        end
      end
      if re and not found then
        for nk,v in pairs(data.packages) do
          if nk:match(name) then
            results[#results+1] = {data.packages[nk], k, nk}
          end
        end
      end
    end
  end
  if re then
    local i = 0
    return function()
      i = i + 1
      if results[i] then return table.unpack(results[i]) end
    end
  end
  exit(opts, "package " .. name .. " not found")
end

function update(cfg, opts)
  log(opts, pfx.info, "refreshing package lists")
  local repos = cfg.Repositories
  for k, v in pairs(repos) do
    log(opts, pfx.info, "refreshing list: ", k)
    local url = v .. "/packages.list"
    download(opts, url, path.concat(opts.root, cfg.General.dataDirectory, k .. ".list"))
  end
end

local function progress(na, nb, a, b)
  local n = math.floor(0.3 * (na / nb * 100))
  io.stdout:write("\27[G[" ..
    ("#"):rep(n) .. ("-"):rep(30 -  n)
    .. "] (" .. a .. "/" .. b .. ")")
  io.stdout:flush()
end

function download(opts, url, dest, total)
  log(opts, pfx.warn, "downloading ", url, " as ", dest)
  local out, err = io.open(dest, "w")
  if not out then
    exit(opts, dest .. ": " .. err)
  end

  local handle, err = network.request(url)
  if not handle then
    out:close() -- just in case
    exit(opts, err)
  end

  local dl = 0
  local lbut = 0

  if total then io.write("\27[G\27[2K[]") io.stdout:flush() end
  repeat
    local chunk = handle:read(2048)
    if chunk then dl = dl + #chunk out:write(chunk) end
    if total then
      if computer.uptime() - lbut > 0.5 or dl >= total then
        lbut = computer.uptime()
        progress(dl, total, size.format(dl), size.format(total))
      end
    end
  until not chunk
  handle:close()
  out:close()
  if total then io.write("\27[G\27[K") end
end

function extract(cfg, opts, package)
  log(opts, pfx.info, "extracting ", package)
  local base, err = io.open(package, "r")
  if not base then
    exit(opts, package .. ": " .. err)
  end
  local files = {}
  for file, diter, len in mtar.unarchive(base) do
    files[#files+1] = file
    if opts.v then
      log(opts, "  ", pfx.info, "extract file: ", file, " (length ", len, ")")
    end
    local absolute = path.concat(opts.root, file)
    local segments = path.split(absolute)
    for i=1, #segments - 1, 1 do
      local create = table.concat(segments, "/", 1, i)
      if not fs.stat(create) then
        local ok, err = fs.touch(create, filetypes.directory)
        if not ok and err then
          log(opts, pfx.err, "failed to create directory " .. create .. ": " .. err)
          exit(opts, "leaving any already-created files - manual cleanup may be required!")
        end
      end
    end
    if opts.v then
      log(opts, "   ", pfx.info, "writing to: ", absolute)
    end
    local handle, err = io.open(absolute, "w")
    if not handle then
      exit(opts, absolute .. ": " .. err)
    end
    while len > 0 do
      local chunk = diter(math.min(len, 2048))
      if not chunk then break end
      len = len - #chunk
      handle:write(chunk)
    end
    handle:close()
  end
  base:close()
  log(opts, pfx.info, "ok")
  return files
end

function install_package(cfg, opts, name)
  local data, err = search(cfg, opts, name)
  if not data then
    exit(opts, "failed reading metadata for package " .. name .. ": " .. err)
  end
  local old_data = installed[name] or {info={version=0},files={}}
  local files = extract(cfg, opts, path.concat(opts.root, cfg.General.cacheDirectory, name .. ".mtar"))
  installed[name] = {info = data, files = files}
  config.table:save(ipath, installed)

  -- remove files that were previously present in this package but aren't
  -- anymore.  TODO: check for file ownership by other packages, and remove
  -- directories.
  local files_to_remove = {}
  local map = {}
  for k, v in pairs(files) do map[v] = true end
  for i, check in ipairs(old_data.files) do
    if not map[check] then
      files_to_remove[#files_to_remove+1] = check
    end
  end
  if #files_to_remove > 0 then
    os.execute("rm -rf " .. table.concat(files_to_remove, " "))
  end
end

local function dl_pkg(cfg, opts, name, repo, data)
  download(opts,
    cfg.Repositories[repo] .. data.mtar,
    path.concat(opts.root, cfg.General.cacheDirectory, name .. ".mtar"),
    data.size)
end

local function install(cfg, opts, packages)
  if #packages == 0 then
    exit(opts, "no packages to install")
  end
  
  local to_install, total_size = {}, 0
  local resolve, resolving = nil, {}
  resolve = function(pkg)
    local data, repo = search(cfg, opts, pkg)
    if installed[pkg] and cmpver(installed[pkg].info.version, data.version)
        and not opts.f then
      log(opts, pfx.err, pkg .. ": package is already installed")
    elseif resolving[pkg] then
      log(opts, pfx.warn, pkg .. ": circular dependency detected")
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

  log(opts, pfx.info, "resolving dependencies")
  for i=1, #packages, 1 do
    resolve(packages[i])
  end

  log(opts, pfx.info, "checking for package conflicts")
  for k, v in pairs(to_install) do
    for _k, _v in pairs(installed) do
      if _v.info.conflicts then
        for __k, __v in pairs(_v.info.conflicts) do
          if k == __v then
            log(opts, pfx.err, "installed package ", _k, " conflicts with package ", __v)
            os.exit(1)
          end
        end
      end
    end
    if v.data.conflicts then
      for _k, _v in pairs(v.data.conflicts) do
        if installed[_v] then
          log(opts, pfx.err, "package ", k, " conflicts with installed package ", _v)
          os.exit(1)
        elseif _v ~= k and to_install[_v] then
          log(opts, pfx.err, "cannot install conflicting packages ", k, " and ", _v)
          os.exit(1)
        end
      end
    end
  end

  local largest = 0
  log(opts, pfx.info, "packages to install:")
  for k, v in pairs(to_install) do
    total_size = total_size + (v.data.size or 0)
    largest = math.max(largest, v.data.size)
    io.write("  " .. k .. "-" .. v.data.version)
  end

  io.write("\n\nTotal download size: " .. size.format(total_size) .. "\n")
  io.write("Space required: " .. size.format(total_size + largest) .. "\n")
  
  if not opts.y then
    io.write("Continue? [Y/n] ")
    repeat
      local c = io.read("l")
      if c == "n" then os.exit() end
      if c ~= "y" and c ~= "" then io.write("Please enter 'y' or 'n': ") end
    until c == "y" or c == ""
  end

  log(opts, pfx.info, "downloading packages")
  for k, v in pairs(to_install) do
    dl_pkg(cfg, opts, k, v.repo, v.data)
  end

  log(opts, pfx.info, "installing packages")
  for k, v in pairs(to_install) do
    install_package(cfg, opts, k, v)
    -- remove package mtar - it just takes up space now
    fs.remove(path.concat(opts.root, cfg.General.cacheDirectory,
      k .. ".mtar"))
  end
end

local function remove(cfg, opts, args)
  local rm = assert(loadfile("/bin/rm.lua"))
  
  log(opts, pfx.info, "packages to remove: ")
  io.write(table.concat(args, "  "), "\n")

  if not opts.y then
    io.write("\nContinue? [Y/n] ")
    repeat
      local c = io.read("l")
      if c == "n" then os.exit() end
      if c ~= "y" and c ~= "" then io.write("Please enter 'y' or 'n': ") end
    until c == "y" or c == ""
  end

  for i=1, #args, 1 do
    local ent = installed[args[i]]
    if not ent then
      log(opts, pfx.err, "package ", args[i], " is not installed")
    else
      log(opts, pfx.info, "removing files")
      local removed = 0
      io.write("\27[G\27[2K")
      for i, file in ipairs(ent.files) do
        removed = removed + 1
        rm("-rf", path.concat(opts.root, file))
        progress(removed, #ent.files, tostring(removed), tostring(#ent.files))
      end
      io.write("\27[G\27[2K")
      log(opts, pfx.info, "unregistering package")
      installed[args[i]] = nil
    end
  end
  config.table:save(ipath, installed)
end

function lib.upgrade(cfg, opts)
  local to_upgrade = {}
  for k, v in pairs(installed) do
    local data, repo = search(cfg, opts, k)
    if not (installed[k] and cmpver(installed[k].info.version, data.version)
        and not opts.f) then
      log(opts, pfx.info, "updating ", k)
      to_upgrade[#to_upgrade+1] = k
    end
  end
  install(cfg, opts, to_upgrade)
end

function lib.cli_search(cfg, opts, args)
  lib.preload()
  for i=1, #args, 1 do
    for data, repo, name in search(cfg, opts, args[i], true) do
      io.write("\27[94m", repo, "\27[39m/", name, "\27[90m-",
        data.version, "\27[37m ",
        installed[name] and "\27[96m(installed)\27[39m" or "", "\n")
      io.write("  \27[92mAuthor: \27[39m", data.author or "(unknown)", "\n")
      io.write("  \27[92mDesc: \27[39m", data.description or
        "(no description)", "\n")
    end
  end
end

function lib.cli_list(cfg, opts, args)
  if args[1] == "installed" then
    for k in pairs(installed) do
      print(k)
    end
  elseif args[1] == "all" or not args[1] then
    for k, v in pairs(cfg.Repositories) do
      if opts.v then log(pfx.info, "searching list ", k) end
      local data, err = config.table:load(path.concat(opts.root,
        cfg.General.dataDirectory, k .. ".list"))
      if not data then
        log(pfx.warn,"list ", k, " is nonexistent; run 'upm update' to refresh")
        if err then log(pfx.warn, "(err: ", err, ")") end
      else
        for p in pairs(data.packages) do
          --io.stderr:write(p, "\n")
          print(p)
        end
      end
    end
  elseif cfg.Repositories[args[1]] then
    local data, err = config.table:load(path.concat(opts.root,
      cfg.General.dataDirectory, args[1] .. ".list"))
    if not data then
      log(pfx.warn, "list ", args[1], " is nonexistent; run 'upm update' to refresh")
      if err then log(pfx.warn, "(err: ", err, ")") end
    else
      for p in pairs(data.packages) do
        print(p)
      end
    end
  else
    exit("cannot determine target '" .. args[1] .. "'")
  end
end

lib.search=search
lib.update=update
lib.download=download
lib.download_package = dl_pkg
lib.extract=extract
lib.install_package=install_package
lib.install=install
lib.remove=remove

return lib
