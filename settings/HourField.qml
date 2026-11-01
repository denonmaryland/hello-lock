import QtQuick

// An hour of the day (0–23) for quiet hours: a caption above a small field
// with a ":00" suffix. Type a number, or use the arrow keys or the wheel.
Column {
  id: hour
  property string label: ""
  property int value: 0
  signal modified(int value)
  spacing: 6
  width: 120
  // Typing replaces the field's text binding, so keep it in step by hand.
  onValueChanged: if (hourInput.text === "" || Number(hourInput.text) !== value) hourInput.text = String(value)

  MonoText {
    text: hour.label
    tracking: 0.2
    size: 10
    color: Theme.a(Theme.muted, 0.75)
  }
  InputField {
    id: hourInput
    width: hour.width
    boxHeight: 38
    mono: true
    suffix: ":00"
    text: String(hour.value)
    maximumLength: 2
    inputMethodHints: Qt.ImhDigitsOnly
    validator: IntValidator { bottom: 0; top: 23 }
    onTextEdited: if (acceptableInput) hour.modified(Number(text))
    onEditingFinished: if (!acceptableInput || text !== String(hour.value)) text = String(hour.value)
    Keys.onUpPressed: hour.modified((hour.value + 1) % 24)
    Keys.onDownPressed: hour.modified((hour.value + 23) % 24)
    WheelHandler {
      onWheel: function(event) { hour.modified((hour.value + (event.angleDelta.y > 0 ? 1 : 23)) % 24) }
    }
  }
}
