import QtQuick

// A setting with a title, a description and a switch; the whole row toggles.
// It reaches 12 px into the column's margins so its text lines up with the
// fields around it, and lights up on hover. `tag` adds an accent tag after
// the title (e.g. what the stage is showing for it).
Rectangle {
  id: row
  property string title: ""
  property string description: ""
  property string tag: ""
  property bool tagEye: true
  property bool checked: false
  property bool lit: false
  readonly property bool hovered: rowMouse.containsMouse
  signal toggled()

  x: -12
  width: parent ? parent.width + 24 : 0
  implicitHeight: textColumn.implicitHeight + 20
  radius: 10
  color: hovered || lit ? Theme.a(Theme.line, 0.34) : "transparent"
  border.width: hovered || lit || activeFocus ? 1 : 0
  border.color: activeFocus ? Theme.a(Theme.accent, 0.7) : Theme.a(Theme.accent, 0.22)
  opacity: enabled ? 1 : 0.45
  activeFocusOnTab: true
  Keys.onSpacePressed: row.toggled()
  Keys.onReturnPressed: row.toggled()
  Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }

  Column {
    id: textColumn
    x: 12
    y: 10
    width: row.width - 24 - 36 - 16
    spacing: 3
    Row {
      spacing: 10
      UiText {
        anchors.verticalCenter: parent.verticalCenter
        text: row.title
        font.pixelSize: 14
        font.weight: Font.Medium
      }
      Tag {
        visible: row.tag !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: row.tag
        eye: row.tagEye
      }
    }
    UiText {
      visible: row.description !== ""
      width: parent.width
      wrapMode: Text.WordWrap
      text: row.description
      color: Theme.muted
      lineHeight: 18
      lineHeightMode: Text.FixedHeight
    }
  }
  SwitchTrack {
    x: row.width - 12 - width
    y: 10
    checked: row.checked
  }
  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.toggled()
  }
}
