import QtQuick
import qs.Commons

import "ExplorerTheme.js" as Aero

Item {
  id: root

  property var productProfile: null
  property string title: ""

  signal closeRequested()
  signal minimizeRequested()
  signal maximizeRequested()

  implicitHeight: Aero.captionHeightPx

  readonly property color glass: Qt.rgba(
    Qt.color(Aero.captionGlass).r,
    Qt.color(Aero.captionGlass).g,
    Qt.color(Aero.captionGlass).b,
    Aero.captionGlassAlpha)

  Rectangle {
    anchors.fill: parent
    color: root.glass
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(1, parent.height * 0.40)
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
      GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.34) }
      GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 1
    color: Qt.rgba(1, 1, 1, 0.62)
  }

  Text {
    id: captionTitle
    anchors.left: parent.left
    anchors.leftMargin: Aero.captionTextPad
    anchors.right: captionButtons.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignLeft
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    text: Semantics.text(root.productProfile, root.title)
    textFormat: Text.PlainText
    color: Aero.captionText
    font.family: Aero.fontFamily
    font.pixelSize: 13

    Accessible.role: Accessible.StaticText
    Accessible.name: captionTitle.text
  }

  Row {
    id: captionButtons
    anchors.right: parent.right
    anchors.rightMargin: Aero.captionButtonPad
    anchors.top: parent.top
    spacing: 0

    Repeater {
      model: [
        { key: "minimize", glyph: "–" },
        { key: "maximize", glyph: "□" },
        { key: "close", glyph: "×" }
      ]

      delegate: Item {
        required property var modelData
        width: Aero.captionButtonPx
        height: Aero.captionHeightPx

        readonly property bool closeButton: modelData.key === "close"

        Rectangle {
          anchors.fill: parent
          visible: captionHover.hovered
          color: parent.closeButton ? Aero.captionCloseBg : Aero.captionButtonFace
        }

        Text {
          anchors.centerIn: parent
          text: modelData.glyph
          textFormat: Text.PlainText
          color: captionHover.hovered && parent.closeButton ? Aero.captionCloseFg : Aero.captionText
          font.family: Aero.fontFamily
          font.pixelSize: 13
        }

        HoverHandler { id: captionHover }
        TapHandler {
          onSingleTapped: {
            if (modelData.key === "close") root.closeRequested()
            else if (modelData.key === "minimize") root.minimizeRequested()
            else root.maximizeRequested()
          }
        }

        Accessible.role: Accessible.Button
        Accessible.name: Semantics.text(root.productProfile, modelData.key === "close" ? "Close" : modelData.key === "minimize" ? "Minimize" : "Maximize")
      }
    }
  }
}
