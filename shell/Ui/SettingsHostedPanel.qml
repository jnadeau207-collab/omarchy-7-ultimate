import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  property string sourcePath: ""

  QtObject {
    id: barStub
    property color foreground: Tokens.text.primary
    property color barForeground: Tokens.text.primary
    property color urgent: Tokens.state.danger
    property string fontFamily: Tokens.typography.family
    property string position: "bottom"
    property var shell: null
  }

  Loader {
    id: loader
    anchors.fill: parent
    source: root.sourcePath !== "" ? Quickshell.shellPath(root.sourcePath) : ""
    onLoaded: root.injectPanel()
  }

  function injectPanel() {
    var item = loader.item
    if (!item) return
    if ("embedMode" in item) item.embedMode = true
    if ("chromeVisible" in item) item.chromeVisible = false
    if ("manageIpc" in item) item.manageIpc = false
    if ("bar" in item) item.bar = barStub
  }

  Text {
    visible: loader.status === Loader.Error
    anchors.fill: parent
    anchors.margins: Style.space(16)
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: Tokens.state.danger
    font.family: Tokens.typography.family
    font.pixelSize: Style.font.body
    text: "This Settings page failed to load the live panel."
  }
}
