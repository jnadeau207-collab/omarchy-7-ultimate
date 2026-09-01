
local share = 0.5

local seed = "[workspace special:scratchpad silent] omarchy-agent"

hl.config({
  decoration = {
    dim_special = 0.6,
  },
})

local covering = nil

local function cover(bottom)
  if covering == bottom then
    return
  end
  covering = bottom

  hl.workspace_rule({
    workspace = "special:scratchpad",
    gaps_in = 0,
    gaps_out = { top = 0, right = 0, bottom = bottom, left = 0 },

    no_border = true,

    on_created_empty = seed,
  })
end

local function fit()
  local monitor = hl.get_active_monitor()

  if not monitor or not monitor.scale or monitor.scale <= 0 then
    return
  end

  local reserved = monitor.reserved
  local usable = monitor.height / monitor.scale - reserved.top - reserved.bottom

  cover(math.max(0, math.floor(usable * (1 - share))))
end

cover(0)
fit()

hl.on("monitor.layout_changed", fit)
hl.on("monitor.focused", fit)

hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "easeInOutCubic", style = "slide bottom" })
