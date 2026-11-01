import QtQuick

// A selectable chip (transitions, typing sounds, wordmark styles). Selected
// chips take the accent; `neutral` chips select in the line colour instead.
Rectangle {
  id: chip
  property string text: ""
  property string icon: ""
  property bool selected: false
  property bool neutral: false
  property int fontSize: 12
  signal clicked()
  implicitWidth: chipRow.implicitWidth + 20
  implicitHeight: 28
  radius: 6
  color: selected ? (neutral ? Theme.a(Theme.line, 0.6) : Theme.a(Theme.accent, 0.12))
    : chipMouse.containsMouse ? Theme.a(Theme.line, 0.3) : "transparent"
  border.width: 1
  border.color: activeFocus ? Theme.accent : selected ? (neutral ? Theme.line : Theme.accent) : Theme.a(Theme.line, 0.7)
  opacity: enabled ? 1 : 0.45
  scale: chipMouse.pressed ? Theme.pressScale : 1
  activeFocusOnTab: true
  Keys.onSpacePressed: chip.clicked()
  Keys.onReturnPressed: chip.clicked()
  Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }

  Row {
    id: chipRow
    anchors.centerIn: parent
    spacing: 6
    Glyph {
      visible: chip.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: 12; height: 12
      path: chip.icon
      strokeWidth: 2
      color: chipLabel.color
    }
    UiText {
      id: chipLabel
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, chip.width - 10 - (chip.icon ? 18 : 0))
      elide: Text.ElideRight
      text: chip.text
      font.pixelSize: chip.fontSize
      font.weight: chip.selected ? Font.DemiBold : Font.Medium
      color: chip.selected ? (chip.neutral ? Theme.fg : Theme.accent) : Theme.muted
      Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    }
  }
  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}
