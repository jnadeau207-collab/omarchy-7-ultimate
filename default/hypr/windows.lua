
o.window(".*", { suppress_event = "maximize" })

o.window(".*", { tag = "+default-opacity" })

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

require("default.hypr.apps")

o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })
