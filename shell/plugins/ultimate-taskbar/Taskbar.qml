import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../../services/WindowModel.js" as WindowModel

Item {
  id: root

  property string omarchyPath: ""
  property var barWidgetRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property string home: Quickshell.env("HOME")
  property bool barHidden: false
  property int barSize: Tokens.components.taskbarHeight
  property bool vertical: false
  property string position: "bottom"
  property string fontFamily: Tokens.typography.family
  property color foreground: Tokens.text.primary
  property color barForeground: Tokens.text.primary
  property color urgent: Tokens.state.danger
  property bool foregroundAnimationEnabled: true
  // Windows 7 Superbar glass remains graphite rather than palette canvas,
  // but now comes from the same resolved payload as caption chrome. The old
  // default/ultimate/chrome-tokens.json and chrome-tokens-light.json files are
  // generated compatibility adapters. Locked pre-contract reference for the
  // visual regression suite: Qt.rgba(0.11, 0.11, 0.12, 0.62).
  readonly property bool highContrast: Tokens.accessibility.highContrast
  readonly property bool rtl: (shell && shell.summonedRtl) || Qt.application.layoutDirection === Qt.RightToLeft
  SemanticProfile {
    id: chromeProfile
    profileId: "product"
    rtl: root.rtl
    pseudoLocale: !!(shell && shell.summonedPseudoLocale)
  }
  readonly property var productProfile: chromeProfile
  function chromeText(value) {
    return Semantics.text(chromeProfile, value)
  }
  readonly property color chromeBar: Tokens.chrome.glass
  readonly property color chromeHover: Tokens.chrome.hover
  readonly property color chromeActive: Tokens.chrome.active
  readonly property color chromePressed: Tokens.chrome.pressed
  readonly property color chromeMenu: Tokens.chrome.menu
  readonly property color chromeGlow: Tokens.chrome.glow
  readonly property color chromeStart: Tokens.chrome.start
  readonly property color chromeEdge: highContrast ? Tokens.border.strong : Tokens.chrome.edge
  readonly property int chromeEdgeWidth: highContrast ? 2 : 1
  property color background: chromeBar
  property var moduleSlots: []
  readonly property var windowService: shell ? shell.windowService : null
  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var groups: windowService ? windowService.groups : []

  // Kept as the compatibility validation hook during the one-window adapter
  // period. It validates the canonical payload; it never mutates bindings or
  // accepts the legacy flat palette as a second source of truth.
  function applyChromeTokens(payload) {
    return Tokens.validPayload(payload)
  }

  function registerSlot(pluginId, item) {
    if (!item) return
    var next = moduleSlots.slice()
    next.push({ moduleName: String(pluginId || ""), activeItem: item })
    moduleSlots = next
  }

  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot.moduleName !== id || !slot.activeItem) continue
      var item = slot.activeItem
      if (typeof item.open === "function" && typeof item.close === "function" && item.opened !== undefined)
        return item
    }
    return null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item) return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item) return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function panelWidgetIdAt(region, index) {
    var names = ["omarchy.audio", "omarchy.bluetooth", "omarchy.network", "omarchy.monitor", "omarchy.power"]
    return names[Math.round(Number(index)) - 1] || ""
  }

  function run(command) {
    if (command) Util.execDetached(command)
  }

  function debugBarGeometry() {
    return []
  }

  function toggleTransparency() {
    return
  }

  function togglePin(group) {
    if (root.windowService) root.windowService.togglePin(group)
  }

  function screenNameOf(screen) {
    return screen && screen.name ? String(screen.name) : ""
  }

  function screenIsPrimary(screen) {
    var monitors = root.windowService ? root.windowService.monitorsIpc : []
    return WindowModel.isPrimaryScreen(root.screenNameOf(screen), monitors)
  }

  function groupsOnScreen(screen) {
    return WindowModel.groupsForScreen(root.groups, root.screenNameOf(screen), root.screenIsPrimary(screen))
  }

  function showsNotificationCluster(screen) {
    return WindowModel.showsNotificationCluster(root.screenIsPrimary(screen))
  }

  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    if (!target || !window) return false
    var tw = targetWindow(target)
    if (tw) return tw === window
    var item = target
    while (item) {
      if (item === window || item === window.contentItem) return true
      item = item.parent
    }
    return false
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function showTooltip(target, text) {
    clearTooltip()
    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }
    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text
    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return
    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem && slot.moduleName === id) items.push(slot.activeItem)
    }
    return items
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false
    var currentIndex = -1
    var panels = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (typeof slot.activeItem.open !== "function" || typeof slot.activeItem.close !== "function") continue
      if (slot.activeItem.opened === undefined) continue
      if (slot.activeItem === owner) currentIndex = panels.length
      panels.push(slot)
    }
    if (currentIndex < 0 || panels.length < 2) return false
    var step = direction < 0 ? -1 : 1
    var next = panels[(currentIndex + step + panels.length) % panels.length]
    if (!next || !next.activeItem) return false
    next.activeItem.open()
    return true
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: barWindow
        required property var modelData
        screen: modelData
        visible: !remapGuard.remapping && !root.barHidden
        // Exclusive zone needs 1 or 3 anchors. Auto guessed the thickness
        // onto the wrong edge on Hyprland 0.56; Normal + exclusiveZone pins
        // the bottom inset the snap math reads as reserved[3].
        exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
        exclusiveZone: root.barHidden ? 0 : implicitHeight
        color: root.background
        implicitHeight: root.barSize
        implicitWidth: 0
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-taskbar"
        WlrLayershell.layer: WlrLayer.Top
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        HoverHandler {
          onHoveredChanged: {
            if (root.shell && root.shell.transientCoordinator)
              root.shell.transientCoordinator.setExempt("taskbar", hovered)
          }
          Component.onDestruction: {
            if (root.shell && root.shell.transientCoordinator)
              root.shell.transientCoordinator.setExempt("taskbar", false)
          }
        }

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.chromeEdgeWidth
          z: 2
          color: root.chromeEdge
        }

        ScreenMoveRemap {
          id: remapGuard
          window: barWindow
        }

        RowLayout {
          anchors.fill: parent
          spacing: 0
          LayoutMirroring.enabled: root.rtl
          LayoutMirroring.childrenInherit: true

          StartButton {
            bar: root
            hostWindow: barWindow
            Layout.preferredWidth: 56
            Layout.fillHeight: true
          }

          TaskView {
            bar: root
            hostWindow: barWindow
            Layout.preferredWidth: 44
            Layout.fillHeight: true
          }

          Repeater {
            model: root.groupsOnScreen(barWindow.screen)
            delegate: TaskButton {
              bar: root
              hostWindow: barWindow
              group: modelData
              Layout.preferredWidth: 56
              Layout.fillHeight: true
            }
          }

          Item { Layout.fillWidth: true }

          TrayCluster {
            bar: root
            visible: root.showsNotificationCluster(barWindow.screen)
            Layout.fillHeight: true
          }

          ShowDesktop {
            bar: root
            Layout.preferredWidth: 14
            Layout.fillHeight: true
          }
        }

        PopupWindow {
          id: tooltipWindow
          visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
          color: "transparent"
          implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
          implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

          anchor {
            id: tooltipAnchor
            window: barWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1

            onAnchoring: {
              var target = root.tooltipTarget
              if (!root.targetBelongsToWindow(target, barWindow)) return
              var popupWidth = tooltipWindow.implicitWidth
              var popupHeight = tooltipWindow.implicitHeight
              var localX = target.width / 2 - popupWidth / 2
              var localY = -popupHeight - 6
              var point = barWindow.contentItem.mapFromItem(target, localX, localY)
              tooltipAnchor.rect.x = Math.round(point.x)
              tooltipAnchor.rect.y = Math.round(point.y)
            }
          }

          BorderSurface {
            id: tooltipBubble
            implicitWidth: tooltipLabel.implicitWidth + 20
            implicitHeight: tooltipLabel.implicitHeight + 14
            color: Tokens.chrome.menu
            borderSpec: Border.surfaceSpec("tooltip", "border", root.chromeEdge, root.chromeEdgeWidth)
            radius: Style.cornerRadius

            Text {
              id: tooltipLabel
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.tooltipText
              color: Tokens.text.primary
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }
        }
      }
    }
  }
}
