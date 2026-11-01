import QtQuick
import "Icons.js" as Icons

// A small caps tag beside a title ("IN USE", "SHOWN IN PREVIEW"), optionally
// with the eye icon. `strong` fills it with the accent.
Rectangle {
  id: tag
  property string text: ""
  property bool eye: false
  property bool neutral: false
  property bool strong: false
  property int size: 11
  implicitWidth: tagRow.implicitWidth + (eye ? 13 : 12)
  implicitHeight: size + 7
  radius: strong ? 4 : 5
  color: strong ? Theme.accent : neutral ? Theme.line : Theme.a(Theme.accent, 0.1)
  Row {
    id: tagRow
    x: 6
    anchors.verticalCenter: parent.verticalCenter
    spacing: 5
    Glyph {
      visible: tag.eye
      anchors.verticalCenter: parent.verticalCenter
      width: tag.size; height: tag.size
      path: Icons.eye
      strokeWidth: 2
      color: tag.neutral ? Theme.fg : Theme.accent
    }
    MonoText {
      anchors.verticalCenter: parent.verticalCenter
      text: tag.text
      tracking: tag.strong ? 0.14 : 0.08
      size: tag.size
      color: tag.strong ? Theme.deepest : tag.neutral ? Theme.fg : Theme.accent
    }
  }
}
