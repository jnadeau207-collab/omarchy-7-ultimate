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

  signal backRequested()
  signal forwardRequested()
  signal crumbActivated(string relativePath)
  signal refreshRequested()
  signal searchAccepted(string text)

  implicitHeight: Aero.addressHeight

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Aero.glassTop }
      GradientStop { position: 1; color: Aero.glassBottom }
    }
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

  Rectangle {
    id: addressField
    anchors.left: forwardButton.right
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(160, parent.width - forwardButton.width - backButton.width - searchField.width - 48)
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
    width: Math.max(120, Math.min(220, parent.width * 0.24))
    height: 22
    color: Aero.fieldFill
    border.width: 1
    border.color: searchInput.activeFocus ? Aero.fieldFocusBorder : Aero.fieldBorder

    Controls.TextField {
      id: searchInput
      anchors.left: parent.left
      anchors.leftMargin: 4
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
