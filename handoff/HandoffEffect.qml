import QtQuick

// Shared plumbing for the logo handoff transitions (see README.md). Each
// transition is a HandoffEffect with a `timeline` and pieces that draw the
// logo; the host fills it to the splash window.
Item {
  id: root

  // Set by the host.
  property Item source: null
  property rect sourceRect: Qt.rect(0, 0, 0, 0)
  property color accent: "white"
  property color logoColor: "white"
  property color alertColor: "red"
  property color backgroundColor: "black"

  // The symbol's entrance, read by the host: scale, offset (fractions of the
  // symbol's size) and a turn about the vertical axis (degrees).
  property real emergeScale: 1
  property real emergeX: 0
  property real emergeY: 0
  property real emergeTurn: 0

  // Drawing only between play() and reset(); t is a 0..1 progress most
  // transitions drive their pieces from.
  property bool active: false
  property real t: 0
  property Animation timeline: null
  readonly property bool busy: timeline !== null && timeline.running

  readonly property real cx: sourceRect.x + sourceRect.width / 2
  readonly property real cy: sourceRect.y + sourceRect.height / 2

  // Extra state of a transition goes back to rest here.
  signal resetting()

  function play() {
    reset()
    active = true
    if (timeline) timeline.restart()
  }

  function stop() {
    if (timeline) timeline.stop()
  }

  function reset() {
    stop()
    active = false
    t = 0
    emergeScale = 1; emergeX = 0; emergeY = 0; emergeTurn = 0
    resetting()
  }

  // Deterministic per-piece pseudo-random in 0..1.
  function prand(i, k) {
    var x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return x - Math.floor(x)
  }

  function clamp01(x) { return Math.max(0, Math.min(1, x)) }
  function easeOut(x) { var p = clamp01(x); return 1 - Math.pow(1 - p, 3) }
}
