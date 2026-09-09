import QtQuick

import "ExplorerTheme.js" as Aero
import "." as Files

Item {
  id: root

  property string selectedId: ""

  signal activated(string routeId)
  signal selectionChanged(var record)

  readonly property var tiles: [
    { id: "documents", title: "Documents", routeId: "files.documents" },
    { id: "pictures", title: "Pictures", routeId: "files.pictures" },
    { id: "music", title: "Music", routeId: "files.music" },
    { id: "videos", title: "Videos", routeId: "files.videos" }
  ]

  Rectangle {
    anchors.fill: parent
    color: Aero.contentFill
  }

  Text {
    id: heading
    anchors.left: parent.left
    anchors.leftMargin: 16
    anchors.top: parent.top
    anchors.topMargin: 14
    text: "Libraries"
    textFormat: Text.PlainText
    color: Aero.navHeaderText
    font.family: Aero.fontFamily
    font.pixelSize: 16
  }

  Text {
    id: description
    anchors.left: parent.left
    anchors.leftMargin: 16
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.top: heading.bottom
    anchors.topMargin: 4
    text: "Open a library to see your files and arrange them by folder, date, and other properties."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: Aero.textSecondary
    font.family: Aero.fontFamily
    font.pixelSize: 12
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.top: description.bottom
    anchors.topMargin: 16
    spacing: 8

    Repeater {
      model: root.tiles

      delegate: Item {
        id: tile
        required property var modelData
        width: Aero.tileWidth
        height: Aero.tileHeight

        readonly property bool chosen: modelData.id === root.selectedId

        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: 3
          visible: tile.chosen || tileHover.hovered
          border.width: 1
          border.color: tile.chosen ? Aero.selectionBorder : Aero.hoverBorder
          gradient: Gradient {
            GradientStop { position: 0; color: tile.chosen ? Aero.selectionTop : Aero.hoverTop }
            GradientStop { position: 1; color: tile.chosen ? Aero.selectionBottom : Aero.hoverBottom }
          }
        }

        Files.ExplorerIcon {
          width: Aero.largeIcon
          height: Aero.largeIcon
          kind: "libraries"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: 8
        }

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: kindLabel.top
          anchors.bottomMargin: 1
          horizontalAlignment: Text.AlignHCenter
          text: modelData.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Aero.textPrimary
          font.family: Aero.fontFamily
          font.pixelSize: 12
        }

        Text {
          id: kindLabel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 8
          horizontalAlignment: Text.AlignHCenter
          text: "Library"
          textFormat: Text.PlainText
          color: Aero.textSecondary
          font.family: Aero.fontFamily
          font.pixelSize: 11
        }

        HoverHandler { id: tileHover }
        TapHandler {
          onSingleTapped: {
            root.selectedId = modelData.id
            root.selectionChanged({
              id: modelData.id,
              title: modelData.title,
              entryKind: "directory",
              typeLabel: "Library",
              kind: "location",
              targetRoute: modelData.routeId
            })
          }
          onDoubleTapped: root.activated(modelData.routeId)
        }
      }
    }
  }
}
