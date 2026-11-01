import QtQuick

// The 36×20 switch: accent track and dark knob when on.
Rectangle {
  id: track
  property bool checked: false
  width: 36
  height: 20
  radius: 10
  color: checked ? Theme.accent : Theme.line
  Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  Rectangle {
    width: 16
    height: 16
    radius: 8
    y: 2
    x: track.checked ? 18 : 2
    color: track.checked ? Theme.deepest : Theme.muted
    Behavior on x { enabled: !Theme.calm; NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  }
}
