pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Resolved semantic design tokens for every first-party surface. The canonical
// payload is ~/.local/state/omarchy/current/design-tokens-v0.json, generated
// atomically from colors.toml plus the theme and user shell.toml layers by
// omarchy-theme-resolve-tokens. Invalid input never replaces the last known
// good payload; invalid hand edits are rejected here without clearing it.
QtObject {
  id: root

  readonly property string schemaVersion: "omarchy.design-tokens.v0"
  readonly property string home: Quickshell.env("HOME")
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string currentPath: home + "/.local/state/omarchy/current"
  readonly property string currentThemePath: currentPath + "/theme"
  readonly property string payloadPath: currentPath + "/design-tokens-v0.json"

  property var payload: ({})
  property bool ready: false
  property bool resolveQueued: false
  property int compositorCornerRadius: Style.cornerRadius
  onCompositorCornerRadiusChanged: scheduleResolve()

  function value(path, fallback) {
    var cursor = payload
    var parts = String(path || "").split(".")
    for (var i = 0; i < parts.length; i++) {
      if (!cursor || typeof cursor !== "object" || cursor[parts[i]] === undefined) return fallback
      cursor = cursor[parts[i]]
    }
    return cursor
  }

  function colorValue(path, fallback) {
    var candidate = value(path, "")
    if (typeof candidate !== "string" || !candidate.match(/^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/)) return fallback
    return candidate
  }

  function numberValue(path, fallback) {
    var candidate = Number(value(path, NaN))
    return isFinite(candidate) ? candidate : fallback
  }

  function boolValue(path, fallback) {
    var candidate = value(path, null)
    return typeof candidate === "boolean" ? candidate : fallback
  }

  function candidateValue(candidate, path) {
    var cursor = candidate
    var parts = String(path || "").split(".")
    for (var i = 0; i < parts.length; i++) {
      if (!cursor || typeof cursor !== "object" || cursor[parts[i]] === undefined) return undefined
      cursor = cursor[parts[i]]
    }
    return cursor
  }

  function validPayload(candidate) {
    if (!candidate || typeof candidate !== "object" || candidate.schemaVersion !== schemaVersion) return false
    if (candidate.mode !== "dark" && candidate.mode !== "light") return false
    var groups = [
      "surface", "text", "accent", "selection", "state", "focus", "border", "chrome", "caption",
      "typography", "icons", "hitTargets", "density", "radii", "elevation", "effects", "motion",
      "accessibility", "components"
    ]
    for (var i = 0; i < groups.length; i++) {
      if (!candidate[groups[i]] || typeof candidate[groups[i]] !== "object") return false
    }
    var colors = [
      "surface.canvas", "surface.base", "surface.raised", "surface.glass", "surface.overlay",
      "text.primary", "text.secondary", "text.disabled", "accent.primary", "accent.hover", "accent.pressed",
      "selection.background", "selection.foreground", "state.success", "state.warning", "state.danger", "state.info",
      "focus.ring", "border.subtle", "border.strong", "chrome.glass", "chrome.menu", "chrome.hover", "chrome.active",
      "chrome.pressed", "chrome.glow", "chrome.start", "chrome.edge", "caption.bar", "caption.text",
      "caption.close.background", "caption.close.foreground", "caption.maximize.background", "caption.maximize.foreground",
      "caption.minimize.background", "caption.minimize.foreground", "effects.shadow.color"
    ]
    for (i = 0; i < colors.length; i++) {
      var color = candidateValue(candidate, colors[i])
      if (typeof color !== "string" || !color.match(/^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/)) return false
    }
    var numbers = [
      "focus.ringWidthPx", "focus.ringOffsetPx", "density.scale", "radii.small", "radii.medium", "radii.large",
      "motion.fastMs", "motion.normalMs", "motion.slowMs", "effects.blur.radiusPx", "effects.blur.passes",
      "effects.shadow.radiusPx", "effects.shadow.offsetXPx", "effects.shadow.offsetYPx",
      "accessibility.minimumTextContrast", "accessibility.minimumLargeTextContrast"
    ]
    var componentNames = [
      "controlGap", "controlPaddingX", "controlPaddingY", "inputPaddingY", "controlHeight", "popupRowHeight",
      "rowGap", "rowPaddingX", "labelGap", "panelGap", "panelPadding", "popupPadding", "dropdownWidth",
      "searchableDropdownWidth", "numberFieldWidth", "searchablePopupMinHeight", "taskbarHeight", "captionHeight",
      "captionButtonSize", "captionButtonPadding", "captionHorizontalPadding"
    ]
    for (i = 0; i < componentNames.length; i++) numbers.push("components." + componentNames[i])
    var numericMaps = {
      "typography.sizesPx": ["caption", "bodySmall", "body", "subtitle", "title", "heading", "display", "displayLarge"],
      "typography.weights": ["regular", "medium", "semibold", "bold"],
      "icons.sizesPx": ["small", "default", "large"],
      "hitTargets": ["minimum", "compact", "comfortable", "touch"],
      "elevation": ["none", "low", "medium", "high"],
      "accessibility.contrast": ["primaryText", "secondaryText", "selectionText", "captionText", "captionClose", "captionMaximize", "captionMinimize"]
    }
    for (var prefix in numericMaps) {
      for (var ni = 0; ni < numericMaps[prefix].length; ni++) numbers.push(prefix + "." + numericMaps[prefix][ni])
    }
    for (i = 0; i < numbers.length; i++) {
      var number = candidateValue(candidate, numbers[i])
      if (typeof number !== "number" || !isFinite(number)) return false
    }
    if (["compact", "comfortable", "touch"].indexOf(candidate.density.mode) < 0) return false
    if (typeof candidate.typography.family !== "string" || !candidate.typography.family) return false
    if (typeof candidate.icons.family !== "string" || !candidate.icons.family) return false
    if (typeof candidate.motion.easing !== "string" || !candidate.motion.easing) return false
    if (typeof candidate.motion.reduced !== "boolean") return false
    if (typeof candidate.accessibility.reducedMotion !== "boolean" || typeof candidate.accessibility.highContrast !== "boolean") return false
    if (candidate.accessibility.largeText !== undefined && typeof candidate.accessibility.largeText !== "boolean") return false
    if (candidate.accessibility.textScale !== undefined
        && (typeof candidate.accessibility.textScale !== "number" || !isFinite(candidate.accessibility.textScale))) return false
    if (typeof candidate.effects.blur.enabled !== "boolean" || typeof candidate.effects.shadow.enabled !== "boolean") return false
    return true
  }

  function applyResolvedPayload(raw) {
    var candidate
    try {
      candidate = typeof raw === "string" ? JSON.parse(raw) : raw
    } catch (error) {
      console.warn("Design tokens: refusing malformed resolved payload: " + error)
      return false
    }
    if (!validPayload(candidate)) {
      console.warn("Design tokens: refusing payload with an incomplete or incompatible contract")
      return false
    }
    payload = candidate
    ready = true
    return true
  }

  function scheduleResolve() {
    if (!omarchyPath || !home) return
    if (resolver.running) {
      resolveQueued = true
      return
    }
    resolveTimer.restart()
  }

  readonly property QtObject surface: QtObject {
    property color canvas: root.colorValue("surface.canvas", Color.background)
    property color base: root.colorValue("surface.base", Qt.lighter(Color.background, 1.08))
    property color raised: root.colorValue("surface.raised", Qt.lighter(Color.background, 1.16))
    property color glass: root.colorValue("surface.glass", Util.alpha(Color.background, 0.82))
    property color overlay: root.colorValue("surface.overlay", Util.alpha(Color.background, 0.6))
  }

  readonly property QtObject text: QtObject {
    property color primary: root.colorValue("text.primary", Color.foreground)
    property color secondary: root.colorValue("text.secondary", Color.muted)
    property color disabled: root.colorValue("text.disabled", Util.alpha(Color.foreground, 0.4))
  }

  readonly property QtObject accent: QtObject {
    property color primary: root.colorValue("accent.primary", Color.accent)
    property color hover: root.colorValue("accent.hover", Qt.lighter(Color.accent, 1.1))
    property color pressed: root.colorValue("accent.pressed", Qt.darker(Color.accent, 1.1))
  }

  readonly property QtObject selection: QtObject {
    property color background: root.colorValue("selection.background", Color.accent)
    property color foreground: root.colorValue("selection.foreground", Color.foreground)
  }

  readonly property QtObject state: QtObject {
    property color success: root.colorValue("state.success", Color.accent)
    property color warning: root.colorValue("state.warning", Color.urgent)
    property color danger: root.colorValue("state.danger", Color.urgent)
    property color info: root.colorValue("state.info", Color.accent)
  }

  readonly property QtObject focus: QtObject {
    property color ring: root.colorValue("focus.ring", Style.focusBorderColor)
    property int ringWidth: Math.round(root.numberValue("focus.ringWidthPx", Style.focusBorderWidth))
    property int ringOffset: Math.round(root.numberValue("focus.ringOffsetPx", 1))
  }

  readonly property QtObject border: QtObject {
    property color subtle: root.colorValue("border.subtle", Util.alpha(Color.foreground, 0.15))
    property color strong: root.colorValue("border.strong", Util.alpha(Color.foreground, 0.3))
  }

  // Superbar glass and caption chrome share this payload. The old
  // chrome-tokens.json / chrome-tokens-light.json files are generated
  // compatibility adapters for older revisions, never inputs to this object.
  readonly property QtObject chrome: QtObject {
    property color glass: root.colorValue("chrome.glass", Util.alpha(Color.background, 0.62))
    property color menu: root.colorValue("chrome.menu", Util.alpha(Color.background, 0.88))
    property color hover: root.colorValue("chrome.hover", Util.alpha(Color.foreground, 0.10))
    property color active: root.colorValue("chrome.active", Util.alpha(Color.foreground, 0.16))
    property color pressed: root.colorValue("chrome.pressed", Util.alpha(Color.foreground, 0.22))
    property color glow: root.colorValue("chrome.glow", Color.accent)
    property color start: root.colorValue("chrome.start", Color.accent)
    property color edge: root.colorValue("chrome.edge", Util.alpha(Color.foreground, 0.33))
  }

  readonly property QtObject caption: QtObject {
    property color bar: root.colorValue("caption.bar", root.chrome.glass)
    property color text: root.colorValue("caption.text", root.text.primary)
    readonly property QtObject close: QtObject {
      property color background: root.colorValue("caption.close.background", Color.urgent)
      property color foreground: root.colorValue("caption.close.foreground", Color.foreground)
    }
    readonly property QtObject maximize: QtObject {
      property color background: root.colorValue("caption.maximize.background", Color.muted)
      property color foreground: root.colorValue("caption.maximize.foreground", Color.foreground)
    }
    readonly property QtObject minimize: QtObject {
      property color background: root.colorValue("caption.minimize.background", Color.muted)
      property color foreground: root.colorValue("caption.minimize.foreground", Color.foreground)
    }
  }

  readonly property QtObject typography: QtObject {
    property string family: String(root.value("typography.family", Style.font.family))
    readonly property QtObject sizes: QtObject {
      property int caption: Math.round(root.numberValue("typography.sizesPx.caption", Style.font.caption))
      property int bodySmall: Math.round(root.numberValue("typography.sizesPx.bodySmall", Style.font.bodySmall))
      property int body: Math.round(root.numberValue("typography.sizesPx.body", Style.font.body))
      property int subtitle: Math.round(root.numberValue("typography.sizesPx.subtitle", Style.font.subtitle))
      property int title: Math.round(root.numberValue("typography.sizesPx.title", Style.font.title))
      property int heading: Math.round(root.numberValue("typography.sizesPx.heading", Style.font.heading))
      property int display: Math.round(root.numberValue("typography.sizesPx.display", Style.font.display))
      property int displayLarge: Math.round(root.numberValue("typography.sizesPx.displayLarge", Style.font.displayLarge))
    }
    readonly property QtObject weights: QtObject {
      property int regular: Math.round(root.numberValue("typography.weights.regular", 400))
      property int medium: Math.round(root.numberValue("typography.weights.medium", 500))
      property int semibold: Math.round(root.numberValue("typography.weights.semibold", 600))
      property int bold: Math.round(root.numberValue("typography.weights.bold", 700))
    }
  }

  readonly property QtObject icons: QtObject {
    property string family: String(root.value("icons.family", Style.font.family))
    readonly property QtObject sizes: QtObject {
      property int small: Math.round(root.numberValue("icons.sizesPx.small", Style.font.iconSmall))
      property int normal: Math.round(root.numberValue("icons.sizesPx.default", Style.font.icon))
      property int large: Math.round(root.numberValue("icons.sizesPx.large", Style.font.iconLarge))
    }
  }

  readonly property QtObject hitTargets: QtObject {
    property int minimum: Math.round(root.numberValue("hitTargets.minimum", 24))
    property int compact: Math.round(root.numberValue("hitTargets.compact", 28))
    property int comfortable: Math.round(root.numberValue("hitTargets.comfortable", 32))
    property int touch: Math.round(root.numberValue("hitTargets.touch", 44))
  }

  readonly property QtObject density: QtObject {
    property string mode: String(root.value("density.mode", "comfortable"))
    property real scale: root.numberValue("density.scale", 1.0)
  }

  // Preserve the established singular API while exposing the contract name.
  readonly property QtObject radius: QtObject {
    id: radiusTokens
    property int small: Math.round(root.numberValue("radii.small", Math.max(4, Math.round(Style.cornerRadius * 0.5))))
    property int medium: Math.round(root.numberValue("radii.medium", Style.cornerRadius))
    property int large: Math.round(root.numberValue("radii.large", Math.round(Style.cornerRadius * 1.5)))
  }
  readonly property QtObject radii: radiusTokens

  readonly property QtObject elevation: QtObject {
    property int none: Math.round(root.numberValue("elevation.none", 0))
    property int low: Math.round(root.numberValue("elevation.low", 1))
    property int medium: Math.round(root.numberValue("elevation.medium", 4))
    property int high: Math.round(root.numberValue("elevation.high", 8))
  }

  readonly property QtObject effects: QtObject {
    readonly property QtObject blur: QtObject {
      property bool enabled: root.boolValue("effects.blur.enabled", true)
      property int radius: Math.round(root.numberValue("effects.blur.radiusPx", 8))
      property int passes: Math.round(root.numberValue("effects.blur.passes", 2))
    }
    readonly property QtObject shadow: QtObject {
      property bool enabled: root.boolValue("effects.shadow.enabled", true)
      property color color: root.colorValue("effects.shadow.color", root.surface.overlay)
      property int radius: Math.round(root.numberValue("effects.shadow.radiusPx", 8))
      property int offsetX: Math.round(root.numberValue("effects.shadow.offsetXPx", 0))
      property int offsetY: Math.round(root.numberValue("effects.shadow.offsetYPx", 2))
    }
  }

  readonly property QtObject motion: QtObject {
    property int fast: Math.round(root.numberValue("motion.fastMs", 100))
    property int normal: Math.round(root.numberValue("motion.normalMs", 200))
    property int slow: Math.round(root.numberValue("motion.slowMs", 300))
    property string easing: String(root.value("motion.easing", "OutCubic"))
    property bool reduced: root.boolValue("motion.reduced", false)
  }

  readonly property QtObject accessibility: QtObject {
    property bool reducedMotion: root.boolValue("accessibility.reducedMotion", false)
    property bool highContrast: root.boolValue("accessibility.highContrast", false)
    property bool largeText: root.boolValue("accessibility.largeText", false)
    property real textScale: root.numberValue("accessibility.textScale", largeText ? 1.25 : 1.0)
    property real minimumTextContrast: root.numberValue("accessibility.minimumTextContrast", 4.5)
    property real minimumLargeTextContrast: root.numberValue("accessibility.minimumLargeTextContrast", 3.0)
  }

  readonly property QtObject components: QtObject {
    property int controlGap: Math.round(root.numberValue("components.controlGap", Style.spacing.controlGap))
    property int controlPaddingX: Math.round(root.numberValue("components.controlPaddingX", Style.spacing.controlPaddingX))
    property int controlPaddingY: Math.round(root.numberValue("components.controlPaddingY", Style.spacing.controlPaddingY))
    property int inputPaddingY: Math.round(root.numberValue("components.inputPaddingY", Style.spacing.inputPaddingY))
    property int controlHeight: Math.round(root.numberValue("components.controlHeight", Style.spacing.controlHeight))
    property int popupRowHeight: Math.round(root.numberValue("components.popupRowHeight", Style.spacing.popupRowHeight))
    property int rowGap: Math.round(root.numberValue("components.rowGap", Style.spacing.rowGap))
    property int rowPaddingX: Math.round(root.numberValue("components.rowPaddingX", Style.spacing.rowPaddingX))
    property int labelGap: Math.round(root.numberValue("components.labelGap", Style.spacing.labelGap))
    property int panelGap: Math.round(root.numberValue("components.panelGap", Style.spacing.panelGap))
    property int panelPadding: Math.round(root.numberValue("components.panelPadding", Style.spacing.panelPadding))
    property int popupPadding: Math.round(root.numberValue("components.popupPadding", Style.spacing.popupPadding))
    property int dropdownWidth: Math.round(root.numberValue("components.dropdownWidth", Style.spacing.dropdownWidth))
    property int searchableDropdownWidth: Math.round(root.numberValue("components.searchableDropdownWidth", Style.spacing.searchableDropdownWidth))
    property int numberFieldWidth: Math.round(root.numberValue("components.numberFieldWidth", Style.spacing.numberFieldWidth))
    property int searchablePopupMinHeight: Math.round(root.numberValue("components.searchablePopupMinHeight", Style.spacing.searchablePopupMinHeight))
    property int taskbarHeight: Math.round(root.numberValue("components.taskbarHeight", Math.max(48, Style.bar.sizeHorizontal + 22)))
    property int captionHeight: Math.round(root.numberValue("components.captionHeight", 32))
    property int captionButtonSize: Math.round(root.numberValue("components.captionButtonSize", 22))
    property int captionButtonPadding: Math.round(root.numberValue("components.captionButtonPadding", 8))
    property int captionHorizontalPadding: Math.round(root.numberValue("components.captionHorizontalPadding", 12))
  }

  property FileView payloadFile: FileView {
    id: payloadFile
    path: root.payloadPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyResolvedPayload(text())
    onFileChanged: reload()
    onLoadFailed: root.scheduleResolve()
  }

  property FileView colorsInput: FileView {
    path: root.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.scheduleResolve()
    onFileChanged: reload()
    onLoadFailed: root.scheduleResolve()
  }

  property FileView shellInput: FileView {
    path: root.currentThemePath + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.scheduleResolve()
    onFileChanged: reload()
    onLoadFailed: root.scheduleResolve()
  }

  property FileView userShellInput: FileView {
    path: root.home + "/.config/omarchy/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.scheduleResolve()
    onFileChanged: reload()
    onLoadFailed: root.scheduleResolve()
  }

  property FileView themeNameInput: FileView {
    path: root.currentPath + "/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.scheduleResolve()
    onFileChanged: reload()
    onLoadFailed: root.scheduleResolve()
  }

  property Timer resolveTimer: Timer {
    id: resolveTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (resolver.running) root.resolveQueued = true
      else resolver.running = true
    }
  }

  property Process resolver: Process {
    id: resolver
    command: [
      root.omarchyPath + "/bin/omarchy-theme-resolve-tokens",
      "--active",
      "--corner-radius", String(root.compositorCornerRadius)
    ]
    stdout: StdioCollector { id: resolverStdout; waitForEnd: true }
    stderr: StdioCollector { id: resolverStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        payloadFile.reload()
        if (String(resolverStdout.text || "").trim() === "changed") hyprReload.running = true
      } else {
        var detail = String(resolverStderr.text || "").trim()
        console.warn("Design tokens: resolver failed; retaining last known good payload" + (detail ? ": " + detail : ""))
      }
      if (root.resolveQueued) {
        root.resolveQueued = false
        resolveTimer.restart()
      }
    }
  }

  // Color publication reloads Hyprland so the generated adapter reaches
  // hyprbars. This never unloads the native plugin or touches frame geometry.
  property Process hyprReload: Process {
    id: hyprReload
    command: ["hyprctl", "reload"]
  }

  Component.onCompleted: scheduleResolve()
}
