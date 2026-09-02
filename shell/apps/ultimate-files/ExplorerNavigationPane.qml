import QtQuick
import QtQuick.Controls as Controls

import "ExplorerTheme.js" as Aero
import "." as Files

Rectangle {
  id: root

  property string accountName: "Home"
  property string currentRoute: ""
  property var mounts: []
  property var expanded: ({ favorites: true, libraries: true, computer: true })

  signal routeActivated(string routeId)

  color: Aero.navFill

  function toggle(key) {
    var next = {}
    for (var name in root.expanded) next[name] = root.expanded[name]
    next[key] = !next[key]
    root.expanded = next
  }

  function rows() {
    var list = []
    list.push({ key: "favorites", depth: 0, label: "Favorites", icon: "favorites", routeId: "", group: true })
    if (root.expanded.favorites) {
      list.push({ key: "favorites.desktop", depth: 1, label: "Desktop", icon: "directory", routeId: "files.desktop", group: false })
      list.push({ key: "favorites.downloads", depth: 1, label: "Downloads", icon: "directory", routeId: "files.downloads", group: false })
      list.push({ key: "favorites.recent", depth: 1, label: "Recent Places", icon: "directory", routeId: "files.recent", group: false })
    }
    list.push({ key: "libraries", depth: 0, label: "Libraries", icon: "libraries", routeId: "", group: true })
    if (root.expanded.libraries) {
      list.push({ key: "libraries.documents", depth: 1, label: "Documents", icon: "directory", routeId: "files.documents", group: false })
      list.push({ key: "libraries.music", depth: 1, label: "Music", icon: "directory", routeId: "files.music", group: false })
      list.push({ key: "libraries.pictures", depth: 1, label: "Pictures", icon: "directory", routeId: "files.pictures", group: false })
      list.push({ key: "libraries.videos", depth: 1, label: "Videos", icon: "directory", routeId: "files.videos", group: false })
    }
    list.push({ key: "home", depth: 0, label: root.accountName, icon: "directory", routeId: "files.overview", group: false })
    list.push({ key: "computer", depth: 0, label: "Computer", icon: "computer", routeId: "files.this-pc", group: true })
    if (root.expanded.computer) {
      var seen = Array.isArray(root.mounts) ? root.mounts : []
      for (var i = 0; i < seen.length; i++) {
        list.push({ key: "computer." + seen[i].id, depth: 1, label: seen[i].title, icon: "drive", routeId: "", group: false })
      }
    }
    list.push({ key: "network", depth: 0, label: "Network", icon: "network", routeId: "files.network", group: false })
    list.push({ key: "recycle", depth: 0, label: "Recycle Bin", icon: "trash", routeId: "files.trash", group: false })
    return list
  }

  Controls.ScrollView {
    anchors.fill: parent
    anchors.topMargin: 6
    clip: true
    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

    Column {
      width: root.width
      spacing: 0

      Repeater {
        model: root.rows()

        delegate: Item {
          id: row
          required property var modelData
          width: root.width
          height: 21

          readonly property bool selected: modelData.routeId !== "" && modelData.routeId === root.currentRoute
          readonly property bool actionable: modelData.routeId !== "" || modelData.group

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: 2
            visible: row.selected || hover.hovered
            border.width: 1
            border.color: row.selected ? (hover.hovered ? Aero.hoverSelectedBorder : Aero.selectionBorder) : Aero.hoverBorder
            gradient: Gradient {
              GradientStop {
                position: 0
                color: row.selected ? (hover.hovered ? Aero.hoverSelectedTop : Aero.selectionTop) : Aero.hoverTop
              }
              GradientStop {
                position: 1
                color: row.selected ? (hover.hovered ? Aero.hoverSelectedBottom : Aero.selectionBottom) : Aero.hoverBottom
              }
            }
          }

          Canvas {
            id: expander
            visible: row.modelData.group
            width: 11
            height: 11
            anchors.verticalCenter: parent.verticalCenter
            x: 6 + row.modelData.depth * 16
            antialiasing: true
            readonly property bool open: root.expanded[row.modelData.key] === true
            onOpenChanged: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.clearRect(0, 0, width, height)
              ctx.beginPath()
              if (open) {
                ctx.moveTo(1.5, 3.5)
                ctx.lineTo(9.5, 3.5)
                ctx.lineTo(5.5, 8.5)
              } else {
                ctx.moveTo(3.5, 1.5)
                ctx.lineTo(8.5, 5.5)
                ctx.lineTo(3.5, 9.5)
              }
              ctx.closePath()
              ctx.fillStyle = open ? "#5a6b7b" : "#ffffff"
              ctx.fill()
              ctx.strokeStyle = "#71889c"
              ctx.lineWidth = 1
              ctx.stroke()
            }
          }

          Files.ExplorerIcon {
            id: glyph
            width: 16
            height: 16
            kind: row.modelData.icon
            anchors.verticalCenter: parent.verticalCenter
            x: 20 + row.modelData.depth * 16
          }

          Text {
            anchors.left: glyph.right
            anchors.leftMargin: 5
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.modelData.group ? Aero.navHeaderText : Aero.navItemText
            font.family: Aero.fontFamily
            font.pixelSize: 12
            font.bold: row.modelData.group
          }

          HoverHandler { id: hover; enabled: row.actionable }

          TapHandler {
            enabled: row.actionable
            onSingleTapped: {
              if (row.modelData.routeId !== "") root.routeActivated(row.modelData.routeId)
              else if (row.modelData.group) root.toggle(row.modelData.key)
            }
            onDoubleTapped: if (row.modelData.group) root.toggle(row.modelData.key)
          }

          Accessible.role: Accessible.TreeItem
          Accessible.name: row.modelData.label
          Accessible.selected: row.selected
        }
      }
    }
  }
}
