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

  // Shared timing, so every transition hands over with the same feel. The
  // logo leaves on exitCurve (gathering speed, yet moving from the first
  // frame) over exitDuration and fades over fadeDuration on moveCurve; the
  // symbol arrives on emergeCurve (fast, then a long gentle settle) over
  // emergeDuration. moveCurve also suits neutral sweeps. Cubic béziers as
  // Easing.BezierSpline takes them (easing.bezierCurve).
  readonly property var exitCurve: [0.4, 0.1, 0.85, 0.4, 1, 1]
  readonly property var emergeCurve: [0.2, 0.6, 0.35, 1, 1, 1]
  readonly property var moveCurve: [0.42, 0.12, 0.4, 1, 1, 1]
  readonly property int exitDuration: 620
  readonly property int fadeDuration: 520
  readonly property int emergeDuration: 760

  function clamp01(x) { return Math.max(0, Math.min(1, x)) }

  // One of the curves above at progress x (clamped), for pieces driven from t.
  function ease(curve, x) {
    var p = clamp01(x)
    if (p <= 0 || p >= 1) return p
    // x(s) rises monotonically, so bisect for s, then read y(s).
    var lo = 0, hi = 1, s = p
    for (var i = 0; i < 20; i++) {
      s = (lo + hi) / 2
      var bx = 3 * (1 - s) * (1 - s) * s * curve[0] + 3 * (1 - s) * s * s * curve[2] + s * s * s
      if (bx < p) lo = s; else hi = s
    }
    return 3 * (1 - s) * (1 - s) * s * curve[1] + 3 * (1 - s) * s * s * curve[3] + s * s * s
  }
  function easeIn(x) { return ease(exitCurve, x) }
  function easeOut(x) { return ease(emergeCurve, x) }
  function easeInOut(x) { return ease(moveCurve, x) }
}
