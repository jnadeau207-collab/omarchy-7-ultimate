import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../../services/WindowPreview.js" as WindowPreview

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string pendingActivate: ""
  property string mode: "switcher"
  property string ownerScreenName: ""
  property var ownerScreen: null
  property int viewDesktop: 1
  onViewDesktopChanged: if (root.opened && root.mode === "taskView") root.captureViewPreviews()

  readonly property var windowService: shell ? shell.windowService : null
  readonly property var cycleList: windowService ? windowService.cycleList : []
  readonly property int cycleIndex: windowService ? windowService.cycleIndex : 0
  readonly property var desktopIds: windowService ? windowService.desktopIds : []
  readonly property var viewPreviewRows: WindowPreview.previewRows(root.viewWindowsFor(root.viewDesktop))

  function captureViewPreviews() {
    if (!windowService) return
    var rows = root.viewPreviewRows
    var i
    for (i = 0; i < rows.length; i++) {
      if (rows[i].capturable) windowService._capturePreview(rows[i].address)
    }
  }

  Timer {
    id: activateAfterHide
    interval: 48
    repeat: false
    onTriggered: {
      var target = root.pendingActivate
      root.pendingActivate = ""
      if (target && windowService && typeof windowService.activateFromSwitcher === "function")
        windowService.activateFromSwitcher(target)
    }
  }

  function screenByName(name) {
    if (!name) return null
    var i
    for (i = 0; i < Quickshell.screens.length; i++) {
      if (String(Quickshell.screens[i].name || "") === String(name)) return Quickshell.screens[i]
    }
    return null
  }

  function open(payloadJson) {
    root.mode = "switcher"
    root.ownerScreenName = ""
    root.ownerScreen = null
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && payload.mode) root.mode = String(payload.mode)
      if (payload && payload.screen) {
        root.ownerScreenName = String(payload.screen)
        root.ownerScreen = root.screenByName(root.ownerScreenName)
      }
    } catch (e) {
    }
    if (windowService && windowService.activeDesktopId)
      root.viewDesktop = windowService.activeDesktopId
    root.opened = true
    if (root.mode === "taskView") root.captureViewPreviews()
  }

  function close() {
    root.opened = false
    if (root.pendingActivate !== "")
      return
    activateAfterHide.stop()
    if (windowService && typeof windowService.cancelCycle === "function")
      windowService.cancelCycle()
  }

  function pick(address) {
    root.pendingActivate = String(address || "")
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-task-switcher")
    activateAfterHide.restart()
  }

  function viewWindowsFor(id) {
    if (!windowService) return []
    var all = windowService.windows || []
    var out = []
    var i
    for (i = 0; i < all.length; i++) {
      if (all[i] && Number(all[i].workspaceId) === Number(id)) out.push(all[i])
    }
    return out
  }

  Loader {
    active: root.opened
    sourceComponent: PanelWindow {
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    screen: root.ownerScreen
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-task-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      visible: root.mode === "taskView"
      onClicked: {
        root.close()
        if (root.shell) root.shell.hide("omarchy.ultimate-task-switcher")
      }
    }

    Rectangle {
      visible: root.mode !== "taskView"
      anchors.centerIn: parent
      width: Math.min(parent.width - 32, 120 * Math.max(1, cycleList.length) + 40)
      height: 160
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      Row {
        anchors.centerIn: parent
        spacing: 8
        Repeater {
          model: cycleList
          delegate: Rectangle {
            width: 120
            height: 120
            radius: Tokens.radius.medium
            color: index === cycleIndex ? Util.alpha(Tokens.accent.primary, 0.28) : Tokens.surface.raised
            border.color: index === cycleIndex ? Tokens.accent.primary : Tokens.border.subtle
            border.width: 1

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - 8
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              text: {
                var title = windowService ? windowService.windowTitle(modelData) : String(modelData)
                if (windowService && typeof windowService.isMinimized === "function" && windowService.isMinimized(modelData))
                  return title + "\nminimized"
                return title
              }
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: Tokens.typography.family
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pick(String(modelData || ""))
            }
          }
        }
      }
    }

    Rectangle {
      visible: root.mode === "taskView"
      anchors.centerIn: parent
      width: Math.min(parent.width - 64, 1100)
      height: Math.min(parent.height - 80, 640)
      color: Tokens.surface.glass
      radius: Tokens.radius.large
      border.color: Tokens.border.subtle
      border.width: 1

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Text {
          text: "Task View"
          color: Tokens.text.primary
          font.pixelSize: Style.font.title
          font.family: Tokens.typography.family
          font.bold: true
        }

        Row {
          spacing: 8
          Repeater {
            model: desktopIds
            delegate: Rectangle {
              width: 88
              height: 48
              radius: Tokens.radius.medium
              color: Number(modelData) === Number(root.viewDesktop) ? Util.alpha(Tokens.accent.primary, 0.28) : Tokens.surface.raised
              border.color: Number(modelData) === Number(root.viewDesktop) ? Tokens.accent.primary : Tokens.border.subtle
              border.width: 1
              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Desktop " + modelData
                color: Tokens.text.primary
                font.pixelSize: Style.font.bodySmall
                font.family: Tokens.typography.family
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.viewDesktop = Number(modelData)
                  if (windowService) windowService.switchToDesktop(modelData)
                }
              }
            }
          }
          Rectangle {
            width: 88
            height: 48
            radius: Tokens.radius.medium
            color: Tokens.surface.raised
            border.color: Tokens.border.subtle
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "New"
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: Tokens.typography.family
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!windowService) return
                windowService.createDesktop()
                root.viewDesktop = windowService.activeDesktopId
              }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: 10
          Repeater {
            model: root.viewPreviewRows
            delegate: Rectangle {
              width: 240
              height: 188
              radius: Tokens.radius.medium
              color: Tokens.surface.raised
              border.color: Tokens.border.subtle
              border.width: 1

              Image {
                id: viewThumb
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 120
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                source: {
                  var _rev = windowService ? windowService.previewRevision : 0
                  return (windowService && modelData.capturable) ? windowService._previewPath(modelData.address) : ""
                }
                visible: status === Image.Ready
              }

              Rectangle {
                visible: !viewThumb.visible
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 120
                radius: Tokens.radius.small
                color: Tokens.surface.base
                Text {
                  anchors.centerIn: parent
                  text: modelData.minimized ? "Minimized" : "No preview"
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: modelData.title + (modelData.minimized ? " (minimized)" : "")
                color: Tokens.text.primary
                font.pixelSize: Style.font.body
                font.family: Tokens.typography.family
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pick(String(modelData.address || ""))
              }
            }
          }
        }
      }
    }
    }
  }
}
