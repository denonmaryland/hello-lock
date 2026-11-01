import QtQuick

// A one-letter key (A, B, C) tying a field to its annotation on the stage.
Rectangle {
  property string letter: ""
  property bool lit: true
  width: 16
  height: 16
  radius: 4
  color: Theme.a(Theme.deepest, 0.8)
  border.width: 1
  border.color: lit ? Theme.a(Theme.accent, 0.55) : Theme.line
  Behavior on border.color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  MonoText {
    anchors.centerIn: parent
    text: parent.letter
    color: parent.lit ? Theme.accent : Theme.muted
    size: 10
  }
}
