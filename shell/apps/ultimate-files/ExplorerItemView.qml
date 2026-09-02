import QtQuick
import QtQuick.Controls as Controls

import "ExplorerTheme.js" as Aero
import "." as Files

FocusScope {
  id: root

  property var items: []
  property string mode: "details"
  property string sortColumn: "name"
  property bool sortAscending: true
  property string selectedId: ""

  signal activated(var record)
  signal selectionChanged(var record)
  signal sortRequested(string column)
  signal contextRequested(var record, real windowX, real windowY)

  readonly property int count: Array.isArray(items) ? items.length : 0

  function recordAt(index) {
    return index >= 0 && index < root.count ? root.items[index] : null
  }

  function indexOfSelected() {
    for (var i = 0; i < root.count; i++) if (root.items[i].id === root.selectedId) return i
    return -1
  }

  function select(index) {
    var record = recordAt(index)
    if (!record) return
    root.selectedId = record.id
    root.selectionChanged(record)
  }

  function step(delta) {
    var index = indexOfSelected()
    var next = index < 0 ? 0 : index + delta
    if (next < 0) next = 0
    if (next > root.count - 1) next = root.count - 1
    select(next)
    if (root.mode === "icons") iconGrid.positionViewAtIndex(next, GridView.Contain)
    else detailList.positionViewAtIndex(next, ListView.Contain)
  }

  function activateSelected() {
    var index = indexOfSelected()
    var record = recordAt(index)
    if (record) root.activated(record)
  }

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Down) { step(root.mode === "icons" ? iconGrid.columnCount : 1); event.accepted = true }
    else if (event.key === Qt.Key_Up) { step(root.mode === "icons" ? -iconGrid.columnCount : -1); event.accepted = true }
    else if (event.key === Qt.Key_Right && root.mode === "icons") { step(1); event.accepted = true }
    else if (event.key === Qt.Key_Left && root.mode === "icons") { step(-1); event.accepted = true }
    else if (event.key === Qt.Key_Home) { step(-root.count); event.accepted = true }
    else if (event.key === Qt.Key_End) { step(root.count); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateSelected(); event.accepted = true }
  }

  Rectangle {
    anchors.fill: parent
    color: Aero.contentFill
  }

  Column {
    anchors.fill: parent
    visible: root.mode === "details"

    Item {
      id: header
      width: parent.width
      height: Aero.headerHeight

      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: Aero.headerTop }
          GradientStop { position: 1; color: Aero.headerBottom }
        }
      }

      Row {
        anchors.fill: parent

        Repeater {
        model: [
          { key: "name", label: "Name", weight: 0.42 },
          { key: "modified", label: "Date modified", weight: 0.24 },
          { key: "type", label: "Type", weight: 0.20 },
          { key: "size", label: "Size", weight: 0.14 }
        ]

          delegate: Item {
            required property var modelData
            width: Math.floor(header.width * modelData.weight)
            height: header.height

            Rectangle {
              anchors.fill: parent
              visible: headerHover.hovered
              gradient: Gradient {
                GradientStop { position: 0; color: Aero.headerHoverTop }
                GradientStop { position: 1; color: Aero.headerHoverBottom }
              }
              border.width: 1
              border.color: Aero.headerHoverBorder
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.right: sortMark.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Aero.headerText
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            Canvas {
              id: sortMark
              width: 9
              height: 6
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              visible: root.sortColumn === modelData.key
              antialiasing: true
              onVisibleChanged: requestPaint()

              Connections {
                target: root
                function onSortAscendingChanged() { sortMark.requestPaint() }
                function onSortColumnChanged() { sortMark.requestPaint() }
              }

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                ctx.beginPath()
                if (root.sortAscending) {
                  ctx.moveTo(0.5, height - 0.5)
                  ctx.lineTo(width - 0.5, height - 0.5)
                  ctx.lineTo(width / 2, 0.5)
                } else {
                  ctx.moveTo(0.5, 0.5)
                  ctx.lineTo(width - 0.5, 0.5)
                  ctx.lineTo(width / 2, height - 0.5)
                }
                ctx.closePath()
                ctx.fillStyle = "#6b7b8a"
                ctx.fill()
              }
            }

            Rectangle {
              width: 1
              height: parent.height - 8
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              color: Aero.headerSeparator
            }

            HoverHandler { id: headerHover }
            TapHandler { onSingleTapped: root.sortRequested(modelData.key) }

            Accessible.role: Accessible.ColumnHeader
            Accessible.name: modelData.label
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        anchors.bottom: parent.bottom
        color: Aero.headerBorder
      }
    }

    Controls.ScrollView {
      width: parent.width
      height: parent.height - header.height
      clip: true
      Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

      ListView {
        id: detailList
        model: root.items
        interactive: true
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          id: detailRow
          required property var modelData
          required property int index
          width: detailList.width
          height: Aero.rowHeight

          readonly property bool chosen: modelData.id === root.selectedId

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            radius: 2
            visible: detailRow.chosen || rowHover.hovered
            border.width: 1
            border.color: detailRow.chosen ? (rowHover.hovered ? Aero.hoverSelectedBorder : Aero.selectionBorder) : Aero.hoverBorder
            gradient: Gradient {
              GradientStop {
                position: 0
                color: detailRow.chosen ? (rowHover.hovered ? Aero.hoverSelectedTop : Aero.selectionTop) : Aero.hoverTop
              }
              GradientStop {
                position: 1
                color: detailRow.chosen ? (rowHover.hovered ? Aero.hoverSelectedBottom : Aero.selectionBottom) : Aero.hoverBottom
              }
            }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: 4

            Item {
              width: Math.floor(detailList.width * 0.42) - 4
              height: parent.height

              Files.ExplorerIcon {
                id: rowIcon
                width: 16
                height: 16
                kind: detailRow.modelData.entryKind || "file"
                dimmed: detailRow.modelData.hidden === true
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: 5
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: detailRow.modelData.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: detailRow.modelData.hidden === true ? Aero.textDisabled : Aero.textPrimary
                font.family: Aero.fontFamily
                font.pixelSize: 12
              }
            }

            Text {
              width: Math.floor(detailList.width * 0.24)
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: 4
              text: detailRow.modelData.modifiedText || ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            Text {
              width: Math.floor(detailList.width * 0.20)
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: 4
              text: detailRow.modelData.typeLabel || ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }

            Text {
              width: Math.floor(detailList.width * 0.14) - 10
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignRight
              text: detailRow.modelData.sizeText || ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: Aero.textPrimary
              font.family: Aero.fontFamily
              font.pixelSize: 12
            }
          }

          HoverHandler { id: rowHover }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: { root.forceActiveFocus(); root.select(detailRow.index) }
            onDoubleTapped: { root.select(detailRow.index); root.activated(detailRow.modelData) }
          }

          TapHandler {
            acceptedButtons: Qt.RightButton
            onSingleTapped: function (eventPoint) {
              root.select(detailRow.index)
              var mapped = detailRow.mapToItem(null, eventPoint.position.x, eventPoint.position.y)
              root.contextRequested(detailRow.modelData, mapped.x, mapped.y)
            }
          }

          Accessible.role: Accessible.ListItem
          Accessible.name: detailRow.modelData.title
          Accessible.description: (detailRow.modelData.typeLabel || "") + " " + (detailRow.modelData.modifiedText || "")
          Accessible.selected: detailRow.chosen
        }
      }
    }
  }

  Controls.ScrollView {
    anchors.fill: parent
    visible: root.mode === "icons" || root.mode === "list"
    clip: true
    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

    GridView {
      id: iconGrid
      model: root.items
      cellWidth: root.mode === "icons" ? Aero.tileWidth : Math.max(160, Math.floor(width / Math.max(1, Math.floor(width / 220))))
      cellHeight: root.mode === "icons" ? Aero.tileHeight : Aero.rowHeight
      flow: root.mode === "icons" ? GridView.FlowLeftToRight : GridView.FlowTopToBottom
      boundsBehavior: Flickable.StopAtBounds
      readonly property int columnCount: Math.max(1, Math.floor(width / cellWidth))

      delegate: Item {
        id: tile
        required property var modelData
        required property int index
        width: iconGrid.cellWidth
        height: iconGrid.cellHeight

        readonly property bool chosen: modelData.id === root.selectedId
        readonly property bool iconMode: root.mode === "icons"

        Rectangle {
          anchors.fill: parent
          anchors.margins: tile.iconMode ? 3 : 1
          radius: 3
          visible: tile.chosen || tileHover.hovered
          border.width: 1
          border.color: tile.chosen ? (tileHover.hovered ? Aero.hoverSelectedBorder : Aero.selectionBorder) : Aero.hoverBorder
          gradient: Gradient {
            GradientStop {
              position: 0
              color: tile.chosen ? (tileHover.hovered ? Aero.hoverSelectedTop : Aero.selectionTop) : Aero.hoverTop
            }
            GradientStop {
              position: 1
              color: tile.chosen ? (tileHover.hovered ? Aero.hoverSelectedBottom : Aero.selectionBottom) : Aero.hoverBottom
            }
          }
        }

        Files.ExplorerIcon {
          id: tileIcon
          width: tile.iconMode ? Aero.largeIcon : Aero.smallIcon
          height: width
          kind: tile.modelData.entryKind || "file"
          dimmed: tile.modelData.hidden === true
          x: tile.iconMode ? (tile.width - width) / 2 : 5
          y: tile.iconMode ? 8 : (tile.height - height) / 2
        }

        Text {
          anchors.top: tile.iconMode ? tileIcon.bottom : undefined
          anchors.topMargin: tile.iconMode ? 5 : 0
          anchors.left: tile.iconMode ? parent.left : tileIcon.right
          anchors.leftMargin: tile.iconMode ? 5 : 5
          anchors.right: parent.right
          anchors.rightMargin: 5
          anchors.verticalCenter: tile.iconMode ? undefined : parent.verticalCenter
          text: tile.modelData.title
          textFormat: Text.PlainText
          horizontalAlignment: tile.iconMode ? Text.AlignHCenter : Text.AlignLeft
          wrapMode: tile.iconMode ? Text.Wrap : Text.NoWrap
          maximumLineCount: tile.iconMode ? 2 : 1
          elide: Text.ElideRight
          color: tile.modelData.hidden === true ? Aero.textDisabled : Aero.textPrimary
          font.family: Aero.fontFamily
          font.pixelSize: 12
        }

        HoverHandler { id: tileHover }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onSingleTapped: { root.forceActiveFocus(); root.select(tile.index) }
          onDoubleTapped: { root.select(tile.index); root.activated(tile.modelData) }
        }

        TapHandler {
          acceptedButtons: Qt.RightButton
          onSingleTapped: function (eventPoint) {
            root.select(tile.index)
            var mapped = tile.mapToItem(null, eventPoint.position.x, eventPoint.position.y)
            root.contextRequested(tile.modelData, mapped.x, mapped.y)
          }
        }

        Accessible.role: Accessible.ListItem
        Accessible.name: tile.modelData.title
        Accessible.selected: tile.chosen
      }
    }
  }
}
