-- openos: run programs in a mostly-OpenOS-compatible environment --

local args, opts = require("argutil").parse(...)

if #args == 0 or opts.help then
  io.stderr:write([[]])
end

local env = {}

for k,v in pairs(_G) do env[k] = v end
env.package = {}
for k,v in pairs(package) do env.package[k] = v end

local loaded = {
  _G = env,
  io = io,
  package = env.package,
  math = math,
  table = table,
  string = string,
  coroutine = coroutine,
  computer = package.loaded.computer,
  component = package.loaded.component
}

setmetatable(env.package.loaded, {__index = package.loaded})

env.package.loaded = loaded
local loading = {}

env.package.path = package.path .. ";/usr/lib/openos/?.lua"

function _G.require(module)
  if loaded[module] then
    return loaded[module]
  elseif not loading[module] then
    local library, status, step

    step, library, status = "not found",
      package.searchpath(module, env.package.path)

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

