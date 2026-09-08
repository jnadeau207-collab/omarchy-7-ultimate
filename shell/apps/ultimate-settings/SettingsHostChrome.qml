import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons

import "../ultimate-files/ExplorerTheme.js" as Aero

Item {
  id: root

  property var productProfile: null
  property var crumbs: []
  property string searchText: ""
  property string searchPlaceholder: "Search Control Panel"

  signal searchChanged(string text)
  signal crumbActivated(string routeId)

  implicitHeight: Aero.addressHeight

  readonly property string bodyFontFamily: Aero.fontFamily
  readonly property color pageFill: Aero.contentFill
  readonly property color cardFill: Aero.contentFill
  readonly property color cardBorder: Aero.headerBorder
  readonly property color navFill: Aero.navFill
  readonly property color navEdge: Aero.navBorder

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Aero.commandTop }
      GradientStop { position: 1; color: Aero.commandBottom }
    }
    border.width: 1
    border.color: Aero.commandBorder
  }

  Rectangle {
    id: crumbField
    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(160, parent.width - searchField.width - 28)
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
    width: Math.max(160, Math.min(240, parent.width * 0.28))
    height: 24
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
