import QtQuick
import QtQuick.Controls as Controls

import "ExplorerTheme.js" as Aero
import "." as Files

FocusScope {
  id: root

  property var items: []
  property string selectedId: ""

  signal activated(var record)
  signal selectionChanged(var record)
  signal contextRequested(var record, real windowX, real windowY)

  readonly property int count: Array.isArray(items) ? items.length : 0

  function groupFor(kind) {
    var list = []
    for (var i = 0; i < root.count; i++) {
      var record = root.items[i]
      if (record.kind === "mount" && record.mountKind === kind) list.push(record)
    }
    return list
  }

  readonly property var fixedDrives: groupFor("system")
  readonly property var removableDrives: groupFor("removable")
  readonly property var networkDrives: groupFor("smb")

  function select(record) {
    if (!record) return
    root.selectedId = String(record.id)
    root.selectionChanged(record)
  }

  Rectangle {
    anchors.fill: parent
    color: Aero.contentFill
  }

  Controls.ScrollView {
    anchors.fill: parent
    clip: true
    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

    Column {
      width: root.width
      spacing: 0
      topPadding: 10
      bottomPadding: 14

      Repeater {
        model: [
          { title: "Hard Disk Drives", drives: root.fixedDrives },
          { title: "Devices with Removable Storage", drives: root.removableDrives },
          { title: "Network Location", drives: root.networkDrives }
        ]

        delegate: Column {
          required property var modelData
          visible: modelData.drives.length > 0
          width: root.width
          spacing: 0

          Item {
            width: parent.width
            height: 26

            Text {
              id: groupLabel
              anchors.left: parent.left
              anchors.leftMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title + " (" + modelData.drives.length + ")"
              textFormat: Text.PlainText
              color: Aero.navHeaderText
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            Rectangle {
              anchors.left: groupLabel.right
              anchors.leftMargin: 8
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              height: 1
              color: Aero.headerBorder
            }
          }

          Flow {
            width: parent.width
            leftPadding: 10
            rightPadding: 10
            bottomPadding: 8
            spacing: 4

            Repeater {
              model: modelData.drives

              delegate: Item {
                id: drive
                required property var modelData
                width: 292
                height: 62

                readonly property bool chosen: modelData.id === root.selectedId
                readonly property real used: modelData.usedFraction === undefined ? -1 : modelData.usedFraction
                readonly property bool low: used >= 0.9

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: 2
                  radius: 3
                  visible: drive.chosen || driveHover.hovered
                  border.width: 1
                  border.color: drive.chosen ? (driveHover.hovered ? Aero.hoverSelectedBorder : Aero.selectionBorder) : Aero.hoverBorder
                  gradient: Gradient {
                    GradientStop {
                      position: 0
                      color: drive.chosen ? (driveHover.hovered ? Aero.hoverSelectedTop : Aero.selectionTop) : Aero.hoverTop
                    }
                    GradientStop {
                      position: 1
                      color: drive.chosen ? (driveHover.hovered ? Aero.hoverSelectedBottom : Aero.selectionBottom) : Aero.hoverBottom
                    }
                  }
                }

                Files.ExplorerIcon {
                  id: driveIcon
                  width: 44
                  height: 44
                  kind: drive.modelData.mountKind === "smb" ? "network" : "drive"
                  anchors.left: parent.left
                  anchors.leftMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: driveName
                  anchors.left: driveIcon.right
                  anchors.leftMargin: 8
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.top: parent.top
                  anchors.topMargin: 9
                  text: drive.modelData.title
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: Aero.textPrimary
                  font.family: Aero.fontFamily
                  font.pixelSize: 12
                }

                Rectangle {
                  id: capacityTrack
                  visible: drive.used >= 0
                  anchors.left: driveName.left
                  anchors.top: driveName.bottom
                  anchors.topMargin: 5
                  width: 168
                  height: 11
                  color: Aero.driveBarTrack
                  border.width: 1
                  border.color: "#a0a5ab"

                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    width: Math.max(0, Math.round((parent.width - 2) * Math.max(0, drive.used)))
                    gradient: Gradient {
                      GradientStop { position: 0; color: drive.low ? "#e8756b" : "#63b0ec" }
                      GradientStop { position: 1; color: drive.low ? Aero.driveBarFull : Aero.driveBarFill }
                    }
                  }
                }

                Text {
                  visible: drive.modelData.capacityText !== undefined && drive.modelData.capacityText !== ""
                  anchors.left: driveName.left
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.top: capacityTrack.visible ? capacityTrack.bottom : driveName.bottom
                  anchors.topMargin: 4
                  text: drive.modelData.capacityText || ""
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: Aero.textSecondary
                  font.family: Aero.fontFamily
                  font.pixelSize: 11
                }

                Text {
                  visible: drive.used < 0
                  anchors.left: driveName.left
                  anchors.top: driveName.bottom
                  anchors.topMargin: 5
                  text: drive.modelData.display || drive.modelData.subtitle || ""
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: Aero.textSecondary
                  font.family: Aero.fontFamily
                  font.pixelSize: 11
                }

                HoverHandler { id: driveHover }

                TapHandler {
                  acceptedButtons: Qt.LeftButton
                  onSingleTapped: { root.forceActiveFocus(); root.select(drive.modelData) }
                  onDoubleTapped: { root.select(drive.modelData); root.activated(drive.modelData) }
                }

                TapHandler {
                  acceptedButtons: Qt.RightButton
                  onSingleTapped: function (eventPoint) {
                    root.select(drive.modelData)
                    var mapped = drive.mapToItem(null, eventPoint.position.x, eventPoint.position.y)
                    root.contextRequested(drive.modelData, mapped.x, mapped.y)
                  }
                }

                Accessible.role: Accessible.ListItem
                Accessible.name: drive.modelData.title
                Accessible.description: drive.modelData.capacityText || ""
                Accessible.selected: drive.chosen
              }
            }
          }
        }
      }
    }
  }
}
