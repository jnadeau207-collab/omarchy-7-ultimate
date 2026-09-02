import QtQuick

import "FilesModel.js" as FilesModel
import "ExplorerTheme.js" as Aero
import "." as Files

Rectangle {
  id: root

  property var record: null
  property int itemCount: 0
  property string locationLabel: ""
  property string boundary: ""
  property string folderPath: ""
  property bool truncated: false

  implicitHeight: Math.max(Aero.detailsHeight, boundaryBanner.visible ? boundaryBanner.implicitHeight + 8 : 0)

  gradient: Gradient {
    GradientStop { position: 0; color: Aero.detailsTop }
    GradientStop { position: 1; color: Aero.detailsBottom }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Aero.detailsBorder
  }

  function pairs() {
    if (!root.record) return []
    var list = []
    if (root.record.modifiedText) list.push({ label: "Date modified", value: root.record.modifiedText })
    if (root.record.entryKind === "file" && root.record.sizeText) list.push({ label: "Size", value: root.record.sizeText })
    if (root.folderPath !== "") list.push({ label: "Folder path", value: root.folderPath })
    list.push({ label: "Read-only", value: root.record.writable === true ? "No" : "Yes" })
    return list
  }

  Files.ExplorerIcon {
    id: preview
    width: 32
    height: 32
    kind: root.record ? (root.record.entryKind || "file") : "directory"
    extension: root.record ? FilesModel.extensionOf(root.record.title) : ""
    dimmed: root.record ? root.record.hidden === true : false
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
  }

  Column {
    id: identity
    anchors.left: preview.right
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    width: 232
    spacing: 2

    Text {
      width: parent.width
      text: root.record ? root.record.title : root.locationLabel
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Aero.textPrimary
      font.family: Aero.fontFamily
      font.pixelSize: 12
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.record ? (root.record.typeLabel || "")
        : (root.itemCount + " item" + (root.itemCount === 1 ? "" : "s") + (root.truncated ? " shown" : ""))
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Aero.textSecondary
      font.family: Aero.fontFamily
      font.pixelSize: 12
    }
  }

  Row {
    anchors.left: identity.right
    anchors.leftMargin: 24
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 26

    Repeater {
      model: root.pairs()

      delegate: Column {
        required property var modelData
        spacing: 2

        Text {
          text: modelData.label
          textFormat: Text.PlainText
          color: Aero.textSecondary
          font.family: Aero.fontFamily
          font.pixelSize: 11
        }

        Text {
          text: modelData.value
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Aero.textPrimary
          font.family: Aero.fontFamily
          font.pixelSize: 12
        }
      }
    }
  }

  Text {
    id: boundaryBanner
    visible: root.record === null && root.boundary !== ""
    anchors.left: identity.right
    anchors.leftMargin: 24
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 4
    text: root.boundary
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    maximumLineCount: 5
    color: Aero.textDisabled
    font.family: Aero.fontFamily
    font.pixelSize: 11
  }

  Accessible.role: Accessible.StaticText
  Accessible.name: root.record ? root.record.title : root.locationLabel
  Accessible.description: root.record === null ? root.boundary : ""
}
