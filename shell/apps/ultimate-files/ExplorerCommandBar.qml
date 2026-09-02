import QtQuick
import QtQuick.Controls as Controls

import "ExplorerTheme.js" as Aero

Item {
  id: root

  property var actions: []
  property string viewMode: "details"

  signal actionTriggered(string key)
  signal viewModeRequested(string mode)

  implicitHeight: Aero.commandHeight

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Aero.commandTop }
      GradientStop { position: 1; color: Aero.commandBottom }
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Aero.commandHighlight
  }

  Rectangle {
    width: parent.width
    height: 1
    y: parent.height - 1
    color: Aero.commandBorder
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 4
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.actions

      delegate: Item {
        id: commandItem
        required property var modelData
        width: commandLabel.implicitWidth + (modelData.dropdown ? 26 : 16)
        height: 22

        readonly property bool usable: modelData.enabled !== false

        Rectangle {
          anchors.fill: parent
          radius: 3
          visible: commandHover.hovered && commandItem.usable
          border.width: 1
          border.color: Aero.hoverBorder
          gradient: Gradient {
            GradientStop { position: 0; color: Aero.hoverTop }
            GradientStop { position: 1; color: Aero.hoverBottom }
          }
        }

        Text {
          id: commandLabel
          anchors.left: parent.left
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          textFormat: Text.PlainText
          color: commandItem.usable ? Aero.textPrimary : Aero.textDisabled
          font.family: Aero.fontFamily
          font.pixelSize: 12
        }

        Text {
          visible: modelData.dropdown === true
          anchors.left: commandLabel.right
          anchors.leftMargin: 4
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
        Accessible.name: modelData.label
        Accessible.onPressAction: if (commandItem.usable) root.actionTriggered(String(modelData.key))
      }
    }
  }

  Item {
    id: viewButton
    width: 44
    height: 22
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
      anchors.fill: parent
      radius: 3
      visible: viewHover.hovered || viewMenu.visible
      border.width: 1
      border.color: Aero.hoverBorder
      gradient: Gradient {
        GradientStop { position: 0; color: Aero.hoverTop }
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
      anchors.rightMargin: 7
      anchors.verticalCenter: parent.verticalCenter
      text: "▾"
      color: Aero.textSecondary
      font.family: Aero.fontFamily
      font.pixelSize: 10
    }

    HoverHandler { id: viewHover }
    TapHandler { onSingleTapped: viewMenu.visible ? viewMenu.close() : viewMenu.open() }

    Accessible.role: Accessible.Button
    Accessible.name: "Change your view"

    Controls.Popup {
      id: viewMenu
      y: viewButton.height + 2
      x: viewButton.width - width
      width: 132
      padding: 1

      background: Rectangle {
        color: "#ffffff"
        border.width: 1
        border.color: "#a0a0a0"
      }

      contentItem: Column {
        spacing: 0

        Repeater {
          model: [
            { key: "icons", label: "Large Icons" },
            { key: "list", label: "List" },
            { key: "details", label: "Details" }
          ]

          delegate: Item {
            required property var modelData
            width: 130
            height: 22

            readonly property bool active: root.viewMode === modelData.key

            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: 2
              visible: menuHover.hovered || parent.active
              border.width: 1
              border.color: Aero.hoverBorder
              gradient: Gradient {
                GradientStop { position: 0; color: Aero.hoverTop }
                GradientStop { position: 1; color: Aero.hoverBottom }
              }
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              textFormat: Text.PlainText
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
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
            Accessible.name: modelData.label
          }
        }
      }
    }
  }
}
