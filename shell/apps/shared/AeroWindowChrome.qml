import QtQuick
import qs.Commons

Item {
  id: root

  property var host: null
  property int frame: 6
  property int captionHeight: 30

  AeroGlassFill {
    anchors.fill: parent
    radius: 6
    drawBorder: true
  }

  MouseArea {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.captionHeight
    acceptedButtons: Qt.LeftButton
    onPressed: {
      var win = root.host ? root.host.window : null
      if (win && win.startSystemMove)
        win.startSystemMove()
    }
    onDoubleClicked: Util.execDetached(["omarchy-shell", "window", "toggleMaximize", "active"])
  }

  Rectangle {
    id: captionCluster
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.top: parent.top
    width: 29 + 29 + 48
    height: 19
    color: Qt.rgba(1, 1, 1, 0.20)
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.30)
    radius: 0

    Rectangle {
      width: parent.width
      height: 5
      anchors.bottom: parent.bottom
      color: "transparent"
      radius: 5
    }

    Row {
      anchors.fill: parent
      spacing: 0

      Item {
        width: 29
        height: 19

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.50) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.30) }
            GradientStop { position: 0.50; color: Qt.rgba(0, 0, 0, 0.10) }
            GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.10) }
            GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.50) }
          }
        }

        Rectangle {
          width: 1
          height: parent.height
          anchors.right: parent.right
          color: Qt.rgba(0, 0, 0, 0.30)
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 3
          text: "–"
          color: "#202020"
          font.pixelSize: 14
        }

        TapHandler {
          onSingleTapped: Util.execDetached(["omarchy-shell", "window", "minimize", "active"])
        }
      }

      Item {
        width: 29
        height: 19

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, 0.50) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.30) }
            GradientStop { position: 0.50; color: Qt.rgba(0, 0, 0, 0.10) }
            GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.10) }
            GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.50) }
          }
        }

        Rectangle {
          width: 1
          height: parent.height
          anchors.right: parent.right
          color: Qt.rgba(0, 0, 0, 0.30)
        }

        Text {
          anchors.centerIn: parent
          text: "□"
          color: "#202020"
          font.pixelSize: 11
        }

        TapHandler {
          onSingleTapped: Util.execDetached(["omarchy-shell", "window", "toggleMaximize", "active"])
        }
      }

      Item {
        width: 48
        height: 19

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.00; color: "#e0a197" }
            GradientStop { position: 0.25; color: "#cf796a" }
            GradientStop { position: 0.50; color: "#d54f36" }
            GradientStop { position: 1.00; color: "#d54f36" }
          }
        }

        Text {
          anchors.centerIn: parent
          text: "×"
          color: "#ffffff"
          font.pixelSize: 13
          font.bold: true
        }

        TapHandler {
          onSingleTapped: Util.execDetached(["omarchy-shell", "window", "close", "active"])
        }
      }
    }
  }
}
