import QtQuick

import "ExplorerTheme.js" as Aero
import "." as Files

Rectangle {
  id: root

  property var record: null
  property string emptyText: "Select a file to preview."

  color: Aero.contentFill
  implicitWidth: Aero.previewPaneWidth

  Rectangle {
    width: 1
    height: parent.height
    color: Aero.navBorder
  }

  Files.ExplorerIcon {
    id: preview
    width: 96
    height: 96
    visible: root.record !== null
    kind: root.record ? (root.record.entryKind || "file") : "directory"
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: 24
  }

  Text {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: preview.visible ? preview.bottom : parent.top
    anchors.topMargin: preview.visible ? 12 : 24
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: root.record ? String(root.record.title || "") : root.emptyText
    textFormat: Text.PlainText
    color: root.record ? Aero.textPrimary : Aero.textSecondary
    font.family: Aero.fontFamily
    font.pixelSize: Aero.fontSize
  }
}
