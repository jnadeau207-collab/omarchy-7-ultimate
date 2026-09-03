import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

import "ExplorerTheme.js" as Aero
import "." as Files

Item {
  id: root

  property var productProfile: null
  property var crumbs: []
  property string locationIcon: "directory"
  property string searchPlaceholder: "Search"
  property string searchText: ""
  property bool canBack: false
  property bool canForward: false
  property bool busy: false
  property var historyMenu: []

  signal backRequested()
  signal forwardRequested()
  signal travelRequested(int index)
  signal crumbActivated(string relativePath)
  signal refreshRequested()
  signal searchAccepted(string text)

  implicitHeight: Aero.addressHeight

  readonly property color glass: {
    var base = Qt.color(Aero.aeroColorization)
    return Qt.rgba(
      base.r + (1 - base.r) * Aero.aeroBalance,
      base.g + (1 - base.g) * Aero.aeroBalance,
      base.b + (1 - base.b) * Aero.aeroBalance,
      Aero.aeroAlpha)
  }

  Rectangle {
    anchors.fill: parent
    color: root.glass
  }


  Files.ExplorerCircleButton {
    id: backButton
    direction: "back"
    enabled: root.canBack
    productProfile: root.productProfile
    width: 24
    height: 24
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    onTriggered: root.backRequested()
  }

  Files.ExplorerCircleButton {
    id: forwardButton
    direction: "forward"
    enabled: root.canForward
    productProfile: root.productProfile
    width: 24
    height: 24
    anchors.left: backButton.right
    anchors.leftMargin: 2
    anchors.verticalCenter: parent.verticalCenter
    onTriggered: root.forwardRequested()
  }

  Item {
    id: historyChevron
    width: 14
    height: 24
    anchors.left: forwardButton.right
    anchors.leftMargin: 2
    anchors.verticalCenter: parent.verticalCenter
    enabled: root.historyMenu.length > 0

    Rectangle {
      anchors.fill: parent
      radius: 2
      visible: chevronHover.hovered && historyChevron.enabled
      color: Aero.crumbHoverTop
      border.width: 1
      border.color: Aero.crumbHoverBorder
    }

    Text {
      anchors.centerIn: parent
      text: "▾"
      color: historyChevron.enabled ? Aero.textPrimary : Aero.textDisabled
      font.family: Aero.fontFamily
      font.pixelSize: 10
    }

    HoverHandler { id: chevronHover }
    TapHandler {
      onSingleTapped: historyPopup.open()
    }

    Accessible.role: Accessible.Button
    Accessible.name: Semantics.text(root.productProfile, "Recent locations")
  }

  Controls.Popup {
    id: historyPopup
    x: historyChevron.x
    y: historyChevron.y + historyChevron.height + 2
    width: 230
    padding: 1
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

    background: Rectangle {
      color: "#ffffff"
      border.width: 1
      border.color: "#a0a0a0"
    }

    contentItem: Column {
      spacing: 0

      Repeater {
        model: root.historyMenu

        delegate: Item {
          required property var modelData
          width: 228
          height: 22

          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            visible: historyHover.hovered
            color: Aero.crumbHoverTop
            border.width: 1
            border.color: Aero.crumbHoverBorder
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: (modelData.current ? "• " : "") + modelData.label
            textFormat: Text.PlainText
            color: Aero.textPrimary
            font.family: Aero.fontFamily
            font.pixelSize: 12
            font.bold: modelData.current === true
          }

          HoverHandler { id: historyHover }
          TapHandler {
            onSingleTapped: {
              historyPopup.close()
              root.travelRequested(modelData.index)
            }
          }

          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
        }
      }
    }
  }

  Rectangle {
    id: addressField
    anchors.left: historyChevron.right
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(160, parent.width - forwardButton.width - backButton.width - historyChevron.width - searchField.width - 64)
    height: 22
    color: Aero.fieldFill
    border.width: 1
    border.color: Aero.fieldBorder

    Files.ExplorerIcon {
      id: crumbIcon
      width: 16
      height: 16
      kind: root.locationIcon
      anchors.left: parent.left
      anchors.leftMargin: 3
      anchors.verticalCenter: parent.verticalCenter
    }

    Row {
      anchors.left: crumbIcon.right
      anchors.leftMargin: 2
      anchors.right: refreshButton.left
      anchors.rightMargin: 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      clip: true

      Text {
        text: "▸"
        color: Aero.crumbSeparator
        font.family: Aero.fontFamily
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: 2
        leftPadding: 2
      }

      Repeater {
        model: root.crumbs

        delegate: Row {
          required property var modelData
          required property int index
          spacing: 0

          Rectangle {
            width: crumbLabel.implicitWidth + 10
            height: 18
            radius: 2
            color: crumbHover.hovered ? Aero.crumbHoverTop : "transparent"
            border.width: crumbHover.hovered ? 1 : 0
            border.color: Aero.crumbHoverBorder

            Text {
              id: crumbLabel
              anchors.centerIn: parent
              text: index === 0 ? Semantics.text(root.productProfile, modelData.label) : modelData.label
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: crumbHover }
            TapHandler { onSingleTapped: root.crumbActivated(String(modelData.relativePath)) }

            Accessible.role: Accessible.Button
            Accessible.name: index === 0 ? Semantics.text(root.productProfile, modelData.label) : modelData.label
          }

          Text {
            text: "▸"
            color: Aero.crumbSeparator
            font.family: Aero.fontFamily
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 3
            rightPadding: 3
          }
        }
      }
    }

    Item {
      id: refreshButton
      width: 18
      height: 18
      anchors.right: parent.right
      anchors.rightMargin: 2
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.fill: parent
        radius: 2
        visible: refreshHover.hovered
        color: Aero.crumbHoverTop
        border.width: 1
        border.color: Aero.crumbHoverBorder
      }

      Canvas {
        anchors.fill: parent
        antialiasing: true
        rotation: root.busy ? 90 : 0

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          var cx = width / 2
          var cy = height / 2
          var r = Math.min(width, height) * 0.30
          ctx.beginPath()
          ctx.arc(cx, cy, r, Math.PI * 0.35, Math.PI * 1.85)
          ctx.strokeStyle = "#2d6ca3"
          ctx.lineWidth = 2
          ctx.lineCap = "round"
          ctx.stroke()
          ctx.beginPath()
          ctx.moveTo(cx + r * 0.30, cy - r * 1.30)
          ctx.lineTo(cx + r * 1.35, cy - r * 0.75)
          ctx.lineTo(cx + r * 0.20, cy - r * 0.30)
          ctx.closePath()
          ctx.fillStyle = "#2d6ca3"
          ctx.fill()
        }
      }

      HoverHandler { id: refreshHover }
      TapHandler { onSingleTapped: root.refreshRequested() }

      Accessible.role: Accessible.Button
      Accessible.name: Semantics.text(root.productProfile, "Refresh")
    }
  }

  Rectangle {
    id: searchField
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(187, Math.min(240, parent.width * 0.24))
    height: 24
    radius: 2
    color: Aero.fieldFill
    border.width: 1
    border.color: searchInput.activeFocus ? Aero.fieldFocusBorder : Aero.fieldBorder

    Rectangle {
      anchors.top: parent.top
      anchors.topMargin: 1
      anchors.left: parent.left
      anchors.leftMargin: 1
      anchors.right: parent.right
      anchors.rightMargin: 1
      height: 1
      color: "#8e8f8f"
      opacity: 0.55
    }

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: 1
      anchors.top: parent.top
      anchors.topMargin: 1
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 1
      width: 1
      color: "#8e8f8f"
      opacity: 0.55
    }

    Controls.TextField {
      id: searchInput
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.right: searchGlyph.left
      anchors.rightMargin: 2
      anchors.verticalCenter: parent.verticalCenter
      height: 18
      text: root.searchText
      placeholderText: Semantics.text(root.productProfile, root.searchPlaceholder)
      placeholderTextColor: Aero.textPlaceholder
      color: Aero.textPrimary
      font.family: Aero.fontFamily
      font.pixelSize: 12
      font.italic: text === ""
      background: null
      padding: 0
      selectByMouse: true
      onAccepted: root.searchAccepted(searchInput.text)

      Accessible.role: Accessible.EditableText
      Accessible.name: Semantics.text(root.productProfile, root.searchPlaceholder)
    }

    Files.ExplorerIcon {
      id: searchGlyph
      width: 14
      height: 14
      kind: "search"
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
