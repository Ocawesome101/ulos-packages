local path = require("path")
local argutil = require("argutil")

local shell = {}

shell.parse = argutil.parse
shell.resolve = path.canonical

return shell
