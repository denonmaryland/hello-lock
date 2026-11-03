pragma Singleton
import QtQuick
import "../platform"
import "../platform" as Commons

// The Settings window's palette, type and motion. Every colour comes from the
// Omarchy theme: the foundational roles directly, the surfaces and greys mixed
// from background and foreground, so dark and light themes both work. On a
// dark theme the window sits a step below the background, the rail and the
// stage further down; on a light one they step towards the foreground.
// Settings.qml binds `calm` (reduced motion: plain fades only).
QtObject {
  id: theme

  readonly property color fg: Commons.Color.foreground
  readonly property color ground: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color alert: Commons.Color.urgent
  readonly property color lockText: Commons.Color.lock.text
  readonly property bool dark: luma(ground) < 0.45

  readonly property color deep: dark ? Qt.darker(ground, 1.32) : mix(ground, fg, 0.035)
  readonly property color rail: dark ? Qt.darker(ground, 1.5) : mix(ground, fg, 0.05)
  readonly property color deepest: dark ? Qt.darker(ground, 2) : mix(ground, fg, 0.075)
  // Hairlines and inactive tracks: whichever of a lifted background or a
  // light foreground mix stands out more.
  readonly property color line: {
    var lifted = Qt.lighter(ground, 1.7), mixed = mix(ground, fg, 0.14)
    return dark && luma(lifted) > luma(mixed) ? lifted : mixed
  }
  readonly property color muted: mix(ground, fg, 0.58)
  // The rare gold unlock, as UnlockSplash draws it (nudged towards the accent).
  readonly property color gold: Qt.tint("#E8C26A", a(accent, 0.22))

  readonly property string uiFont: Style.font.family
  readonly property string mono: "Share Tech Mono"
  readonly property string display: "Oxanium"

  property bool calm: false
  // UI state changes run 120–260 ms: ease-out on the way in, ease-in out.
  readonly property int fastMs: 120
  readonly property int uiMs: 180
  readonly property int slowMs: 260
  readonly property var easeOut: [0.22, 0.8, 0.24, 1, 1, 1]
  readonly property var easeIn: [0.5, 0, 0.84, 0.3, 1, 1]
  readonly property real pressScale: calm ? 1 : 0.97

  function a(c, alpha) { return Qt.rgba(c.r, c.g, c.b, alpha) }
  function mix(x, y, t) {
    return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t)
  }
  function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

  // Timeline helpers for the stage previews: progress of t through [from, to],
  // and the cubic curves the motion tokens use.
  function seg(t, from, to) { return to <= from ? (t >= to ? 1 : 0) : Math.max(0, Math.min(1, (t - from) / (to - from))) }
  function outCubic(x) { return 1 - Math.pow(1 - x, 3) }
  function inCubic(x) { return x * x * x }

  function fileUrl(path, version) {
    if (!path) return ""
    path = String(path)
    if (path.indexOf("data:image/svg+xml,") === 0) return path
    return "file://" + path.split("/").map(encodeURIComponent).join("/") + "?v=" + (version || 0)
  }
}
