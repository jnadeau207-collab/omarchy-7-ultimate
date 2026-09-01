import QtQuick
import qs.Commons

Text {
  id: root

  property color foreground: Tokens.text.primary
  property string fontFamily: Tokens.typography.family
  property real fontSize: Style.font.caption

  textFormat: Text.PlainText
  color: Qt.darker(foreground, 1.4)
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true

  topPadding: Math.ceil(fontSize * 0.15)
}
