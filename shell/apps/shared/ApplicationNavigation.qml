import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

Rectangle {
  id: root

  property string title: ""
  property var semanticProfile: null
  property var routes: []
  property string currentRoute: ""
  property alias query: search.text

  signal routeActivated(string routeId)

  color: Tokens.surface.base
  border.color: Tokens.border.subtle
  border.width: 1
  Accessible.role: Accessible.Pane
  Accessible.name: title + " navigation"

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: Semantics.text(root.semanticProfile, root.title)
      color: Tokens.text.primary
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
      Layout.fillWidth: true
    }

    Ui.SearchBox {
      id: search
      Layout.fillWidth: true
      semanticPlaceholderText: "Search"
      semanticProfile: root.semanticProfile
      accessibleName: "Search " + root.title
    }

    ListView {
      id: routeList
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.space(2)
      model: root.routes
      currentIndex: -1

      delegate: Item {
        required property var modelData
        required property int index

        width: ListView.view.width
        height: sectionLabel.visible ? sectionLabel.implicitHeight + routeButton.implicitHeight + Style.space(10) : routeButton.implicitHeight + Style.space(2)

        readonly property bool beginsSection: index === 0 || root.routes[index - 1].section !== modelData.section

        Text {
          textFormat: Text.PlainText
          id: sectionLabel
          visible: parent.beginsSection
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: parent.index === 0 ? 0 : Style.space(6)
          text: Semantics.text(root.semanticProfile, parent.modelData.section.toUpperCase())
          color: Tokens.text.disabled
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Ui.Button {
          id: routeButton
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          text: parent.modelData.title
          semanticProfile: root.semanticProfile
          leftAlign: true
          focusable: true
          selected: root.currentRoute === parent.modelData.id
          accessibleDescription: parent.modelData.description
          onClicked: root.routeActivated(parent.modelData.id)
        }
      }

      Ui.EmptyState {
        visible: routeList.count === 0
        anchors.centerIn: parent
        width: Math.min(parent.width, 260)
        semanticProfile: root.semanticProfile
        title: "No matching destinations"
        message: "Try a different search."
      }
    }
  }
}
