import QtQuick

// Buttons. kind: "primary" (accent tint, the stage's play actions),
// "outline", "solid" (line fill) or "ghost" (text only). `active` lights an
// outline button for a toggled state; `iconOnly` makes a square icon button.
Rectangle {
  id: button
  property string text: ""
  property string icon: ""
  property bool iconFilled: false
  property string kind: "outline"
  property bool active: false
  property bool alertTone: false
  property bool iconOnly: false
  property int fontSize: 13
  property int padding: 12
  signal clicked()

  readonly property bool primary: kind === "primary" || active
  readonly property color tone: alertTone ? Theme.alert : Theme.accent
  readonly property color ink: primary ? tone : kind === "ghost" ? Theme.muted : Theme.fg
  implicitWidth: iconOnly ? implicitHeight : buttonRow.implicitWidth + padding * 2 + (icon && text ? 2 : 0)
  implicitHeight: 32
  radius: 8
  color: primary ? Theme.a(tone, buttonMouse.containsMouse ? 0.2 : 0.14)
    : kind === "solid" ? (buttonMouse.containsMouse ? Theme.mix(Theme.line, Theme.fg, 0.08) : Theme.line)
    : buttonMouse.containsMouse ? Theme.a(Theme.line, 0.35) : "transparent"
  border.width: kind === "ghost" && !activeFocus ? 0 : 1
  border.color: activeFocus ? Theme.accent : primary ? Theme.a(tone, 0.7) : kind === "solid" ? Theme.line : Theme.a(Theme.line, 0.95)
  opacity: enabled ? 1 : 0.4
  scale: buttonMouse.pressed ? Theme.pressScale : 1
  activeFocusOnTab: enabled
  Keys.onSpacePressed: button.clicked()
  Keys.onReturnPressed: button.clicked()
  Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }

  Row {
    id: buttonRow
    anchors.centerIn: parent
    spacing: 8
    Glyph {
      visible: button.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: button.iconFilled ? 12 : 13
      height: width
      path: button.icon
      filled: button.iconFilled
      strokeWidth: 2
      color: button.ink
    }
    UiText {
      visible: !button.iconOnly && button.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: button.text
      font.pixelSize: button.fontSize
      font.weight: button.primary ? Font.DemiBold : Font.Medium
      color: button.ink
    }
  }
  MouseArea {
    id: buttonMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (button.enabled) button.clicked()
  }
}
