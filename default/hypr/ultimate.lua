local paths = require("default.hypr.paths")

local function read_mode()
  local file = io.open(paths.state_home .. "/omarchy/ultimate/mode", "r")
  if not file then
    return "desktop"
  end

  local mode = (file:read("*l") or ""):gsub("%s+", "")
  file:close()

  if mode == "power-user" then
    return "power-user"
  end

  return "desktop"
end

return {
  mode = read_mode,
}
