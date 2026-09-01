
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

require("hypr.monitors")

require("default.hypr.omarchy")

require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
if _G.omarchy_apply_desktop_look then
  _G.omarchy_apply_desktop_look()
end
require("hypr.autostart")

require("default.hypr.toggles")

