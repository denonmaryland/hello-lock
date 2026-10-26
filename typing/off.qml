import QtQuick

// No typing effect: the plain logo, like the stock lock screen.
Item {
  property Item source
  property rect inkRect
  property real level: 0
  property int typedLength: 0
  property bool holding: false
  property bool reducedMotion: false
  property color accent
  property color logoColor
  property color errorColor

  readonly property real baseOpacity: 1
  readonly property real glowLevel: 0
  readonly property bool busy: false

  function keystroke(length, delta) {}
  function submit() {}
  function fail() {}
  function reset() {}
}
