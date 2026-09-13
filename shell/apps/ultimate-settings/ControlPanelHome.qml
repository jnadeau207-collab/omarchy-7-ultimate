import QtQuick
import qs.Commons

import "../ultimate-files/ExplorerTheme.js" as Aero

Item {
  id: root

  property var productProfile: null
  property string viewBy: "category"

  signal categoryActivated(string routeId)

  readonly property var categories: [
    {
      title: "System and Security",
      icon: "shield",
      tasks: [
        { label: "Review your computer's status", routeId: "settings.system.overview" },
        { label: "Back up your computer", routeId: "settings.recovery.overview" },
        { label: "Find and fix problems", routeId: "settings.update.overview" }
      ]
    },
    {
      title: "Network and Internet",
      icon: "network",
      tasks: [
        { label: "View network status and tasks", routeId: "settings.network.overview" },
        { label: "Connect to a network", routeId: "settings.network.overview" }
      ]
    },
    {
      title: "Hardware and Sound",
      icon: "hardware",
      tasks: [
        { label: "View devices and printers", routeId: "settings.printers.overview" },
        { label: "Add a device", routeId: "settings.bluetooth.overview" },
        { label: "Adjust commonly used moving settings", routeId: "settings.audio.overview" }
      ]
    },
    {
      title: "Programs",
      icon: "programs",
      tasks: [
        { label: "Uninstall a program", routeId: "settings.apps.overview" },
        { label: "Change default programs", routeId: "settings.apps.default-programs" }
      ]
    },
    {
      title: "User Accounts and Family Safety",
      icon: "users",
      tasks: [
        { label: "Add or remove user accounts", routeId: "settings.system.overview" },
        { label: "Set up parental controls", routeId: "settings.system.overview" }
      ]
    },
    {
      title: "Appearance and Personalization",
      icon: "appearance",
      tasks: [
        { label: "Change the theme", routeId: "settings.personalization.overview" },
        { label: "Change desktop background", routeId: "settings.personalization.overview" },
        { label: "Adjust screen resolution", routeId: "settings.display.overview" }
      ]
    },
    {
      title: "Clock, Language, and Region",
      icon: "clock",
      tasks: [
        { label: "Change keyboards or other input methods", routeId: "settings.input.overview" }
      ]
    },
    {
      title: "Ease of Access",
      icon: "ease",
      tasks: [
        { label: "Let Windows suggest settings", routeId: "settings.accessibility.overview" },
        { label: "Optimize visual display", routeId: "settings.accessibility.overview" }
      ]
    }
  ]

  Item {
    id: pageHeader
    width: parent.width
    height: 36

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: Semantics.text(root.productProfile, "Adjust your computer's settings")
      textFormat: Text.PlainText
      color: Aero.headingText
      font.family: Aero.fontFamily
      font.pixelSize: Aero.pageInstructionSize
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Semantics.text(root.productProfile, "View by:")
        textFormat: Text.PlainText
        color: Aero.textPrimary
        font.family: Aero.fontFamily
        font.pixelSize: Aero.fontSize
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Semantics.text(root.productProfile, "Category") + " ▾"
        textFormat: Text.PlainText
        color: Aero.linkText
        font.family: Aero.fontFamily
        font.pixelSize: Aero.fontSize
      }
    }
  }

  Grid {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: pageHeader.bottom
    anchors.topMargin: 8
    anchors.bottom: parent.bottom
    columns: width >= 640 ? 2 : 1
    columnSpacing: 24
    rowSpacing: 18

    Repeater {
      model: root.categories

      delegate: Item {
        required property var modelData
        width: parent.columns === 2 ? (parent.width - parent.columnSpacing) / 2 : parent.width
        height: categoryColumn.implicitHeight

        Canvas {
          id: categoryIcon
          width: 48
          height: 48
          anchors.left: parent.left
          anchors.top: parent.top
          antialiasing: true
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var kind = String(modelData.icon || "")
            var grad = ctx.createLinearGradient(0, 0, 0, height)
            if (kind === "shield") { grad.addColorStop(0, "#6db3ee"); grad.addColorStop(1, "#1f5fa8") }
            else if (kind === "network") { grad.addColorStop(0, "#dff0fb"); grad.addColorStop(1, "#7fb8e4") }
            else if (kind === "hardware") { grad.addColorStop(0, "#f6f8fa"); grad.addColorStop(1, "#c9d2db") }
            else if (kind === "programs") { grad.addColorStop(0, "#f4f7fb"); grad.addColorStop(1, "#9db3c6") }
            else if (kind === "users") { grad.addColorStop(0, "#d7e8f8"); grad.addColorStop(1, "#6ea0d0") }
            else if (kind === "appearance") { grad.addColorStop(0, "#e9eef4"); grad.addColorStop(1, "#b9c5d2") }
            else if (kind === "clock") { grad.addColorStop(0, "#ffffff"); grad.addColorStop(1, "#d5dde6") }
            else { grad.addColorStop(0, "#cfe4f7"); grad.addColorStop(1, "#8bb8de") }
            ctx.beginPath()
            if (kind === "shield") {
              ctx.moveTo(10, 4)
              ctx.lineTo(38, 4)
              ctx.lineTo(38, 26)
              ctx.quadraticCurveTo(24, 46, 10, 26)
              ctx.closePath()
            } else {
              ctx.arc(24, 24, 18, 0, Math.PI * 2)
            }
            ctx.fillStyle = grad
            ctx.fill()
            ctx.strokeStyle = Aero.driveOutline
            ctx.stroke()
          }
        }

        Column {
          id: categoryColumn
          anchors.left: categoryIcon.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: 2

          Text {
            width: parent.width
            text: Semantics.text(root.productProfile, modelData.title)
            textFormat: Text.PlainText
            color: Aero.headingText
            font.family: Aero.fontFamily
            font.pixelSize: 14
            wrapMode: Text.WordWrap

            HoverHandler { id: titleHover }
            TapHandler {
              onSingleTapped: {
                if (modelData.tasks && modelData.tasks.length > 0)
                  root.categoryActivated(String(modelData.tasks[0].routeId))
              }
            }
          }

          Repeater {
            model: modelData.tasks

            delegate: Text {
              required property var modelData
              width: categoryColumn.width
              text: Semantics.text(root.productProfile, modelData.label)
              textFormat: Text.PlainText
              color: taskHover.hovered ? Aero.linkHover : Aero.linkText
              font.family: Aero.fontFamily
              font.pixelSize: Aero.fontSize
              wrapMode: Text.WordWrap

              HoverHandler { id: taskHover }
              TapHandler { onSingleTapped: root.categoryActivated(String(modelData.routeId)) }

              Accessible.role: Accessible.Button
              Accessible.name: Semantics.text(root.productProfile, modelData.label)
            }
          }
        }
      }
    }
  }
}
