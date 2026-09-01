pragma Singleton
import QtQuick
import "SemanticMetrics.js" as Metrics

QtObject {
  id: root

  readonly property var operationStates: Metrics.operationIds()

  function operation(stateId) { return Metrics.operationDefinition(stateId) }
  function text(profile, value) { return profile ? profile.text(value) : String(value) }
  function metric(profile, value, minimum) {
    return profile ? profile.metric(value, minimum) : Math.max(minimum === undefined ? 0 : minimum, value)
  }
  function font(profile, value) { return profile ? profile.font(value) : value }
  function duration(profile, value) {
    if (profile) return profile.duration(value)
    return Tokens.motion.reduced || Tokens.accessibility.reducedMotion ? 0 : value
  }
  function minimumTarget(profile) {
    if (profile) return profile.minimumTarget
    if (Tokens.density.mode === "touch") return Tokens.hitTargets.touch
    if (Tokens.density.mode === "compact") return Tokens.hitTargets.compact
    return Tokens.hitTargets.comfortable
  }
  function toneColor(tone, profile) {
    if (profile) return profile.toneColor(tone)
    if (tone === "success") return Tokens.state.success
    if (tone === "warning") return Tokens.state.warning
    if (tone === "danger") return Tokens.state.danger
    if (tone === "info") return Tokens.state.info
    return Tokens.accent.primary
  }
  function accessibleProgress(label, value, indeterminate) {
    if (indeterminate) return label + ": progress is indeterminate."
    return label + ": " + Math.round(Math.max(0, Math.min(1, value)) * 100)
      + " percent. Numeric AT-SPI value export is not available in the installed Qt runtime."
  }
}
