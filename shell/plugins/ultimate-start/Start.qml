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

  property bool summonedRtl: false
  property bool summonedPseudoLocale: false
  property string summonedLocale: "en-US"
  SemanticProfile {
    id: productProfile
    profileId: "product"
    rtl: root.summonedRtl || (root.shell && root.shell.summonedRtl) || Qt.application.layoutDirection === Qt.RightToLeft
    pseudoLocale: root.summonedPseudoLocale || (root.shell && root.shell.summonedPseudoLocale) || root.summonedLocale === "pseudo"
    locale: root.summonedLocale
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
  readonly property var programRows: appLibrary ? appLibrary.programRows(root.filter, root.hideDeveloperTools) : []
  readonly property var recentApps: {
    var exclude = []
    var i
    for (i = 0; i < root.pins.length; i++)
      exclude.push(root.pins[i].desktopId || root.pins[i].id)
    return appLibrary ? appLibrary.recentEntries(6, exclude) : []
  }
  readonly property var places: [
    { id: "files", name: "Files", desktopId: "org.omarchy.Files", icon: "system-file-manager" },
    { id: "pictures", name: "Pictures", desktopId: "org.omarchy.Files", icon: "folder-pictures", actionId: "Pictures" },
    { id: "computer", name: "Computer", desktopId: "org.omarchy.Files", icon: "computer", actionId: "ThisPC" },
    { id: "settings", name: "Settings", desktopId: "org.omarchy.Settings", icon: "org.omarchy.Settings" },
    { id: "agent-center", name: "Agent Center", desktopId: "org.omarchy.AgentCenter", icon: "org.omarchy.AgentCenter" }
  ]

  property var focusedWhenOpened: null
  property string focusReturn: ""
  property string ownerScreenName: ""
  property var ownerScreen: null
  property bool raiseUnderCursorOnClose: false
  property bool restoreFocusOnClose: false
  property bool launchingFromStart: false
  property var pinMenuAnchor: null
  property var pinMenuItem: null
  property bool pinMenuOpen: false
  property bool morePowerOpen: false

  function screenByName(name) {
    if (!name) return null
    var i
    for (i = 0; i < Quickshell.screens.length; i++) {
      if (String(Quickshell.screens[i].name || "") === String(name)) return Quickshell.screens[i]
    }
    return null
  }

  function currentActiveAddress() {
    if (!windowService) return ""
    var list = windowService.windows || []
    var i
    for (i = 0; i < list.length; i++) {
      if (list[i] && list[i].address && typeof windowService.isActive === "function"
          && windowService.isActive(list[i].address))
        return list[i].address
    }
    return ""
  }

  function writeOwnerScreen(name) {
    ownerFile.setText(JSON.stringify({ screen: String(name || "") }) + "\n")
  }

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
    var screenName = payload.screen ? String(payload.screen) : ""
    if (root.opened && (root.ownerScreenName === screenName || screenName === "")) {
      root.restoreFocusOnClose = true
      root.close()
      return
    }
    root.focusSearch = payload.focusSearch === true
    root.summonedRtl = payload.rtl === true
    root.summonedPseudoLocale = payload.pseudoLocale === true
    if (root.shell) {
      root.shell.summonedRtl = root.summonedRtl
      root.shell.summonedPseudoLocale = root.summonedPseudoLocale
    }
    root.summonedLocale = payload.locale ? String(payload.locale) : (root.summonedPseudoLocale ? "pseudo" : "en-US")
    root.filter = ""
    if (!root.opened) {
      root.focusedWhenOpened = ToplevelManager.activeToplevel
      root.focusReturn = root.currentActiveAddress()
    }
    root.raiseUnderCursorOnClose = false
    root.launchingFromStart = false
    root.ownerScreenName = screenName
    root.ownerScreen = root.screenByName(screenName)
    if (!root.ownerScreen && Quickshell.screens.length > 0) {
      root.ownerScreen = Quickshell.screens[0]
      if (!root.ownerScreenName)
        root.ownerScreenName = String(root.ownerScreen.name || "")
    }
    root.writeOwnerScreen(root.ownerScreenName)
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.request(root)
    root.opened = true
    if (appLibrary) appLibrary.refreshIcons()
  }

  function close() {
    var raise = root.raiseUnderCursorOnClose && !root.launchingFromStart
    var restore = root.restoreFocusOnClose && !raise && !root.launchingFromStart ? root.focusReturn : ""
    root.raiseUnderCursorOnClose = false
    root.restoreFocusOnClose = false
    root.launchingFromStart = false
    if (root.shell && root.shell.transientCoordinator)
      root.shell.transientCoordinator.release(root)
    if (!root.opened) {
      root.filter = ""
      return
    }
    root.opened = false
    root.filter = ""
    root.summonedRtl = false
    root.summonedPseudoLocale = false
    root.summonedLocale = "en-US"
    root.focusedWhenOpened = null
    root.focusReturn = ""
    root.ownerScreenName = ""
    root.ownerScreen = null
    root.pinMenuOpen = false
    root.pinMenuAnchor = null
    root.pinMenuItem = null
    root.morePowerOpen = false
    root.writeOwnerScreen("")
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy.ultimate-start")
    if (raise && root.shell && root.shell.windowService
        && typeof root.shell.windowService.activateAtCursorSoon === "function")
      root.shell.windowService.activateAtCursorSoon()
    else if (restore && root.shell && root.shell.windowService
        && typeof root.shell.windowService.activate === "function")
      root.shell.windowService.activate(restore)
  }

  function launchEntry(entry) {
    if (!entry || !appLibrary) return
    if (entry.kind === "destination" || entry.actionId || entry.command) {
      root.launchPlace({
        name: appLibrary.entryName(entry) || entry.name,
        desktopId: entry.desktopId || entry.id,
        actionId: entry.actionId || "",
        command: entry.command || ""
      })
      return
    }
    root.launchingFromStart = true
    root.raiseUnderCursorOnClose = false
    appLibrary.launch(entry.id, appLibrary.entryName(entry))
    root.close()
  }

  function desktopIdOf(item) {
    var entry = item && item.entry ? item.entry : item
    return String((entry && (entry.desktopId || entry.id)) || "")
  }

  function isPinnedId(desktopId) {
    var want = String(desktopId || "").toLowerCase()
    if (want.slice(-8) === ".desktop") want = want.slice(0, -8)
    if (!want) return false
    var i
    for (i = 0; i < root.pins.length; i++) {
      var id = String((root.pins[i] && (root.pins[i].desktopId || root.pins[i].id)) || "").toLowerCase()
      if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
      if (id === want) return true
    }
    return false
  }

  function pinPayload(item) {
    var entry = item && item.entry ? item.entry : item
    var id = root.desktopIdOf(entry)
    var name = ""
    if (root.appLibrary && entry) name = root.appLibrary.entryName(entry)
    if (!name) name = String((entry && entry.name) || id)
    return {
      id: id,
      desktopId: id,
      name: name,
      icon: String((entry && (entry.icon || entry.desktopId || entry.id)) || "")
    }
  }

  readonly property var pinMenuJumpList: {
    if (!root.appLibrary || !root.pinMenuItem) return []
    return root.appLibrary.jumpListFor(root.desktopIdOf(root.pinMenuItem))
  }

  function showPinMenu(anchor, item) {
    root.morePowerOpen = false
    root.pinMenuAnchor = anchor
    root.pinMenuItem = item
    root.pinMenuOpen = true
  }

  function toggleMorePower() {
    root.pinMenuOpen = false
    root.pinMenuAnchor = null
    root.pinMenuItem = null
    root.morePowerOpen = !root.morePowerOpen
  }

  function togglePinned(item) {
    if (!windowService || !item) return
    var payload = root.pinPayload(item)
    if (!payload.desktopId) return
    if (root.isPinnedId(payload.desktopId)) windowService.unpin(payload.desktopId)
    else windowService.pin(payload)
  }

  function placeAction(place) {
    if (!place || !place.actionId || !root.appLibrary) return null
    var rows = root.appLibrary.jumpListFor(place.desktopId)
    var i
    for (i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].id === place.actionId) return rows[i]
    }
    return null
  }

  function launchPlace(place) {
    if (!place) return
    if (place.actionId) {
      var action = root.placeAction(place)
      if (action) {
        root.launchingFromStart = true
        root.raiseUnderCursorOnClose = false
        root.appLibrary.launchAction(place.desktopId, action, place.name)
        root.close()
        return
      }
    }
    if (place.command && root.appLibrary) {
      root.launchingFromStart = true
      root.raiseUnderCursorOnClose = false
      root.appLibrary.launchAction(place.desktopId, {
        command: place.command,
        kind: "desktop-action",
        name: place.name
      }, place.name)
      root.close()
      return
    }
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

  FileView {
    id: ownerFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/ultimate/start-owner.json"
    printErrors: false
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
    screen: root.ownerScreen
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
      id: startCard
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
            semanticPlaceholderText: "Search programs"
            onTextChanged: root.filter = text
            Component.onCompleted: searchField.forceActiveFocus()
            Keys.onReturnPressed: {
              if (root.entries.length > 0) root.launchEntry(root.entries[0])
            }
            Keys.onEscapePressed: root.close()
          }

          Text {
            visible: root.pins.length > 0 && root.filter.length === 0
            text: productProfile.text("Pinned")
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
                id: pinTile
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
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      root.showPinMenu(pinTile, modelData)
                      return
                    }
                    root.launchingFromStart = true
                    if (root.appLibrary) root.appLibrary.launch(modelData.desktopId || modelData.id, modelData.name)
                    root.close()
                  }
                }
              }
            }
          }

          Text {
            visible: root.recentApps.length > 0 && root.filter.length === 0
            text: productProfile.text("Recent")
            color: Tokens.text.secondary
            font.pixelSize: Style.font.bodySmall
            font.family: Tokens.typography.family
          }

          Flow {
            visible: root.recentApps.length > 0 && root.filter.length === 0
            Layout.fillWidth: true
            spacing: 12
            Repeater {
              model: root.recentApps
              delegate: Item {
                id: recentTile
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
                    source: root.appLibrary ? root.appLibrary.iconSource(modelData.icon || modelData.id) : ""
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.appLibrary ? root.appLibrary.entryName(modelData) : ""
                    color: Tokens.text.primary
                    font.family: Tokens.typography.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      root.showPinMenu(recentTile, modelData)
                      return
                    }
                    root.launchEntry(modelData)
                  }
                }
              }
            }
          }

          Text {
            visible: root.filter.length === 0
            text: productProfile.text("All programs")
            color: Tokens.text.secondary
            font.pixelSize: Style.font.bodySmall
            font.family: Tokens.typography.family
          }

          ListView {
            visible: root.programRows.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.programRows
            delegate: Item {
              id: programRow
              width: ListView.view.width
              height: modelData.kind === "letter" ? 22 : Semantics.minimumTarget(productProfile)
              clip: true
              Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.small
                visible: modelData.kind === "app"
                color: programMouse.containsMouse ? Tokens.chrome.hover : "transparent"
              }
              Text {
                visible: modelData.kind === "letter"
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                text: modelData.letter
                color: Tokens.text.secondary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              RowLayout {
                visible: modelData.kind === "app"
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
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
                  source: root.appLibrary && modelData.entry ? root.appLibrary.iconSource(modelData.entry.icon) : ""
                }
                Text {
                  textFormat: Text.PlainText
                  Layout.fillWidth: true
                  text: root.appLibrary && modelData.entry ? root.appLibrary.entryName(modelData.entry) : ""
                  color: Tokens.text.primary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }
              MouseArea {
                id: programMouse
                anchors.fill: parent
                enabled: modelData.kind === "app"
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  if (!modelData.entry) return
                  if (mouse.button === Qt.RightButton) {
                    root.showPinMenu(programRow, modelData.entry)
                    return
                  }
                  root.launchEntry(modelData.entry)
                }
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
              text: root.userName.length > 0 ? root.userName : productProfile.text("Local account")
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
              id: placeRow
              Layout.fillWidth: true
              implicitHeight: Semantics.minimumTarget(productProfile)
              Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.small
                color: placeMouse.containsMouse ? Tokens.chrome.hover : "transparent"
              }
              Image {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                width: 20
                height: 20
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 20 * Screen.devicePixelRatio
                sourceSize.height: 20 * Screen.devicePixelRatio
                source: root.appLibrary ? root.appLibrary.iconSource(modelData.icon) : ""
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 36
                textFormat: Text.PlainText
                text: productProfile.text(modelData.name)
                color: Tokens.text.primary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              MouseArea {
                id: placeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    if (modelData.desktopId) root.showPinMenu(placeRow, modelData)
                    return
                  }
                  root.launchPlace(modelData)
                }
              }
            }
          }

          Item { Layout.fillHeight: true }

          Item {
            Layout.fillWidth: true
            implicitHeight: 28
            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              text: productProfile.text(modeProfile && modeProfile.mode === "desktop" ? "Power User Mode" : "Desktop Mode")
              color: modeMouse.containsMouse ? Tokens.text.primary : Tokens.text.secondary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: modeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!modeProfile) return
                modeProfile.setMode(modeProfile.mode === "desktop" ? "power-user" : "desktop")
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Button {
              semanticProfile: productProfile
              Layout.fillWidth: true
              text: "Shut down"
              onClicked: {
                Util.execDetached("omarchy-system-shutdown")
                root.close()
              }
            }
            IconButton {
              id: powerMore
              iconText: "\u25B2"
              tooltipText: root.morePowerOpen ? "" : "More power options"
              semanticProfile: productProfile
              onClicked: root.toggleMorePower()
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        z: 39
        enabled: root.pinMenuOpen || root.morePowerOpen
        acceptedButtons: Qt.LeftButton
        onClicked: {
          root.pinMenuOpen = false
          root.pinMenuAnchor = null
          root.pinMenuItem = null
          root.morePowerOpen = false
        }
      }

      Item {
        id: powerMenu
        z: 40
        width: 200
        height: powerCol.implicitHeight + 12
        visible: root.morePowerOpen
        x: {
          var at = powerMore.mapToItem(startCard, 0, 0)
          return Math.max(8, Math.min(at.x + powerMore.width - width, startCard.width - width - 8))
        }
        y: {
          var at = powerMore.mapToItem(startCard, 0, 0)
          return Math.max(8, at.y - height - 4)
        }

        Rectangle {
          anchors.fill: parent
          color: Tokens.chrome.menu
          radius: Tokens.radius.medium
          border.color: Tokens.border.subtle
          border.width: 1

          Column {
            id: powerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 2

            Repeater {
              model: [
                { label: "Lock", icon: "\u26BF", command: "omarchy-system-lock", tip: "Lock" },
                { label: "Restart", icon: "\u21BB", command: "omarchy-system-reboot", tip: "Restart" },
                { label: "Log off", icon: "", command: "omarchy-system-logout", tip: "Log off" },
                { label: "Shut down", icon: "\u23FB", command: "omarchy-system-shutdown", tip: "Shut down" }
              ]
              delegate: Item {
                width: powerCol.width
                height: Semantics.minimumTarget(productProfile)
                Rectangle {
                  anchors.fill: parent
                  radius: Tokens.radius.small
                  color: powerRowMouse.containsMouse ? Tokens.chrome.hover : "transparent"
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  text: modelData.icon
                  color: Tokens.text.primary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 32
                  text: productProfile.text(modelData.label)
                  color: Tokens.text.primary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: powerRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    Util.execDetached(modelData.command)
                    root.morePowerOpen = false
                    root.close()
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: pinMenu
        z: 40
        width: 220
        height: pinCol.implicitHeight + 12
        visible: root.pinMenuOpen && root.pinMenuAnchor !== null
        x: {
          if (!root.pinMenuAnchor) return 8
          var at = root.pinMenuAnchor.mapToItem(startCard, 0, 0)
          return Math.max(8, Math.min(at.x, startCard.width - width - 8))
        }
        y: {
          if (!root.pinMenuAnchor) return 8
          var at = root.pinMenuAnchor.mapToItem(startCard, 0, 0)
          return Math.max(8, Math.min(at.y, startCard.height - height - 8))
        }

        Rectangle {
          anchors.fill: parent
          color: Tokens.chrome.menu
          radius: Tokens.radius.medium
          border.color: Tokens.border.subtle
          border.width: 1

          Column {
            id: pinCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 2

            Repeater {
              model: root.pinMenuJumpList
              delegate: Item {
                width: pinCol.width
                height: Semantics.minimumTarget(productProfile)
                Rectangle {
                  anchors.fill: parent
                  radius: Tokens.radius.small
                  color: jumpRowMouse.containsMouse ? Tokens.chrome.hover : "transparent"
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  anchors.right: parent.right
                  anchors.rightMargin: 8
                  text: modelData.name
                  color: Tokens.text.primary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                MouseArea {
                  id: jumpRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.launchingFromStart = true
                    if (root.appLibrary)
                      root.appLibrary.launchAction(root.desktopIdOf(root.pinMenuItem), modelData, modelData.name)
                    root.pinMenuOpen = false
                    root.pinMenuAnchor = null
                    root.pinMenuItem = null
                    root.close()
                  }
                }
              }
            }

            Item {
              width: pinCol.width
              height: Semantics.minimumTarget(productProfile)
              Rectangle {
                anchors.fill: parent
                radius: Tokens.radius.small
                color: pinRowMouse.containsMouse ? Tokens.chrome.hover : "transparent"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                text: productProfile.text(root.isPinnedId(root.desktopIdOf(root.pinMenuItem)) ? "Unpin from taskbar" : "Pin to taskbar")
                color: Tokens.text.primary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: pinRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.togglePinned(root.pinMenuItem)
                  root.pinMenuOpen = false
                  root.pinMenuAnchor = null
                  root.pinMenuItem = null
                }
              }
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
