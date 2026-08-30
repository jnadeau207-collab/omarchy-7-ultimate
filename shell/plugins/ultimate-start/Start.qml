import QtQuick
import QtQuick.Layouts
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
  property bool opened: false

  SemanticProfile {
    id: productProfile
    profileId: "product"
    rtl: Qt.application.layoutDirection === Qt.RightToLeft
  }
  property string filter: ""
  property bool focusSearch: false
  property int cardWidth: 0
  property int cardHeight: 0
  property int barHeight: 0
  property int cardLeftMargin: 0
  readonly property string userName: String(Quickshell.env("USER") || Quickshell.env("LOGNAME") || "")
  readonly property string userInitial: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "?"

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var modeProfile: shell ? shell.modeProfileService : null
  readonly property var windowService: shell ? shell.windowService : null
  readonly property var pins: windowService ? windowService.pins : []
  readonly property bool hideDeveloperTools: !(modeProfile && modeProfile.feature("developerToolsInStart"))
  readonly property var entries: appLibrary ? appLibrary.visibleEntries(root.filter, root.hideDeveloperTools) : []
  readonly property var places: [
    { id: "files", name: "Files", desktopId: "org.omarchy.Files" },
    { id: "pictures", name: "Pictures", command: "xdg-open \"$(xdg-user-dir PICTURES)\"" },
    { id: "computer", name: "Computer", desktopId: "org.omarchy.Files" },
    { id: "settings", name: "Settings", desktopId: "org.omarchy.Settings" },
    { id: "agent-center", name: "Agent Center", desktopId: "org.omarchy.AgentCenter" }
  ]

  property var focusedWhenOpened: null
  property bool raiseUnderCursorOnClose: false
  property bool launchingFromStart: false

  function applyStartChrome(raw) {
    var parsed = JSON.parse(String(raw || "{}"))
    var width = Number(parsed.cardWidth)
    var height = Number(parsed.cardHeight)
    var bar = Number(parsed.barHeight)
    var left = Number(parsed.cardLeftMargin)
    if (!(width > 0) || !(height > 0) || !(bar > 0) || !(left >= 0))
      throw "start-chrome.json is incomplete"
    root.cardWidth = width
    root.cardHeight = height
    root.barHeight = bar
    root.cardLeftMargin = left
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.focusSearch = payload.focusSearch === true
    root.filter = ""
    root.focusedWhenOpened = ToplevelManager.activeToplevel
    root.raiseUnderCursorOnClose = false
    root.launchingFromStart = false
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.request(root)
    root.opened = true
    if (appLibrary) appLibrary.refreshIcons()
  }

  function close() {
    var raise = root.raiseUnderCursorOnClose && !root.launchingFromStart
    root.raiseUnderCursorOnClose = false
    root.launchingFromStart = false
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.release(root)
    if (!root.opened) {
      root.filter = ""
      return
    }
    root.opened = false
    root.filter = ""
    root.focusedWhenOpened = null
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-start")
    if (raise && root.shell && root.shell.windowService
        && typeof root.shell.windowService.activateAtCursorSoon === "function")
      root.shell.windowService.activateAtCursorSoon()
  }

  function launchEntry(entry) {
    if (!entry || !appLibrary) return
    root.launchingFromStart = true
    root.raiseUnderCursorOnClose = false
    appLibrary.launch(entry.id, appLibrary.entryName(entry))
    root.close()
  }

  function launchPlace(place) {
    if (!place) return
    root.launchingFromStart = true
    root.raiseUnderCursorOnClose = false
    if (place.desktopId && root.appLibrary)
      root.appLibrary.launch(place.desktopId, place.name)
    else if (place.command)
      Util.execDetached(place.command)
    root.close()
  }

  FileView {
    path: root.omarchyPath + "/default/ultimate/start-chrome.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyStartChrome(text())
    onFileChanged: reload()
  }

  Connections {
    target: ToplevelManager
    enabled: root.opened
    function onActiveToplevelChanged() {
      var next = ToplevelManager.activeToplevel
      if (!next)
        return
      if (!root.launchingFromStart)
        root.raiseUnderCursorOnClose = true
      root.close()
    }
  }

  Loader {
    active: root.opened
    sourceComponent: PanelWindow {
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    anchors.left: true
    anchors.bottom: true
    margins.left: root.cardLeftMargin
    margins.bottom: root.barHeight
    WlrLayershell.namespace: "omarchy-start"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.fill: parent
      clip: true
      color: Tokens.surface.base
      radius: Tokens.radius.large
      border.color: Tokens.chrome.edge
      border.width: 1
      LayoutMirroring.enabled: productProfile.rtl
      LayoutMirroring.childrenInherit: true

      HoverHandler {
        onHoveredChanged: {
          if (root.shell && root.shell.transientCoordinator)
            root.shell.transientCoordinator.setExempt("start", hovered)
        }
        Component.onDestruction: {
          if (root.shell && root.shell.transientCoordinator)
            root.shell.transientCoordinator.setExempt("start", false)
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 0

        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredWidth: 440
          spacing: 12

          SearchBox {
            id: searchField
            Layout.fillWidth: true
            semanticProfile: productProfile
            onTextChanged: root.filter = text
            Component.onCompleted: searchField.forceActiveFocus()
            Keys.onReturnPressed: {
              if (root.entries.length > 0) root.launchEntry(root.entries[0])
            }
            Keys.onEscapePressed: root.close()
          }

          Text {
            visible: root.pins.length > 0 && root.filter.length === 0
            text: "Pinned"
            color: Tokens.text.secondary
            font.pixelSize: Style.font.bodySmall
            font.family: Tokens.typography.family
          }

          Flow {
            visible: root.filter.length === 0 && root.pins.length > 0
            Layout.fillWidth: true
            spacing: 12
            Repeater {
              model: root.pins
              delegate: Item {
                width: 88
                height: 84
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
                    source: root.appLibrary ? root.appLibrary.iconSource(modelData.icon || modelData.desktopId) : ""
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData.name || modelData.desktopId
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.launchingFromStart = true
                    if (root.appLibrary) root.appLibrary.launch(modelData.desktopId || modelData.id, modelData.name)
                    root.close()
                  }
                }
              }
            }
          }

          Text {
            visible: root.filter.length === 0
            text: "All programs"
            color: Tokens.text.secondary
            font.pixelSize: Style.font.bodySmall
            font.family: Tokens.typography.family
          }

          ListView {
            visible: root.entries.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.entries
            delegate: Item {
              width: ListView.view.width
              height: Semantics.minimumTarget(productProfile)
              clip: true
              RowLayout {
                anchors.fill: parent
                spacing: 10
                Image {
                  Layout.preferredWidth: 32
                  Layout.preferredHeight: 32
                  Layout.alignment: Qt.AlignVCenter
                  width: 32
                  height: 32
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  sourceSize.width: 32 * Screen.devicePixelRatio
                  sourceSize.height: 32 * Screen.devicePixelRatio
                  source: root.appLibrary ? root.appLibrary.iconSource(modelData.icon) : ""
                }
                Text {
                  textFormat: Text.PlainText
                  Layout.fillWidth: true
                  text: root.appLibrary ? root.appLibrary.entryName(modelData) : ""
                  color: Tokens.text.primary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchEntry(modelData)
              }
            }
          }

          EmptyState {
            visible: root.entries.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            semanticProfile: productProfile
            title: root.filter.length > 0 ? "No matching apps" : "Search for apps"
            message: root.filter.length > 0 ? "Try a different name." : "Pinned programs stay on the left. Files, Pictures, Computer, Settings, and Agent Center stay on the right. Terminal and Vim stay available from search."
          }
        }

        Rectangle {
          Layout.fillHeight: true
          Layout.leftMargin: 12
          Layout.rightMargin: 12
          implicitWidth: 1
          color: Tokens.chrome.edge
        }

        ColumnLayout {
          Layout.preferredWidth: 236
          Layout.fillHeight: true
          spacing: 10

          RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
              implicitWidth: 44
              implicitHeight: 44
              radius: 22
              color: Tokens.surface.raised
              border.color: Tokens.chrome.edge
              border.width: 1
              Text {
                anchors.centerIn: parent
                text: root.userInitial
                color: Tokens.text.primary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: root.userName.length > 0 ? root.userName : "Local account"
              color: Tokens.text.primary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }
          }

          Repeater {
            model: root.places
            delegate: Item {
              Layout.fillWidth: true
              implicitHeight: Semantics.minimumTarget(productProfile)
              Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.small
                color: placeMouse.containsMouse ? Tokens.chrome.hover : "transparent"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                textFormat: Text.PlainText
                text: modelData.name
                color: Tokens.text.primary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              MouseArea {
                id: placeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchPlace(modelData)
              }
            }
          }

          Item { Layout.fillHeight: true }

          Button {
            semanticProfile: productProfile
            Layout.fillWidth: true
            text: modeProfile && modeProfile.mode === "desktop" ? "Power User Mode" : "Desktop Mode"
            onClicked: {
              if (!modeProfile) return
              modeProfile.setMode(modeProfile.mode === "desktop" ? "power-user" : "desktop")
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IconButton {
              iconText: "\u26BF"
              tooltipText: "Lock"
              semanticProfile: productProfile
              onClicked: { Util.execDetached("omarchy-system-lock"); root.close() }
            }
            IconButton {
              iconText: "\u21BB"
              tooltipText: "Restart"
              semanticProfile: productProfile
              onClicked: { Util.execDetached("omarchy-system-reboot"); root.close() }
            }
            IconButton {
              iconText: "\u23FB"
              tooltipText: "Shut down"
              semanticProfile: productProfile
              danger: true
              onClicked: { Util.execDetached("omarchy-system-shutdown"); root.close() }
            }
          }
        }
      }
    }

      PanelKeyCatcher {
        anchors.fill: parent
        blocked: searchField.activeFocus
        onCloseRequested: root.close()
      }
    }
  }
}
