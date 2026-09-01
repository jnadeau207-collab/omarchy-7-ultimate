o.window(".*[Rr]esolve.*", {
  float = true,
  stay_focused = true,
  no_follow_mouse = true,
  tag = "-default-opacity",
  opacity = "1 1",
})

o.window({ class = ".*[Rr]esolve.*", title = "^DaVinci Resolve( Studio)? - .+$" }, { fullscreen = true })
o.window({ class = ".*[Rr]esolve.*", title = "^(DaVinci Resolve( Studio)? - .+|Project Manager|Preferences|Find Directory|Dialog)$" }, { stay_focused = false })
