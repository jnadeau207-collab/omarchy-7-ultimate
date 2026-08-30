o.window(".*", { float = true })
o.window(".*", { tag = "+default-opacity" })

o.window(".*", { size = { 880, 560 } })

o.window({ modal = true }, { float = true, size = { "window_w", "window_h" } })

o.window(
  {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  { no_focus = true }
)

_G.omarchy_desktop_floats = true
require("default.hypr.apps")
o.window(".*", { float = true })

local function repo_root()
  local omarchy = os.getenv("OMARCHY_PATH") or ""
  if omarchy ~= "" then
    return omarchy
  end
  local src = debug.getinfo(1, "S").source or ""
  src = src:gsub("^@", "")
  local root = src:match("(.+)/default/hypr/desktop%-windows%.lua$")
  return root or ""
end

local function load_start_chrome()
  local root = repo_root()
  if root == "" then
    return nil, "OMARCHY_PATH is unavailable; cannot locate start-chrome.json"
  end
  local file = io.open(root .. "/default/ultimate/start-chrome.json", "r")
  if not file then
    return nil, "cannot read start-chrome.json"
  end
  local body = file:read("*a")
  file:close()
  local chrome = {}
  for key, value in body:gmatch('"([A-Za-z]+)"%s*:%s*(%d+)') do
    chrome[key] = tonumber(value)
  end
  if not chrome.cardWidth or not chrome.cardHeight or not chrome.barHeight or chrome.cardLeftMargin == nil then
    return nil, "start-chrome.json is incomplete"
  end
  return chrome, nil
end

local start_chrome, start_chrome_error = load_start_chrome()
if not start_chrome then
  error(start_chrome_error)
end

local function load_csd_patterns()
  local root = repo_root()
  if root == "" then
    return {}
  end
  local file = io.open(root .. "/default/ultimate/csd-clients.json", "r")
  if not file then
    return {}
  end
  local body = file:read("*a")
  file:close()
  local patterns = {}
  for quoted in body:gmatch('"([^"]+)"') do
    if quoted ~= "classPatterns" then
      local pat = quoted:gsub("\\\\", "\\")
      patterns[#patterns + 1] = pat
    end
  end
  return patterns
end

local function theme_is_light()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return false
  end
  local file = io.open(home .. "/.local/state/omarchy/current/theme/colors.toml", "r")
  if not file then
    return false
  end
  local body = file:read("*a")
  file:close()
  return body:match('mode%s*=%s*"light"') ~= nil
end

local function chrome_tokens_path()
  local home = os.getenv("HOME") or ""
  if home == "" then
    return nil, "HOME is unavailable; cannot locate resolved chrome tokens"
  end
  return home .. "/.local/state/omarchy/current/chrome-tokens-v0.json"
end

local function load_chrome_tokens()
  local path, path_error = chrome_tokens_path()
  if not path then
    return nil, path_error
  end
  local file = io.open(path, "r")
  if not file then
    return nil, "cannot read resolved chrome token adapter at " .. path
  end
  local body = file:read("*a")
  file:close()
  local tokens = {}
  for key, value in body:gmatch('"([A-Za-z0-9_]+)"%s*:%s*"([^"]*)"') do
    tokens[key] = value
  end
  if tokens._schemaVersion ~= "omarchy.chrome-adapter.v0" or tokens._sourceSchemaVersion ~= "omarchy.design-tokens.v0" then
    return nil, "resolved chrome token adapter has an incompatible schema"
  end
  local expected_mode = theme_is_light() and "light" or "dark"
  if tokens._mode ~= expected_mode then
    return nil, "resolved chrome token adapter mode does not match the active theme"
  end
  local required = {
    "glassRed", "glassGreen", "glassBlue", "glassAlphaPct", "hyprbarsTextHex",
    "captionCloseBgHex", "captionCloseFgHex", "captionMaxBgHex", "captionMaxFgHex",
    "captionMinBgHex", "captionMinFgHex", "borderActiveHex", "borderInactiveHex",
  }
  for _, key in ipairs(required) do
    if not tokens[key] or tokens[key] == "" then
      return nil, "resolved chrome token adapter is missing " .. key
    end
  end
  for _, key in ipairs({ "glassRed", "glassGreen", "glassBlue" }) do
    local value = tonumber(tokens[key])
    if not value or value < 0 or value > 255 or value % 1 ~= 0 then
      return nil, "resolved chrome token adapter has invalid " .. key
    end
  end
  local alpha = tonumber(tokens.glassAlphaPct)
  if not alpha or alpha < 0 or alpha > 100 then
    return nil, "resolved chrome token adapter has invalid glassAlphaPct"
  end
  return tokens, nil
end

local function chrome_glass_rgba(tokens)
  local r = tonumber(tokens.glassRed)
  local g = tonumber(tokens.glassGreen)
  local b = tonumber(tokens.glassBlue)
  local pct = tonumber(tokens.glassAlphaPct)
  local a = math.floor(pct * 255 / 100 + 0.5)
  return string.format("rgba(%02x%02x%02x%02x)", r, g, b, a)
end

local function chrome_hex_rgb(tokens, key)
  local hex = tokens[key]
  hex = hex:gsub("^#", "")
  if not hex:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
    error("resolved chrome token adapter has invalid " .. key)
  end
  return string.format("rgb(%s)", hex:sub(1, 6))
end

local function chrome_text_rgb(tokens)
  return chrome_hex_rgb(tokens, "hyprbarsTextHex")
end

local function require_chrome_tokens()
  local tokens, load_error = load_chrome_tokens()
  if not tokens then
    error(load_error)
  end
  return tokens
end

for _, class_pat in ipairs(load_csd_patterns()) do

  o.window(class_pat, { float = true, ["hyprbars:no_bar"] = true, no_shadow = true, no_blur = true, border_size = 0, rounding = 0, size = { 1200, 740 } })
end

o.window("org.omarchy.screensaver", { float = true, fullscreen = true, ["hyprbars:no_bar"] = true })

o.window({ tag = "default-opacity" }, { opacity = "1 1" })
o.window(".*", { opacity = "1 1" })

local function apply_desktop_look()
  local chrome = require_chrome_tokens()
  hl.config({
    general = {
      resize_on_border = true,

      extend_border_grab_area = 4,
      gaps_in = 0,
      gaps_out = 0,
      border_size = 1,
      col = {
        active_border = chrome_hex_rgb(chrome, "borderActiveHex"),
        inactive_border = chrome_hex_rgb(chrome, "borderInactiveHex"),
      },
    },

    input = {
      follow_mouse = 0,
    },
    group = {
      col = {
        border_active = chrome_hex_rgb(chrome, "borderActiveHex"),
        border_inactive = chrome_hex_rgb(chrome, "borderInactiveHex"),
      },
    },
    decoration = {

      rounding = 0,
      rounding_power = 2,
      shadow = {
        enabled = true,
        range = 8,
        render_power = 2,
      },
      blur = {
        enabled = true,
        size = 8,
        passes = 2,
        popups = true,
        vibrancy = 0,
        noise = 0,
      },
    },
    render = {
      cm_auto_hdr = 0,
    },
    cursor = {
      hide_on_key_press = false,
    },
    plugin = {
      hyprbars = {
        enabled = true,
        bar_height = 32,
        bar_part_of_window = true,
        bar_precedence_over_border = true,
        bar_padding = 12,
        bar_button_padding = 8,
        bar_title_enabled = true,
        bar_text_size = 13,
        bar_text_font = "sans-serif",
        bar_text_align = "left",
        bar_buttons_alignment = "right",
        icon_on_hover = false,
        bar_blur = true,
        bar_color = chrome_glass_rgba(chrome),
        ["col.text"] = chrome_text_rgb(chrome),
        on_double_click = "omarchy-shell window toggleMaximize 0x{:x}",
      },
    },
  })

  hl.animation({ leaf = "windows", enabled = false })
  hl.animation({ leaf = "windowsIn", enabled = false })
  hl.animation({ leaf = "windowsOut", enabled = false })
end

apply_desktop_look()
_G.omarchy_apply_desktop_look = apply_desktop_look

hl.layer_rule({ match = { namespace = "omarchy-taskbar" }, blur = true })
hl.layer_rule({ match = { namespace = "omarchy-start" }, blur = true })

pcall(function()
  hl.permission("/usr/lib/hyprland-plugins/hyprbars.so", "plugin", "allow")
  hl.permission("/usr/lib/hyprland-plugins/omarchy-minimize.so", "plugin", "allow")
  hl.permission("/usr/local/lib/hyprland-plugins/hyprbars.so", "plugin", "allow")
  hl.permission("/usr/local/lib/hyprland-plugins/omarchy-minimize.so", "plugin", "allow")
  hl.permission(".*/default/hypr/plugins/hyprbars/hyprbars.so", "plugin", "allow")
  hl.permission(".*/default/hypr/plugins/omarchy-minimize/omarchy-minimize.so", "plugin", "allow")
end)

local function plugin_table()
  local plugin = hl.plugin
  if type(plugin) ~= "table" then
    return nil
  end
  return plugin
end

local function hyprbars_ready()
  local plugin = plugin_table()
  return plugin ~= nil and plugin.hyprbars ~= nil
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function load_so(path)
  if not file_exists(path) then
    return false
  end

  local ok = pcall(function()
    hl.exec_cmd("hyprctl plugin load " .. path)
  end)
  return ok
end

local function first_existing(candidates)
  local i
  for i = 1, #candidates do
    if file_exists(candidates[i]) then
      return candidates[i]
    end
  end
  return nil
end

local function load_hyprbars()
  if hyprbars_ready() then
    return true
  end
  local omarchy = os.getenv("OMARCHY_PATH") or ""

  local candidates = {}
  if omarchy ~= "" then
    candidates[#candidates + 1] = omarchy .. "/default/hypr/plugins/hyprbars/hyprbars.so"
  end
  candidates[#candidates + 1] = "/usr/lib/hyprland-plugins/hyprbars.so"
  candidates[#candidates + 1] = "/usr/local/lib/hyprland-plugins/hyprbars.so"
  local path = first_existing(candidates)
  if not path then
    return false
  end
  return load_so(path)
end

local function minimize_ready()
  local plugin = plugin_table()
  return plugin ~= nil and plugin.omarchy_minimize ~= nil
end

local function load_omarchy_minimize()
  if minimize_ready() then
    return true
  end
  local omarchy = os.getenv("OMARCHY_PATH") or ""
  local candidates = {}
  if omarchy ~= "" then
    candidates[#candidates + 1] = omarchy .. "/default/hypr/plugins/omarchy-minimize/omarchy-minimize.so"
  end
  candidates[#candidates + 1] = "/usr/lib/hyprland-plugins/omarchy-minimize.so"
  candidates[#candidates + 1] = "/usr/local/lib/hyprland-plugins/omarchy-minimize.so"
  local path = first_existing(candidates)
  if not path then
    return false
  end
  return load_so(path)
end

local function add_hyprbars_buttons()
  local plugin = plugin_table()
  if not (plugin and plugin.hyprbars and plugin.hyprbars.add_button) then
    return
  end

  local chrome = require_chrome_tokens()
  local sig = (chrome.captionCloseBgHex or "") .. (chrome.captionMaxBgHex or "") .. (chrome.glassRed or "")
  if _G.omarchy_hyprbars_buttons == sig then
    return
  end
  plugin.hyprbars.add_button({
    bg_color = chrome_hex_rgb(chrome, "captionCloseBgHex"),
    fg_color = chrome_hex_rgb(chrome, "captionCloseFgHex"),
    size = 22,
    icon = "×",
    action = "omarchy-shell window close 0x{:x}",
  })
  plugin.hyprbars.add_button({
    bg_color = chrome_hex_rgb(chrome, "captionMaxBgHex"),
    fg_color = chrome_hex_rgb(chrome, "captionMaxFgHex"),
    size = 22,
    icon = "□",
    action = "omarchy-shell window toggleMaximize 0x{:x}",
    hover_action = "omarchy-shell window snapChooser 0x{:x}",
  })
  plugin.hyprbars.add_button({
    bg_color = chrome_hex_rgb(chrome, "captionMinBgHex"),
    fg_color = chrome_hex_rgb(chrome, "captionMinFgHex"),
    size = 22,
    icon = "–",
    action = "omarchy-shell window minimize 0x{:x}",
  })
  _G.omarchy_hyprbars_buttons = sig
end

load_hyprbars()
add_hyprbars_buttons()
load_omarchy_minimize()

hl.on("hyprland.start", function()
  apply_desktop_look()
  load_hyprbars()
  add_hyprbars_buttons()
  load_omarchy_minimize()
end)

local start_clickthrough_bind = nil

local function start_owner_screen()
  local home = os.getenv("HOME") or ""
  local file = io.open(home .. "/.local/state/omarchy/ultimate/start-owner.json", "r")
  if not file then
    return ""
  end
  local raw = file:read("*a") or ""
  file:close()
  return raw:match('"screen"%s*:%s*"([^"]*)"') or ""
end

local function monitor_at_point(pos, mons)
  if type(mons) ~= "table" then
    return nil
  end
  for _, mon in pairs(mons) do
    if type(mon) == "table" and mon.width and mon.height then
      local mx = tonumber(mon.x) or 0
      local my = tonumber(mon.y) or 0
      if pos.x >= mx and pos.x < mx + mon.width and pos.y >= my and pos.y < my + mon.height then
        return mon
      end
    end
  end
  return nil
end

local function start_click_is_on_shell_chrome(pos)
  if not pos or pos.x == nil or pos.y == nil then
    return true
  end
  local mx, my, mh = 0, 0, 1080
  local mon_name = ""
  local ok, mons = pcall(function()
    return hl.get_monitors()
  end)
  if ok and type(mons) == "table" then
    local mon = monitor_at_point(pos, mons)
    if not mon then
      for _, candidate in pairs(mons) do
        if type(candidate) == "table" and candidate.height and (candidate.focused or candidate.focus) then
          mon = candidate
          break
        end
      end
    end
    if type(mon) == "table" then
      mx = tonumber(mon.x) or 0
      my = tonumber(mon.y) or 0
      mh = mon.height or mh
      mon_name = tostring(mon.name or "")
    end
  end
  local bar = start_chrome.barHeight
  local left = start_chrome.cardLeftMargin
  local width = start_chrome.cardWidth
  local height = start_chrome.cardHeight
  local local_x = pos.x - mx
  local local_y = pos.y - my
  if local_y >= mh - bar then
    return true
  end
  local owner = start_owner_screen()
  if owner ~= "" and mon_name ~= "" and owner ~= mon_name then
    return false
  end
  local card_y = mh - bar - height
  if local_x >= left and local_x < left + width and local_y >= card_y and local_y < mh - bar then
    return true
  end
  return false
end

hl.on("layer.opened", function(layer)
  if not layer or layer.namespace ~= "omarchy-start" or start_clickthrough_bind then
    return
  end
  start_clickthrough_bind = hl.bind("mouse:272", function()
    local pos = hl.get_cursor_pos()
    if start_click_is_on_shell_chrome(pos) then
      return
    end
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell dismissOutside"))
  end, { description = "Dismiss Start click-through", mouse = true, non_consuming = true })
end)

hl.on("layer.closed", function(layer)
  if not layer or layer.namespace ~= "omarchy-start" or not start_clickthrough_bind then
    return
  end
  start_clickthrough_bind:unbind()
  start_clickthrough_bind = nil
end)
