
local apply = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/bin/omarchy-hyprland-monitor-apply"
local emit = io.popen(apply .. " --emit-lua")
local body = emit and emit:read("*a") or ""
if emit then
  emit:close()
end
if body:match("hl%.monitor") then
  assert(load(body))()
  return
end

local omarchy_monitor_scale = "auto"
hl.monitor({ output = "", mode = "highrr", position = "auto", scale = omarchy_monitor_scale, bitdepth = 8 })

local omarchy_gdk_scale = 1
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
