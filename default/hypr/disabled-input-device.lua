
local paths = require("default.hypr.paths")

return function(kind)
  local file = io.open(paths.home .. "/.local/state/omarchy/toggles/hypr/" .. kind .. "-disabled-name", "r")
  if not file then
    return
  end

  local name = file:read("*l")
  file:close()

  if name and name ~= "" then
    hl.device({ name = name, enabled = false })
  end
end
