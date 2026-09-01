
hl.layer_rule({ match = { namespace = "omarchy-bar" }, no_anim = true, animation = "none" })

hl.layer_rule({ match = { namespace = "^(omarchy-menu|omarchy-image-selector|omarchy-emojis|omarchy-clipboard|omarchy-keyboard-panel)$" }, no_anim = true, animation = "none" })

o.window({ class = "^org.quickshell$", title = "^Omarchy shell – dev gallery$" }, { maximize = true })
