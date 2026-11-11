import QtQuick
import QtQuick.Controls as QQC
import "../platform"
import "../platform/SafeTyping.js" as SafeTyping

// A text field on the deepest surface; focus draws the accent border and a
// soft 3 px ring. `mono` sets it in Share Tech Mono with `tracking` (em);
// `suffix` is a hint drawn at the right edge (e.g. "+ ONLINE").
// Read-only to Qt for good: a writable field reads the whole clipboard in the
// shell on every clipboard change. Typing and a bounded paste come from
// platform/SafeTyping.js and SafePaste.qml; `enabled` still turns it off.
QQC.TextField {
  id: field
  readOnly: true
  cursorVisible: activeFocus
  Keys.onPressed: (event) => { if (field.enabled) SafeTyping.key(field, event, paste) }
  property bool mono: false
  property real tracking: 0
  property string suffix: ""
  property int boxHeight: 42
  property real size: mono ? 16 : 15
  readonly property bool hot: hovered || activeFocus

  implicitHeight: boxHeight
  leftPadding: 14
  rightPadding: 14 + (suffix ? suffixText.implicitWidth + 10 : 0)
  topPadding: 0
  bottomPadding: 0
  verticalAlignment: TextInput.AlignVCenter
  color: enabled ? Theme.fg : Theme.a(Theme.muted, 0.6)
  placeholderTextColor: Theme.a(Theme.muted, 0.6)
  selectionColor: Theme.a(Theme.accent, 0.35)
  selectedTextColor: Theme.fg
  font.family: mono ? Theme.mono : Theme.uiFont
  font.pixelSize: size
  font.weight: mono ? Font.Normal : Font.Medium
  font.letterSpacing: size * tracking
  opacity: enabled ? 1 : 0.55

  SafePaste { id: paste }

  background: Rectangle {
    radius: 8
    color: Theme.deepest
    border.width: 1
    border.color: field.activeFocus ? Theme.accent
      : field.hovered ? Theme.mix(Theme.line, Theme.fg, 0.22) : Theme.a(Theme.line, 0.6)
    Behavior on border.color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    Rectangle {
      anchors.fill: parent
      anchors.margins: -3
      radius: 11
      color: "transparent"
      border.width: 3
      border.color: Theme.a(Theme.accent, 0.12)
      opacity: field.activeFocus ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    }
    MonoText {
      id: suffixText
      visible: field.suffix !== ""
      anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
      text: field.suffix
      tracking: 0.18
      size: 11
      color: Theme.a(Theme.muted, 0.6)
    }
  }
}
