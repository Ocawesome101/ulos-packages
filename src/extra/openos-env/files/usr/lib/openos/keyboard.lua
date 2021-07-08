-- whooooooo, boy, this is interesting --

local term = require("openos/term")

local process = require("process")

local kdown = {}

local keys = {
  lc = 0x1d,
  rc = 0x9d
}

process.spawn {
  name = "kbevtlisteenr",
  func = function()
    while true do
      local sig = table.pack(coroutine.yield())
      if sig[1] == "key_down" then
        kdown[sig[2]] = kdown[sig[2]] or {}
        kdown[sig[4]] = true
      elseif sig[1] == "key_up" then
        kdown[sig[2]] = kdown[sig[2]] or {}
        kdown[sig[4]] = false
      end
    end
  end
}

local lib = {}

function lib.isAltDown() return false end
function lib.isControlDown(a) return kdown[keys.lc] or kdown[keys.rc] end
function lib.isShiftDown() return false end

return lib
