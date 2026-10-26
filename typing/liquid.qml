import QtQuick

// Liquid: the logo fills like a tank. The lit logo rises from the bottom to
// the charge level under a wavy surface with an accent meniscus. Keystrokes
// raise or lower the level on a soft spring and slosh the surface; idle, it
// settles flat and stops. Submit floods to the top with a ripple; failure
// drains it in a swirl. Reduced motion: a flat surface with plain fades.
// The surface is drawn by liquid.frag (compiled to liquid.frag.qsb).
Item {
  id: root

  property Item source
  property rect inkRect
  property real level: 0
  property int typedLength: 0
  property bool holding: false
  property bool reducedMotion: false
  property color accent
  property color logoColor
  property color errorColor

  readonly property real baseOpacity: 0.22
  readonly property real glowLevel: Math.max(0, Math.min(1, levelFrom + (shown - levelFrom) * xf)) * 0.9
  readonly property bool busy: frames.running

  // Simulation state. Lengths are in pixels, times in seconds.
  property string mode: "type"     // "type", "submit", "fail"
  property real shown: 0           // drawn level
  property real vel: 0
  property real amp: 0             // wave amplitude
  property real phase: 0
  property real tilt: 0            // surface slope (slosh)
  property real tiltVel: 0
  property real glint: 0.85        // meniscus strength
  property real ripple: 0
  property real from: 0            // level at the start of a timed phase
  property real fromTilt: 0
  property real clock: 0           // time in the current timed phase
  property real sinceKey: 99
  property real levelFrom: 0       // reduced motion cross-fade
  property real xf: 1
  property bool draining: false

  readonly property real inkH: Math.max(1, inkRect.height)
  readonly property real typingAmp: inkH * 0.014
  // Slope that tips the surface edges by about half the ink height.
  readonly property real aspect: inkH / Math.max(1, inkRect.width)

  function wake() { frames.running = true }

  function keystroke(length, delta) {
    if (mode !== "type") { mode = "type"; draining = false }
    sinceKey = 0
    if (reducedMotion) { crossfade(level); return }
    // Slosh: kick the wave and tip the surface, alternating sides.
    var up = delta > 0
    amp = Math.min(inkH * 0.075, amp + inkH * (up ? 0.032 : 0.022) * (delta < -1 ? 1.6 : 1))
    tiltVel += (length % 2 ? 1 : -1) * aspect * (up ? 1.0 : 0.7) * (delta < -1 ? 1.5 : 1)
    vel += up ? 0.35 : -0.2
    wake()
  }

  function submit() {
    mode = "submit"
    draining = false
    from = shown
    clock = 0
    if (reducedMotion) { crossfade(1); return }
    amp = Math.max(amp, inkH * 0.06)
    wake()
  }

  function fail() {
    mode = "fail"
    draining = true
    from = shown
    fromTilt = tilt
    clock = 0
    if (reducedMotion) { crossfade(0); return }
    wake()
  }

  function reset() {
    frames.running = false
    mode = "type"
    draining = false
    shown = level
    levelFrom = level
    xf = 1
    vel = 0; amp = 0; tilt = 0; tiltVel = 0; ripple = 0
    glint = 0.85
    sinceKey = 99
  }

  // Reduced motion: cross-fade from what is shown to a new level.
  function crossfade(to) {
    levelFrom = xf < 0.5 ? levelFrom : shown
    shown = to
    xf = 0
    clock = 0
    wake()
  }

  onLevelChanged: if (mode === "type" && !reducedMotion) wake()

  function step(dt) {
    dt = Math.min(dt, 1 / 30)
    clock += dt
    sinceKey += dt

    if (reducedMotion) {
      var dur = mode === "fail" ? 0.6 : mode === "submit" ? 0.25 : 0.18
      xf = Math.min(1, clock / dur)
      if (xf >= 1) {
        levelFrom = shown
        if (mode === "fail") { mode = "type"; draining = false }
        frames.running = false
      }
      return
    }

    var target = holding ? 1 : level
    if (mode === "type") {
      // Underdamped spring: a quick rise with a slight overshoot.
      var k = 150, c = 2 * 0.62 * Math.sqrt(k)
      vel += (k * (target - shown) - c * vel) * dt
      shown += vel * dt
    } else if (mode === "submit") {
      var p = Math.min(1, clock / 0.25)
      shown = from + (1 - from) * (1 - Math.pow(1 - p, 3))
      vel = 0
      ripple = clock < 0.18 ? 0 : Math.min(1, (clock - 0.18) / 0.75)
    } else if (mode === "fail") {
      // Drain: accelerating fall while the surface swirls side to side.
      var q = Math.min(1, clock / 0.6)
      shown = from * (1 - q * q * (3 - 2 * q))
      vel = 0
      var swirl = Math.sin(q * Math.PI * 3.2) * (1 - q) * 1.1
      tilt = fromTilt * (1 - q) + swirl * aspect
      tiltVel = 0
      amp = inkH * 0.09 * Math.sin(Math.PI * Math.min(1, q * 1.4)) * (1 - q * 0.6)
      if (q >= 1) {
        mode = "type"; draining = false
        shown = 0; tilt = 0; amp = 0; ripple = 0
      }
    }

    // Surface: tilt is a damped oscillator; the wave relaxes to a gentle
    // ripple while typing and to flat once idle.
    if (mode !== "fail") {
      var calm = sinceKey > 1.2
      var tk = 60, tc = 2 * (calm ? 0.55 : 0.24) * Math.sqrt(tk)
      tiltVel += (-tk * tilt - tc * tiltVel) * dt
      tilt += tiltVel * dt
      var rest = sinceKey < 1.2 && mode === "type" ? typingAmp : 0
      amp += (rest - amp) * (1 - Math.exp(-dt * (amp > rest ? (calm ? 4.5 : 2.6) : 4)))
    }
    phase += dt * (2.6 + amp / inkH * 30)
    glint = (draining ? 1 : 0.85) + Math.min(0.15, amp / inkH * 3)

    // Settled: stop every frame driver.
    var done = mode === "type" && Math.abs(target - shown) < 0.0008 && Math.abs(vel) < 0.002
      && amp < 0.15 && Math.abs(tilt) * inkRect.width < 0.5 && Math.abs(tiltVel) * inkRect.width < 2 && sinceKey > 1.2
    var flooded = mode === "submit" && clock >= 0.95
    if (done || flooded) {
      if (done) { shown = target; vel = 0; amp = 0; tilt = 0; tiltVel = 0 }
      if (flooded) { shown = 1; ripple = 0; amp = 0; tilt = 0; tiltVel = 0 }
      frames.running = false
    }
  }

  FrameAnimation {
    id: frames
    running: false
    onTriggered: root.step(frameTime)
  }

  ShaderEffect {
    anchors.fill: parent
    property Item source: root.source
    property vector4d ink: Qt.vector4d(root.inkRect.x, root.inkRect.y, root.inkRect.width, root.inkRect.height)
    property color lineColor: root.draining ? root.errorColor : root.accent
    property point px: Qt.point(width, height)
    property real level: root.shown
    property real levelFrom: root.levelFrom
    property real xf: root.xf
    property real amp: root.amp
    property real phase: root.phase
    property real tilt: root.tilt
    property real glint: root.glint
    property real ripple: root.ripple
    property real lineW: Math.max(2, root.inkH * 0.03)
    fragmentShader: "liquid.frag.qsb"
  }
}
