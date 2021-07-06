-- term library --

local term = {}

local termio = require("termio")

term.getSize = termio.getTernSize
term.getCursor = termio.getCursor
term.setCursor = termio.setCursor
term.isAvailable = function() return true end
term.gpu = function() return require("getgpu")(io.stderr.tty) end
term.clear = function() io.write("\27[2J") end
term.setCursorBlink = function() end
term.getGlobalArea = term.getSize

return term
