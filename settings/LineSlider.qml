import QtQuick

// A thin accent slider (0..1 by default). `moved` follows the drag;
// `released` fires once at the end of a drag or click, `stepped` after an
// arrow key (so a held key never repeats anything heavier than a save).
Item {
  id: slider
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property int knobSize: 14
  property bool interactive: true
  signal moved(real value)
  signal released(real value)
  signal stepped(real value)
  readonly property real fraction: maximum > minimum ? Math.max(0, Math.min(1, (value - minimum) / (maximum - minimum))) : 0

  implicitHeight: 20
  activeFocusOnTab: interactive
  function snap(v) {
    v = Math.max(minimum, Math.min(maximum, v))
    return step > 0 ? Math.round((v - minimum) / step) * step + minimum : v
  }
  Keys.onLeftPressed: { var v = snap(value - step); moved(v); stepped(v) }
  Keys.onRightPressed: { var v = snap(value + step); moved(v); stepped(v) }

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 3
    radius: 2
    color: Theme.a(Theme.line, 0.95)
  }
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(slider.knobSize / 2 + slider.fraction * (slider.width - slider.knobSize))
    height: 3
    radius: 2
    color: Theme.accent
  }
  Rectangle {
    x: slider.fraction * (slider.width - slider.knobSize)
    anchors.verticalCenter: parent.verticalCenter
    width: slider.knobSize
    height: slider.knobSize
    radius: slider.knobSize / 2
    color: Theme.fg
    border.width: 3
    border.color: Theme.a(Theme.accent, sliderMouse.pressed || slider.activeFocus ? 0.45 : 0.25)
    // The ring sits outside the knob in the design: grow the item instead.
    Rectangle {
      anchors.centerIn: parent
      width: parent.width - 6
      height: width
      radius: width / 2
      color: Theme.fg
    }
  }
  MouseArea {
    id: sliderMouse
    enabled: slider.interactive
    anchors.fill: parent
    anchors.margins: -6
    cursorShape: Qt.PointingHandCursor
    preventStealing: true
    function at(mx) { return slider.snap(slider.minimum + Math.max(0, Math.min(1, (mx - 6 - slider.knobSize / 2) / (slider.width - slider.knobSize))) * (slider.maximum - slider.minimum)) }
    onPressed: function(mouse) { slider.forceActiveFocus(); slider.moved(at(mouse.x)) }
    onPositionChanged: function(mouse) { if (pressed) slider.moved(at(mouse.x)) }
    onReleased: function(mouse) { slider.released(at(mouse.x)) }
  }
}
