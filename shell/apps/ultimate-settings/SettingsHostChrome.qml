import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

import "../ultimate-files/ExplorerTheme.js" as Aero

Item {
  id: root

  property var productProfile: null
  property var crumbs: []
  property string searchText: ""
  property string searchPlaceholder: "Search Control Panel"
  property bool canBack: false
  property bool canForward: false

  signal searchChanged(string text)
  signal crumbActivated(string routeId)
  signal backRequested()
  signal forwardRequested()

  implicitHeight: Aero.addressHeight

  readonly property string bodyFontFamily: Aero.fontFamily
  readonly property color pageFill: Aero.contentFill
  readonly property color cardFill: Aero.contentFill
  readonly property color cardBorder: Aero.headerBorder
  readonly property color navFill: Aero.navFill
  readonly property color navEdge: Aero.navBorder

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

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Aero.glassSheenLeft }
      GradientStop { position: 0.5; color: Aero.glassSheenMid }
      GradientStop { position: 1.0; color: Aero.glassSheenRight }
    }
  }

  Canvas {
    id: backFace
    width: Aero.backDiameter
    height: Aero.backDiameter
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var r = Math.min(width, height) / 2 - 1.5
      var fill = ctx.createLinearGradient(cx, cy - r, cx, cy + r)
      fill.addColorStop(0, root.canBack ? Aero.circleTop : Aero.circleDisabledTop)
      fill.addColorStop(1, root.canBack ? Aero.circleBottom : Aero.circleDisabledBottom)
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.fillStyle = fill
      ctx.fill()
      ctx.strokeStyle = root.canBack ? Aero.circleBorder : Aero.circleDisabledBorder
      ctx.stroke()
      ctx.fillStyle = root.canBack ? Aero.circleArrow : Aero.circleDisabledArrow
      ctx.beginPath()
      ctx.moveTo(cx + 3, cy - 5)
      ctx.lineTo(cx - 5, cy)
      ctx.lineTo(cx + 3, cy + 5)
      ctx.fill()
    }

    Connections {
      target: root
      function onCanBackChanged() { backFace.requestPaint() }
    }

    TapHandler { onSingleTapped: if (root.canBack) root.backRequested() }
    Accessible.role: Accessible.Button
    Accessible.name: Semantics.text(root.productProfile, "Back")
  }

  Canvas {
    id: forwardFace
    width: Aero.forwardDiameter
    height: Aero.forwardDiameter
    anchors.left: backFace.right
    anchors.leftMargin: 2
    anchors.verticalCenter: parent.verticalCenter
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var r = Math.min(width, height) / 2 - 1.5
      var fill = ctx.createLinearGradient(cx, cy - r, cx, cy + r)
      fill.addColorStop(0, root.canForward ? Aero.circleTop : Aero.circleDisabledTop)
      fill.addColorStop(1, root.canForward ? Aero.circleBottom : Aero.circleDisabledBottom)
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.fillStyle = fill
      ctx.fill()
      ctx.strokeStyle = root.canForward ? Aero.circleBorder : Aero.circleDisabledBorder
      ctx.stroke()
      ctx.fillStyle = root.canForward ? Aero.circleArrow : Aero.circleDisabledArrow
      ctx.beginPath()
      ctx.moveTo(cx - 3, cy - 5)
      ctx.lineTo(cx + 5, cy)
      ctx.lineTo(cx - 3, cy + 5)
      ctx.fill()
    }

    Connections {
      target: root
      function onCanForwardChanged() { forwardFace.requestPaint() }
    }

    TapHandler { onSingleTapped: if (root.canForward) root.forwardRequested() }
    Accessible.role: Accessible.Button
    Accessible.name: Semantics.text(root.productProfile, "Forward")
  }

  Rectangle {
    id: crumbField
    anchors.left: forwardFace.right
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(160, parent.width - searchField.width - backFace.width - forwardFace.width - 36)
    height: 22
    color: Aero.fieldFill
    border.width: 1
    border.color: Aero.fieldBorder

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      clip: true

      Repeater {
        model: root.crumbs

        delegate: Row {
          required property var modelData
          required property int index
          spacing: 0

          Text {
            visible: index > 0
            text: "\u25B8"
            color: Aero.crumbSeparator
            font.family: Aero.fontFamily
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 3
            rightPadding: 3
          }

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
              text: Semantics.text(root.productProfile, String(modelData.label || ""))
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            HoverHandler { id: crumbHover }
            TapHandler {
              onSingleTapped: {
                if (String(modelData.routeId || "") !== "")
                  root.crumbActivated(String(modelData.routeId))
              }
            }

            Accessible.role: Accessible.Button
            Accessible.name: Semantics.text(root.productProfile, String(modelData.label || "Control Panel"))
          }
        }
      }
    }

    Accessible.role: Accessible.Pane
    Accessible.name: Semantics.text(root.productProfile, "Control Panel breadcrumb")
  }

  Rectangle {
    id: searchField
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(Aero.searchMinWidth, Math.min(240, parent.width * 0.28))
    height: 22
    radius: 2
    color: Aero.fieldFill
    border.width: 1
    border.color: searchInput.activeFocus ? Aero.fieldFocusBorder : Aero.fieldBorder

    Controls.TextField {
      id: searchInput
      anchors.fill: parent
      anchors.margins: 1
      text: root.searchText
      placeholderText: Semantics.text(root.productProfile, root.searchPlaceholder)
      font.family: Aero.fontFamily
      font.pixelSize: 12
      font.italic: text === ""
      color: Aero.textPrimary
      placeholderTextColor: Aero.textPlaceholder
      selectByMouse: true
      background: Rectangle { color: Aero.fieldFill }
      onTextChanged: {
        if (text !== root.searchText)
          root.searchChanged(text)
      }

      Accessible.name: Semantics.text(root.productProfile, root.searchPlaceholder)
    }
  }
}
