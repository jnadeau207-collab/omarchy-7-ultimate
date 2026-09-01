import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

import "SetupModel.js" as SetupModel

Item {
  id: root

  property var host: null
  property var controller: null
  property var queryState: SetupModel.baseState(SetupModel.OVERVIEW_ROUTE, {}, "offline")
  readonly property var productProfile: host && host.productProfile ? host.productProfile : null

  readonly property var steps: host && host.routeCatalog && Array.isArray(host.routeCatalog.routes)
    ? host.routeCatalog.routes : []
  readonly property string currentRouteId: host ? String(host.currentRoute || "") : ""
  readonly property int stepIndex: indexOfRoute(currentRouteId)
  readonly property var currentRoute: host ? host.routeById(currentRouteId) : null
  readonly property bool providerStep: queryState.query && queryState.query.providerId !== ""
  readonly property bool queryBusy: queryState.phase === "catalog-loading" || queryState.phase === "loading"
  readonly property bool lastStep: stepIndex >= 0 && stepIndex === steps.length - 1
  readonly property bool firstStep: stepIndex <= 0

  focus: true

  function indexOfRoute(routeId) {
    for (var i = 0; i < steps.length; i++) if (steps[i].id === routeId) return i
    return -1
  }

  function goTo(offset) {
    var next = stepIndex + offset
    if (next < 0 || next >= steps.length || !host) return
    host.navigate(steps[next].id, {})
  }

  function ensureController() {
    if (controller) return
    controller = SetupModel.createController({
      send: function(method, parameters) {
        return root.host ? root.host.requestFabric(method, parameters) : ""
      },
      cancel: function(requestId) {
        if (!root.host || typeof root.host.cancelFabric !== "function") return false
        return root.host.cancelFabric(requestId)
      },
      onState: function(state) { root.queryState = state }
    })
  }

  function synchronizeHost() {
    ensureController()
    if (!host) return
    controller.activate(currentRouteId || SetupModel.OVERVIEW_ROUTE, {})
    controller.setConnected(host.fabricReady)
  }

  onHostChanged: synchronizeHost()
  Component.onCompleted: ensureController()

  Connections {
    target: root.host
    enabled: root.host !== null
    function onFabricConnectionReady(hello) { root.ensureController(); root.controller.setConnected(true) }
    function onFabricReadyChanged() { root.ensureController(); root.controller.setConnected(root.host.fabricReady) }
    function onRouteActivated(routeId, routeArguments, context) { root.ensureController(); root.controller.activate(routeId, {}) }
    function onFabricResult(requestId, result) { if (root.controller) root.controller.receiveResult(requestId, result) }
    function onFabricFailure(requestId, error) { if (root.controller) root.controller.receiveFailure(requestId, error) }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      Layout.preferredWidth: Style.space(260)
      Layout.fillHeight: true
      color: Tokens.surface.base
      border.color: Tokens.accessibility.highContrast ? Tokens.border.strong : Tokens.border.subtle
      border.width: Tokens.accessibility.highContrast ? 2 : 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(20)
        spacing: Style.space(14)

        Text {
          text: Semantics.text(root.productProfile, "Set up this computer")
          color: Tokens.text.primary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.Wrap
          Layout.fillWidth: true
        }

        Text {
          text: Semantics.text(root.productProfile, "Step") + " " + (root.stepIndex + 1) + " " +
            Semantics.text(root.productProfile, "of") + " " + root.steps.length
          color: Tokens.text.secondary
          font.family: Tokens.typography.family
          font.pixelSize: Style.font.bodySmall
          Layout.fillWidth: true
        }

        Ui.ProgressBar {
          value: root.steps.length > 0 ? (root.stepIndex + 1) / root.steps.length : 0
          Layout.fillWidth: true
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(8)
          spacing: Style.space(2)

          Repeater {
            model: root.steps
            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool active: index === root.stepIndex
              readonly property bool done: index < root.stepIndex
              Layout.fillWidth: true
              implicitHeight: stepLabel.implicitHeight + Style.space(14)
              radius: Tokens.radius.small
              color: active ? Tokens.chrome.active : "transparent"

              Text {
                id: stepLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                text: Semantics.text(root.productProfile, modelData.title)
                color: active ? Tokens.text.primary : done ? Tokens.text.secondary : Tokens.text.disabled
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.body
                font.bold: active
                elide: Text.ElideRight
              }
            }
          }
        }

        Item { Layout.fillHeight: true }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.margins: Style.space(28)
      spacing: Style.space(16)

      Text {
        text: Semantics.text(root.productProfile, root.currentRoute ? root.currentRoute.title : "Setup")
        color: Tokens.text.primary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }

      Text {
        text: Semantics.text(root.productProfile, root.currentRoute ? root.currentRoute.description : "")
        color: Tokens.text.secondary
        font.family: Tokens.typography.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }

      Ui.Card {
        visible: root.providerStep
        Layout.fillWidth: true
        implicitHeight: providerColumn.implicitHeight + Style.space(32)

        ColumnLayout {
          id: providerColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(16)
          spacing: Style.space(6)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: Semantics.text(root.productProfile, "What this computer reports")
              color: Tokens.text.primary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              Layout.fillWidth: true
            }

            Ui.Badge {
              text: root.queryBusy ? "READING" : SetupModel.phaseBadge(root.queryState)
              tone: root.queryBusy ? "info" : SetupModel.phaseTone(root.queryState)
            }
          }

          Text {
            textFormat: Text.PlainText
            text: Semantics.text(root.productProfile, SetupModel.stateExplanation(root.queryState))
            color: Tokens.text.secondary
            font.family: Tokens.typography.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.queryState.totalRecords > 0
            text: root.queryState.totalRecords + " " +
              Semantics.text(root.productProfile, "records reported by this provider")
            color: Tokens.text.primary
            font.family: Tokens.typography.family
            font.pixelSize: Style.font.body
            Layout.fillWidth: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.queryState.query && root.queryState.query.coverage !== ""
            text: Semantics.text(root.productProfile, root.queryState.query ? root.queryState.query.coverage : "")
            color: Tokens.text.disabled
            font.family: Tokens.typography.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
        }
      }

      Repeater {
        model: root.providerStep ? root.queryState.records : []

        Ui.Card {
          required property var modelData
          Layout.fillWidth: true
          implicitHeight: recordColumn.implicitHeight + Style.space(32)

          ColumnLayout {
            id: recordColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(16)
            spacing: Style.space(4)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: modelData.label
                color: Tokens.text.primary
                font.family: Tokens.typography.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Ui.Badge {
                visible: modelData.status !== ""
                text: modelData.status
                tone: "info"
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: modelData.subtitle !== "" && modelData.subtitle !== modelData.label
              text: modelData.subtitle
              color: Tokens.text.secondary
              font.family: Tokens.typography.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }

            Repeater {
              model: modelData.details

              RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: Tokens.text.secondary
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  Layout.preferredWidth: Style.space(140)
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.value
                  color: Tokens.text.disabled
                  font.family: Tokens.typography.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }
              }
            }
          }
        }
      }

      Ui.EmptyState {
        visible: !root.providerStep
        semanticProfile: root.productProfile
        Layout.fillWidth: true
        title: Semantics.text(root.productProfile, "Nothing to configure here yet")
        message: Semantics.text(root.productProfile,
          "This step has no registered provider, so setup states what ships rather than reading live state.")
      }

      Item { Layout.fillHeight: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Ui.Button {
          text: Semantics.text(root.productProfile, "Back")
          enabled: !root.firstStep
          onClicked: root.goTo(-1)
        }

        Item { Layout.fillWidth: true }

        Ui.Button {
          text: root.lastStep
            ? Semantics.text(root.productProfile, "Finish")
            : Semantics.text(root.productProfile, "Next")
          enabled: !root.lastStep
          onClicked: root.goTo(1)
        }
      }
    }
  }
}
