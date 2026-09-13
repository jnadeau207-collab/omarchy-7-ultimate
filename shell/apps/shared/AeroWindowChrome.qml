import QtQuick
import qs.Commons

Item {
  id: root

  property var host: null
  property int frame: 6
  property int captionHeight: 30

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: Qt.rgba(0.271, 0.502, 0.769, 0.72)
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.70)
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: 5
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.55)
  }

  Rectangle {
    anchors.fill: parent
    radius: 6
    opacity: 0.45
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.40) }
      GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.10) }
      GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.20) }
    }
  }

  Rectangle {
    x: 2
    y: 11
    width: parent.width - 4
    height: 2
    color: Qt.rgba(1, 1, 1, 0.70)
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
          onSingleTapped: {
            if (root.host && root.host.window)
              root.host.window.minimized = true
          }
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
          onSingleTapped: {
            if (root.host && root.host.window)
              root.host.window.visible = false
            Qt.quit()
          }
        }
      }
    }
  }
}
