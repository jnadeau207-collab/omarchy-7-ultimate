import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../../services/WindowPreview.js" as WindowPreview

Item {
  id: root

  property var bar: null
  property var hostWindow: null
  property var group: ({})
  property var windowService: bar && bar.shell ? bar.shell.windowService : null
  property var appLibrary: bar && bar.shell ? bar.shell.appLibrary : null
  property var notificationService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null

  readonly property var windows: group && group.windows ? group.windows : []
  readonly property var previewRows: WindowPreview.previewRows(windows)
  readonly property var jumpList: appLibrary ? appLibrary.jumpListFor(group && group.desktopId ? group.desktopId : "") : []
  readonly property int badgeCount: {
    var _rev = notificationService ? notificationService.centerRevision : 0
    return notificationService ? notificationService.badgeCountForApp(group.desktopId, group.name) : 0
  }
  readonly property bool running: windows.length > 0
  readonly property bool active: {
    if (!windowService) return false
    for (var i = 0; i < windows.length; i++) {
      if (windowService.isActive(windows[i].address)) return true
    }
    return false
  }
  readonly property string label: group && group.name ? group.name : ""
  readonly property string iconName: group && (group.icon || group.desktopId) ? (group.icon || group.desktopId) : ""

  implicitWidth: 56
  implicitHeight: parent ? parent.height : 48

  function activate() {
    var startWasOpen = !!(root.bar && root.bar.shell && typeof root.bar.shell.isPluginOpen === "function"
      && root.bar.shell.isPluginOpen("omarchy.ultimate-start"))
    if (root.bar && root.bar.shell && root.bar.shell.transientCoordinator)
      root.bar.shell.transientCoordinator.dismiss()
    if (!root.running) {
      if (root.appLibrary && group && group.desktopId)
        root.appLibrary.launch(group.desktopId, group.name)
      return
    }
    if (startWasOpen) {
      if (windows.length === 1)
        windowService.activate(windows[0].address)
      else {
        var keep = 0
        var j
        for (j = 0; j < windows.length; j++) {
          if (windowService.isActive(windows[j].address)) {
            keep = j
            break
          }
        }
        windowService.activate(windows[keep].address)
      }
      return
    }
    if (windows.length === 1) {
      windowService.toggleFromTaskbar(windows[0].address)
      return
    }
    var activeIndex = -1
    var i
    for (i = 0; i < windows.length; i++) {
      if (windowService.isActive(windows[i].address)) {
        activeIndex = i
        break
      }
    }
    if (activeIndex >= 0)
      windowService.activate(windows[(activeIndex + 1) % windows.length].address)
    else
      windowService.activate(windows[0].address)
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    radius: Tokens.radius.medium
    color: mouse.pressed ? bar.chromePressed
      : mouse.containsMouse ? bar.chromeHover
      : root.active ? bar.chromeActive
      : root.running ? bar.chromeHover
      : "transparent"
    border.color: root.active ? bar.chromeGlow : (root.running ? Tokens.border.subtle : "transparent")
    border.width: root.running || root.active ? 1 : 0

    Rectangle {
      visible: root.running
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 6
      anchors.rightMargin: 6
      anchors.bottomMargin: 3
      height: root.active ? 3 : 2
      radius: 1
      color: bar.chromeGlow
    }

    Image {
      id: icon
      anchors.centerIn: parent
      width: 36
      height: 36
      fillMode: Image.PreserveAspectFit
      sourceSize.width: 36 * Screen.devicePixelRatio
      sourceSize.height: 36 * Screen.devicePixelRatio
      source: root.appLibrary ? root.appLibrary.iconSource(root.iconName) : ""
      visible: status === Image.Ready
    }

    Text {
      textFormat: Text.PlainText
      visible: icon.status !== Image.Ready
      anchors.centerIn: parent
      text: root.label ? root.label.charAt(0).toUpperCase() : "?"
      color: Tokens.text.primary
      font.pixelSize: Style.font.body
      font.family: "sans-serif"
    }

    Badge {
      visible: root.badgeCount > 0
      count: root.badgeCount
      tone: "danger"
      anchors.right: parent.right
      anchors.top: parent.top
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onPressed: {
      peekTimer.stop()
      peek.visible = false
    }
    onClicked: function(event) {
      peekTimer.stop()
      peek.visible = false
      if (event.button === Qt.RightButton) {
        menu.visible = !menu.visible
        return
      }
      if (event.modifiers & Qt.ShiftModifier) {
        if (root.appLibrary && group && group.desktopId)
          root.appLibrary.launch(group.desktopId, group.name)
        return
      }
      root.activate()
    }
    onContainsMouseChanged: {
      if (mouse.containsMouse && root.running && !menu.visible) peekTimer.restart()
      else {
        peekTimer.stop()
        peek.visible = false
      }
    }
  }

  Timer {
    id: peekTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (mouse.containsMouse && root.running && !menu.visible)
        peek.visible = true
    }
  }

  PopupWindow {
    id: peek
    visible: false
    color: "transparent"
    implicitWidth: 280
    implicitHeight: peekCol.implicitHeight + 16
    anchor.window: root.hostWindow
    anchor.item: root
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right
    anchor.rect.y: -8

    onVisibleChanged: {
      if (!visible || !windowService) return
      var rows = root.previewRows
      var i
      for (i = 0; i < rows.length; i++) {
        if (rows[i].capturable) windowService._capturePreview(rows[i].address)
      }
    }

    Rectangle {
      anchors.fill: parent
      color: bar.chromeMenu
      radius: Tokens.radius.medium
      border.color: Tokens.border.subtle
      border.width: 1

      Column {
        id: peekCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 6

        Text {
          textFormat: Text.PlainText
          width: peekCol.width
          text: root.label
          color: Tokens.text.primary
          font.pixelSize: Style.font.body
          font.family: "sans-serif"
          elide: Text.ElideRight
        }

        Repeater {
          model: previewRows
          delegate: Item {
            width: peekCol.width
            height: peekThumb.height + 44 + (peekThumb.visible ? 4 : 0)

            Rectangle {
              anchors.fill: parent
              radius: Tokens.radius.small
              color: rowMouse.containsMouse ? bar.chromeHover : "transparent"
            }

            Image {
              id: peekThumb
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: status === Image.Ready ? 132 : 0
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
              source: {
                var _rev = windowService ? windowService.previewRevision : 0
                return (windowService && modelData.capturable) ? windowService._previewPath(modelData.address) : ""
              }
              visible: status === Image.Ready
            }

            Image {
              id: peekIcon
              anchors.top: peekThumb.bottom
              anchors.topMargin: peekThumb.visible ? 4 : 8
              anchors.left: parent.left
              anchors.leftMargin: 6
              width: 28
              height: 28
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 28 * Screen.devicePixelRatio
              sourceSize.height: 28 * Screen.devicePixelRatio
              source: root.appLibrary ? root.appLibrary.iconSource(root.iconName) : ""
            }

            Text {
              textFormat: Text.PlainText
              anchors.top: peekThumb.bottom
              anchors.topMargin: peekThumb.visible ? 4 : 4
              anchors.left: peekIcon.right
              anchors.leftMargin: 6
              anchors.right: peekClose.left
              anchors.rightMargin: 4
              text: modelData.title + (modelData.minimized ? " (minimized)" : "")
              color: Tokens.text.primary
              font.pixelSize: Style.font.bodySmall
              font.family: "sans-serif"
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 4
              anchors.left: peekIcon.right
              anchors.leftMargin: 6
              anchors.right: peekClose.left
              text: modelData.workspace ? ("Desktop " + modelData.workspace) : ""
              color: Tokens.text.secondary
              font.pixelSize: Style.font.bodySmall
              font.family: "sans-serif"
              elide: Text.ElideRight
            }

            Text {
              id: peekClose
              anchors.top: peekThumb.bottom
              anchors.topMargin: peekThumb.visible ? 10 : 8
              anchors.right: parent.right
              anchors.rightMargin: 6
              text: "×"
              color: Tokens.text.primary
              font.pixelSize: Style.font.body
              font.family: "sans-serif"
              visible: windowService ? true : false
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (windowService) windowService.activate(modelData.address)
                peek.visible = false
              }
            }

            MouseArea {
              anchors.top: peekThumb.bottom
              anchors.right: parent.right
              width: 22
              height: 44
              z: 2
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (windowService) windowService.close(modelData.address)
                peek.visible = false
              }
            }
          }
        }
      }
    }
  }

  PopupWindow {
    id: menu
    visible: false
    color: "transparent"
    implicitWidth: 220
    implicitHeight: col.implicitHeight + 12
    anchor.window: root.hostWindow
    anchor.item: root
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Top | Edges.Right
    anchor.rect.y: -4

    Rectangle {
      anchors.fill: parent
      color: bar.chromeMenu
      radius: Tokens.radius.medium
      border.color: Tokens.border.subtle
      border.width: 1

      Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        spacing: 2

        Repeater {
          model: root.jumpList
          delegate: Item {
            width: col.width
            height: 28

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.right: parent.right
              anchors.rightMargin: 8
              text: modelData.name
              color: Tokens.text.primary
              font.pixelSize: Style.font.body
              font.family: "sans-serif"
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                if (root.appLibrary)
                  root.appLibrary.launchAction(group.desktopId, modelData, group.name)
                menu.visible = false
              }
            }
          }
        }

        Repeater {
          model: [
            { label: (group && group.pinned) ? "Unpin from taskbar" : "Pin to taskbar", action: "pin" },
            { label: (windows.length > 1) ? "Close group" : "Close window", action: "close" }
          ]
          delegate: Item {
            width: col.width
            height: 28
            visible: modelData.action !== "close" || root.running

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 8
              text: modelData.label
              color: Tokens.text.primary
              font.pixelSize: Style.font.body
              font.family: "sans-serif"
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                if (modelData.action === "pin" && root.bar && typeof root.bar.togglePin === "function")
                  root.bar.togglePin(group)
                if (modelData.action === "close") {
                  for (var i = 0; i < windows.length; i++) windowService.close(windows[i].address)
                }
                menu.visible = false
              }
            }
          }
        }
      }
    }
  }
}
