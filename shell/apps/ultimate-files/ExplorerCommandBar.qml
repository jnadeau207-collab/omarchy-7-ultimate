import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

import "ExplorerTheme.js" as Aero

Item {
  id: root

  property var productProfile: null
  property var actions: []
  property string viewMode: "details"
  property string sessionBadge: "SESSION CONTROL"
  property bool previewVisible: false

  signal actionTriggered(string key)
  signal viewModeRequested(string mode)
  signal previewToggled()
  signal helpRequested()

  implicitHeight: Aero.commandHeight

  readonly property var paintedActions: {
    var list = []
    var seen = Array.isArray(root.actions) ? root.actions : []
    for (var i = 0; i < seen.length; i++) {
      if (seen[i] && seen[i].chrome !== false)
        list.push(seen[i])
    }
    return list
  }

  Rectangle {
    width: parent.width
    height: 1
    y: parent.height - 1
    color: Aero.commandHighlight
    opacity: 0.25
  }

  Row {
    id: leftCommands
    anchors.left: parent.left
    anchors.leftMargin: 2
    anchors.right: trailing.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0
    clip: true

    Repeater {
      model: root.paintedActions

      delegate: Item {
        id: commandItem
        required property var modelData
        width: commandLabel.implicitWidth + (modelData.dropdown ? 28 : 18) + 16
        height: 22

        readonly property bool usable: modelData.enabled !== false

        Rectangle {
          anchors.fill: parent
          radius: Aero.controlRadius
          visible: commandHover.hovered && commandItem.usable
          border.width: 1
          border.color: Aero.hoverBorder
          gradient: Gradient {
            GradientStop { position: 0; color: Aero.hoverTop }
            GradientStop { position: 0.45; color: Aero.hoverMid }
            GradientStop { position: 1; color: Aero.hoverBottom }
          }
        }

        Canvas {
          id: commandGlyph
          width: 16
          height: 16
          anchors.left: parent.left
          anchors.leftMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          antialiasing: true
          Component.onCompleted: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            var key = String(commandItem.modelData.key || "")
            ctx.strokeStyle = commandItem.usable ? "#3d5a73" : Aero.textDisabled
            ctx.fillStyle = commandItem.usable ? "#cfe3f4" : "#e8e8e8"
            ctx.lineWidth = 1
            if (key === "organize") {
              ctx.fillRect(2, 5, 12, 9)
              ctx.strokeRect(2, 5, 12, 9)
              ctx.fillStyle = commandItem.usable ? "#f6d27a" : "#e0e0e0"
              ctx.beginPath()
              ctx.moveTo(2, 5)
              ctx.lineTo(6, 5)
              ctx.lineTo(8, 7)
              ctx.lineTo(14, 7)
              ctx.lineTo(14, 5)
              ctx.lineTo(2, 5)
              ctx.fill()
              ctx.stroke()
            } else if (key === "new-folder") {
              ctx.fillStyle = commandItem.usable ? "#f6d27a" : "#e0e0e0"
              ctx.fillRect(1, 6, 11, 8)
              ctx.strokeRect(1, 6, 11, 8)
              ctx.fillStyle = commandItem.usable ? "#2f6f2f" : Aero.textDisabled
              ctx.fillRect(13, 3, 2, 8)
              ctx.fillRect(10, 6, 8, 2)
            } else if (key.indexOf("share") >= 0) {
              ctx.beginPath()
              ctx.arc(5, 6, 2.5, 0, Math.PI * 2)
              ctx.arc(11, 6, 2.5, 0, Math.PI * 2)
              ctx.fill()
              ctx.stroke()
            } else if (key === "open" || key === "system-properties" || key === "control-panel") {
              ctx.fillRect(3, 3, 10, 10)
              ctx.strokeRect(3, 3, 10, 10)
              ctx.fillStyle = commandItem.usable ? "#6aa7d4" : "#d0d0d0"
              ctx.fillRect(4, 5, 8, 7)
            } else {
              ctx.fillRect(3, 4, 10, 8)
              ctx.strokeRect(3, 4, 10, 8)
            }
          }
        }

        Text {
          id: commandLabel
          anchors.left: commandGlyph.right
          anchors.leftMargin: 3
          anchors.verticalCenter: parent.verticalCenter
          text: Semantics.text(root.productProfile, modelData.label)
          textFormat: Text.PlainText
          color: commandItem.usable ? Aero.textPrimary : Aero.textDisabled
          font.family: Aero.fontFamily
          font.pixelSize: Aero.fontSize
        }

        Text {
          visible: modelData.dropdown === true
          anchors.left: commandLabel.right
          anchors.leftMargin: 3
          anchors.verticalCenter: parent.verticalCenter
          text: "▾"
          color: commandItem.usable ? Aero.textSecondary : Aero.textDisabled
          font.family: Aero.fontFamily
          font.pixelSize: 10
        }

        HoverHandler { id: commandHover; enabled: commandItem.usable }
        TapHandler {
          enabled: commandItem.usable
          onSingleTapped: root.actionTriggered(String(modelData.key))
        }

        Accessible.role: Accessible.Button
        Accessible.name: Semantics.text(root.productProfile, modelData.label)
        Accessible.onPressAction: if (commandItem.usable) root.actionTriggered(String(modelData.key))
      }
    }
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Item {
      id: viewButton
      width: 44
      height: 22

      Rectangle {
        anchors.fill: parent
        radius: Aero.controlRadius
        visible: viewHover.hovered || viewMenu.visible
        border.width: 1
        border.color: Aero.hoverBorder
        gradient: Gradient {
          GradientStop { position: 0; color: Aero.hoverTop }
          GradientStop { position: 0.45; color: Aero.hoverMid }
          GradientStop { position: 1; color: Aero.hoverBottom }
        }
      }

      Canvas {
        id: viewGlyph
        width: 16
        height: 16
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        antialiasing: true

        Connections {
          target: root
          function onViewModeChanged() { viewGlyph.requestPaint() }
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          ctx.fillStyle = "#4a5b6b"
          if (root.viewMode === "icons") {
            ctx.fillRect(1, 1, 6, 6)
            ctx.fillRect(9, 1, 6, 6)
            ctx.fillRect(1, 9, 6, 6)
            ctx.fillRect(9, 9, 6, 6)
          } else if (root.viewMode === "list") {
            for (var i = 0; i < 4; i++) {
              ctx.fillRect(1, 1 + i * 4, 3, 3)
              ctx.fillRect(6, 2 + i * 4, 9, 1)
            }
          } else {
            for (var r = 0; r < 4; r++) {
              ctx.fillRect(1, 1 + r * 4, 3, 3)
              ctx.fillRect(6, 2 + r * 4, 5, 1)
              ctx.fillRect(12, 2 + r * 4, 3, 1)
            }
          }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        color: Aero.textSecondary
        font.family: Aero.fontFamily
        font.pixelSize: 10
      }

      HoverHandler { id: viewHover }
      TapHandler { onSingleTapped: viewMenu.visible ? viewMenu.close() : viewMenu.open() }

      Accessible.role: Accessible.Button
      Accessible.name: Semantics.text(root.productProfile, "Change your view")

      Controls.Popup {
        id: viewMenu
        y: viewButton.height + 2
        x: viewButton.width - width
        width: 168
        padding: 2

        background: Rectangle {
          color: Aero.menuFill
          border.width: 1
          border.color: Aero.menuBorder
        }

        contentItem: Column {
          spacing: 0

          Repeater {
            model: [
              { key: "icons", label: "Large Icons" },
              { key: "list", label: "List" },
              { key: "details", label: "Details" },
              { key: "tiles", label: "Tiles" }
            ]

            delegate: Item {
              required property var modelData
              width: 164
              height: 22

              readonly property bool active: root.viewMode === modelData.key

              Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                visible: menuHover.hovered || parent.active
                color: menuHover.hovered ? Aero.menuHover : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Aero.menuGutter
                anchors.verticalCenter: parent.verticalCenter
                text: Semantics.text(root.productProfile, modelData.label)
                textFormat: Text.PlainText
                color: menuHover.hovered ? "#ffffff" : Aero.textPrimary
                font.family: Aero.fontFamily
                font.pixelSize: Aero.fontSize
                font.bold: parent.active
              }

              HoverHandler { id: menuHover }
              TapHandler {
                onSingleTapped: {
                  root.viewModeRequested(String(modelData.key))
                  viewMenu.close()
                }
              }

              Accessible.role: Accessible.MenuItem
              Accessible.name: Semantics.text(root.productProfile, modelData.label)
            }
          }
        }
      }
    }

    Item {
      id: previewButton
      width: 24
      height: 22

      Rectangle {
        anchors.fill: parent
        radius: Aero.controlRadius
        visible: previewHover.hovered || root.previewVisible
        border.width: 1
        border.color: Aero.hoverBorder
        gradient: Gradient {
          GradientStop { position: 0; color: Aero.hoverTop }
          GradientStop { position: 0.45; color: Aero.hoverMid }
          GradientStop { position: 1; color: Aero.hoverBottom }
        }
      }

      Canvas {
        anchors.fill: parent
        anchors.margins: 4
        antialiasing: true
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          ctx.strokeStyle = "#3d5a73"
          ctx.strokeRect(0.5, 0.5, width - 4, height - 1)
          ctx.fillStyle = "#cfe3f4"
          ctx.fillRect(width - 6, 1, 5, height - 2)
        }
      }

      HoverHandler { id: previewHover }
      TapHandler { onSingleTapped: root.previewToggled() }

      Accessible.role: Accessible.Button
      Accessible.name: Semantics.text(root.productProfile, "Show the preview pane")
      Accessible.checkable: true
      Accessible.checked: root.previewVisible
    }

    Item {
      id: helpButton
      width: 22
      height: 22

      Rectangle {
        anchors.fill: parent
        radius: Aero.controlRadius
        visible: helpHover.hovered
        border.width: 1
        border.color: Aero.hoverBorder
        gradient: Gradient {
          GradientStop { position: 0; color: Aero.hoverTop }
          GradientStop { position: 0.45; color: Aero.hoverMid }
          GradientStop { position: 1; color: Aero.hoverBottom }
        }
      }

      Text {
        anchors.centerIn: parent
        text: "?"
        color: "#0b4c86"
        font.family: Aero.fontFamily
        font.pixelSize: 13
        font.bold: true
      }

      HoverHandler { id: helpHover }
      TapHandler { onSingleTapped: root.helpRequested() }

      Accessible.role: Accessible.Button
      Accessible.name: Semantics.text(root.productProfile, "Help")
    }
  }
}
