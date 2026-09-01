o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })

o.window(
  "(org.omarchy.btop|org.omarchy.terminal|org.omarchy.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|Omarchy|About|TUI.float|imv|mpv)",
  {
    tag = "+floating-window",
  }
)

o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
o.window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

o.window("org.omarchy.about", { float = true })
o.window("org.omarchy.about", { center = true })
o.window("org.omarchy.about", { size = { 920, 480 } })

o.window("dev.tensaku.Tensaku", { float = true })
o.window("dev.tensaku.Tensaku", { center = true })
o.window("omacalc", { float = true })

o.window("org.omarchy.screensaver", { fullscreen = true })
o.window("org.omarchy.screensaver", { float = true })
o.window("org.omarchy.screensaver", { animation = "slide" })

o.window(
  "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
  {
    tag = "-default-opacity",
  }
)
o.window(
  "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
  {
    opacity = "1 1",
  }
)

o.window({ tag = "pop" }, { rounding = 8 })

o.window({ tag = "noidle" }, { idle_inhibit = "always" })
