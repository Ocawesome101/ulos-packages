-- wrap a gpu proxy so that all functions called on the wrapper are redirected to a buffer --

local blacklist = {
  setActiveBuffer = true,
  getActiveBuffer = true,
  setForeground = true,
  getForeground = true,
  setBackground = true,
  getBackground = true,
  allocateBuffer = true,
  setDepth = true,
  getDepth = true,
  maxDepth = true,
  setResolution = true,
  getResolution = true,
  maxResolution = true,
  totalMemory = true,
  buffers = true,
  getBufferSize = true,
  freeAllBuffers = true,
  freeMemory = true
}

return {
  buffer = function(px, bufi)
    local new = {}
  
    for k, v in pairs(px) do
      if not blacklist[v] then
        new[k] = function(...)
          gpu.setActiveBuffer(bufi)
          return v(...)
        end
      else
        new[k] = v
      end
    end

    return new
  end,

  area = function(px, x, y, w, h)
    local wrap = setmetatable({}, {__index = px})
    function wrap.getResolution() return w, h - 1 end
    wrap.maxResolution = wrap.getResolution
    wrap.setResolution = function() end
    wrap.set = function(_x, _y, t, v) return px.set(
      x + _x - 1, y + _y - 1,
      t:sub(0, (v and h or w) - (v and _y or _x)), v) end
    wrap.get = function(_x, _y) return px.get(x + _x - 1, y + _y - 1) end
    wrap.fill = function(_x, _y, _w, _h, c) return px.fill(
      x + _x - 1, y + _y - 1, math.min(w - _x, _w), math.min(h - _y, _h), c) end
    wrap.copy = function(_x, _y, _w, _h, rx, ry) return px.copy(
      x + _x - 1, y + _y - 1,
      math.min(w - _x + 1, _w), math.min(h - _y + 1, _h),
      rx, ry) end

    wrap.getScreen = px.getScreen

    return wrap
  end
}
