-- help app --

local app = {}

local help = {
  "Unable to load /help.txt."
}

local fd = fread("/usr/share/osgui/help.txt")
if fd then
  help = {}
  for line in fd:gmatch("[^\n]+") do
    line = line:gsub("\\n", "")
    help[#help + 1] = line
  end
end

function app:init()
  self.w = 80
  self.h = 25
  self.x = 10
  self.y = 5
  self.labels = osgui.labelgroup()
  for i=1, #help, 1 do
    if help[i] ~= "" then
      self.labels:add {
        fg = 0x000000,
        x = (help[i]:sub(1,1)~=" "and(40 - (#help[i] // 2)) or 1) + 1,
        y = 1 + i,
        text = help[i]
      }
    end
  end
end

function app:refresh()
  self.labels:draw(self)
end

function app:click()
end

function app:key()
end

function app:scroll(n)
  self.labels:doscroll(n)
end

function app:close()
end

return osgui.window(app, "Help")
