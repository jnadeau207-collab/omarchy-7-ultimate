import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property var modeProfile: shell ? shell.modeProfileService : null
  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property bool enabled: !!(modeProfile && modeProfile.feature("desktopIcons"))
  readonly property string lister: root.omarchyPath + "/shell/plugins/desktop-icons/list-desktop.py"

  property var items: []
  property string desktopDirectory: ""

  function refresh() {
    if (!root.enabled || listProc.running) return
    listProc.running = true
  }

  function openItem(item) {
    var command = String(item && item.command || "")
    if (command && root.appLibrary && typeof root.appLibrary.launchCommand === "function") {
      Util.execDetached("uwsm-app -- " + root.appLibrary.launchCommand(command))
      return
    }
    var path = String(item && item.path || "")
    if (!path) return
    Util.execArgv(["xdg-open", path])
  }

  Connections {
    target: root.modeProfile
    function onRevisionChanged() { root.refresh() }
  }

  Process {
    id: listProc
    command: ["python3", root.lister]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.desktopDirectory = String(parsed.directory || "")
          root.items = parsed.items || []
        } catch (e) {
          root.items = []
        }
      }
    }
  }

  Timer {
    interval: 4000
    repeat: true
    running: root.enabled
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.enabled
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "omarchy-desktop-icons"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region { item: iconGrid }

      Grid {
        id: iconGrid
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.topMargin: 16
        rows: Math.max(1, Math.floor((panel.height - 32) / 100))
        flow: Grid.TopToBottom
        rowSpacing: 8
        columnSpacing: 8

        Repeater {
          model: root.items
          delegate: Item {
            width: 96
            height: 92
            Column {
              anchors.fill: parent
              spacing: 6
              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48
                height: 48
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 48 * Screen.devicePixelRatio
                sourceSize.height: 48 * Screen.devicePixelRatio
                source: root.appLibrary ? root.appLibrary.iconSource(modelData.icon) : ""
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: modelData.name
                color: Tokens.text.primary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.bodySmall
              }
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onDoubleClicked: root.openItem(modelData)
            }
          }
        }
      }
    }
  }
}
