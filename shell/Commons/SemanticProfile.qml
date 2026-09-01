import QtQuick
import "SemanticMetrics.js" as Metrics

QtObject {
  id: root

  property string profileId: "default"
  property string densityMode: Tokens.density.mode
  property real scaleFactor: Tokens.density.scale
  property bool highContrast: Tokens.accessibility.highContrast
  property bool reducedMotion: Tokens.motion.reduced || Tokens.accessibility.reducedMotion
  property bool largeText: Tokens.accessibility.largeText
  property real textScale: Tokens.accessibility.textScale
  property bool rtl: false
  property bool pseudoLocale: false
  property string locale: "en-US"

  property color surfaceCanvas: Tokens.surface.canvas
  property color surfaceBase: Tokens.surface.base
  property color surfaceRaised: Tokens.surface.raised
  property color textPrimary: Tokens.text.primary
  property color textSecondary: Tokens.text.secondary
  property color textDisabled: Tokens.text.disabled
  property color accent: Tokens.accent.primary
  property color success: Tokens.state.success
  property color warning: Tokens.state.warning
  property color danger: Tokens.state.danger
  property color info: Tokens.state.info
  property color focusRing: Tokens.focus.ring
  property color borderStrong: Tokens.border.strong

  readonly property real resolvedDensityScale: Metrics.densityScale(densityMode)
  readonly property real resolvedFontScale: Metrics.fontScale(root)
  readonly property int minimumTarget: Metrics.minimumTarget(root)
  readonly property int focusWidth: highContrast ? Math.max(3, Tokens.focus.ringWidth) : Math.max(1, Tokens.focus.ringWidth)

  function metric(value, minimum) { return Metrics.scaledMetric(value, root, minimum) }
  function font(value) { return Metrics.scaledFont(value, root) }
  function duration(value) { return Metrics.duration(value, root) }
  function text(value) { return Metrics.localize(value, root) }
  function definition(stateId) { return Metrics.operationDefinition(stateId) }
  function contrast(foreground, background) { return Metrics.contrastRatio(foreground, background) }
  function logicalEdges(leading, trailing) { return Metrics.logicalEdges(rtl, leading, trailing) }

  function toneColor(tone) {
    if (tone === "success") return success
    if (tone === "warning") return warning
    if (tone === "danger") return danger
    if (tone === "info") return info
    return accent
  }
}
