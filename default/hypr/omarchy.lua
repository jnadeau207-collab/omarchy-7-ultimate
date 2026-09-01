
require("default.hypr.helpers")
local require_optional = require("default.hypr.require_optional")
local ultimate = require("default.hypr.ultimate")
local mode = ultimate.mode()

require("default.hypr.autostart")
if _G.omarchy_default_bindings ~= false then
  require("default.hypr.bindings.media")
  require("default.hypr.bindings.clipboard")
  if mode == "desktop" then
    require("default.hypr.bindings.desktop")
  else
    require("default.hypr.bindings.tiling")
    require("default.hypr.bindings.utilities")
    require_optional.module("default.hypr.bindings.applications")
  end
  require("default.hypr.bindings.voxtype")
end
require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.qconsole")
require("default.hypr.input")
if mode ~= "desktop" then
  require("default.hypr.windows")
end

require_optional.module("omarchy.current.theme.hyprland")

if mode == "desktop" then
  require("default.hypr.desktop-windows")
end
