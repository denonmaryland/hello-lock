import QtQuick
import QtQuick.Effects

// Equalizer: the logo is lit by vertical bars rising from the bottom like an
// audio level meter. The skyline tracks the charge level; each keystroke
// kicks a few columns up, leaving accent peak caps that hold, then fall back
// slowly. Idle, the bars rest as a steady, slightly uneven skyline and
// nothing runs. Submit slams every bar to the top; failure drops the bars in
// a fast cascade, the caps last. Reduced motion: even bars with plain fades.
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
  readonly property real glowLevel: Math.max(0, Math.min(1, meanHeight)) * 0.9
  readonly property bool busy: frames.running

  // Columns: about inkRect.width / 24 wide, a 1–2 px gap between them.
  readonly property int columns: 24
  readonly property real pitch: inkRect.width / columns
  readonly property real gap: Math.max(1, Math.min(1.5, pitch * 0.08))
  readonly property real inkH: Math.max(1, inkRect.height)
  readonly property real capH: Math.max(2, Math.min(5, inkH * 0.035))

  // Simulation state, one entry per column. Heights are 0..1 of inkRect.
  property var h: []
  property var v: []
  property var cap: []
  property var capV: []
  property var capHold: []
  property real meanHeight: 0
  property string mode: "type"    // "type", "submit", "fail"
  property real clock: 0           // time in the current timed phase, s
  property real now: 0
  property real sinceKey: 99
  property real slam: 0            // accent flash of the caps on submit
  property bool failing: false
  // Reduced motion cross-fade between two even levels.
  property real fadeFrom: 0
  property real fadeTo: 0
  property real fadeT: 1
  // Gap fill: the whole logo once submitted.
  property real fullness: 0

  // A fixed, slightly uneven skyline: -1..1 per column.
  function skew(i) {
    var s = Math.sin((i + 1) * 12.9898) * 43758.5453
    return (s - Math.floor(s)) * 2 - 1
  }

  function restingHeight(i, l) {
    var room = Math.min(1, l * 4) * Math.min(1, (1 - l) * 4)
    return Math.max(0, Math.min(1, l + skew(i) * 0.075 * room))
  }

  function ensure() {
    if (h.length === columns) return
    h = []; v = []; cap = []; capV = []; capHold = []
    for (var i = 0; i < columns; i++) {
      h.push(0); v.push(0); cap.push(0); capV.push(0); capHold.push(0)
    }
  }

  function wake() { ensure(); frames.running = true }

  function keystroke(length, delta) {
    ensure()
    if (mode !== "type") { mode = "type"; failing = false }
    sinceKey = 0
    if (reducedMotion) { crossfade(level); return }
    if (delta > 0) {
      // Kick three to five random columns, nudging their neighbours.
      var n = 3 + Math.floor(Math.random() * 3)
      for (var k = 0; k < n; k++) {
        var c = Math.floor(Math.random() * columns)
        var up = 1.6 + Math.random() * 2.2
        v[c] += up
        if (c > 0) v[c - 1] += up * 0.35
        if (c < columns - 1) v[c + 1] += up * 0.35
      }
    }
    wake()
  }

  function submit() {
    ensure()
    mode = "submit"
    failing = false
    clock = 0
    if (reducedMotion) { crossfade(1); return }
    wake()
  }

  function fail() {
    ensure()
    mode = "fail"
    failing = true
    clock = 0
    if (reducedMotion) { crossfade(0); return }
    for (var i = 0; i < columns; i++) {
      v[i] = 0
      capV[i] = 0
      cap[i] = Math.max(cap[i], h[i])
      // Caps hang on until after their bar has gone.
      capHold[i] = 0.22 + i * 0.012
    }
    wake()
  }

  function reset() {
    frames.running = false
    ensure()
    mode = "type"
    failing = false
    sinceKey = 99
    slam = 0
    fullness = 0
    fadeFrom = level; fadeTo = level; fadeT = 1
    for (var i = 0; i < columns; i++) {
      h[i] = restingHeight(i, level); v[i] = 0
      cap[i] = h[i]; capV[i] = 0; capHold[i] = 0
    }
    paint()
  }

  // Reduced motion: fade evenly from what is shown to a new level.
  function crossfade(to) {
    fadeFrom = fadeT < 0.5 ? fadeFrom : fadeTo
    fadeTo = to
    fadeT = 0
    clock = 0
    frames.running = true
  }

  onLevelChanged: if (mode === "type" && !reducedMotion) wake()
  onColumnsChanged: reset()

  function step(dt) {
    dt = Math.min(dt, 1 / 30)
    clock += dt
    now += dt
    sinceKey += dt

    if (reducedMotion) {
      var dur = mode === "fail" ? 0.45 : mode === "submit" ? 0.25 : 0.18
      fadeT = Math.min(1, clock / dur)
      fullness = mode === "submit" ? fadeT : mode === "fail" ? 0 : fullness
      if (fadeT >= 1) {
        if (mode === "fail") { mode = "type"; failing = false }
        frames.running = false
      }
      paint()
      return
    }

    var settled = true
    // Typing shimmer: a little life in every column, gone ~1.2 s after a key.
    var shimmer = mode === "type" ? 0.045 * Math.max(0, Math.min(1, (1.2 - sinceKey) / 0.6)) : 0
    var l = holding ? 1 : level

    for (var i = 0; i < columns; i++) {
      if (mode === "fail") {
        // Fast cascade, left to right: each bar falls away under gravity.
        var start = i * 0.018
        if (clock > start) {
          v[i] -= 22 * dt
          h[i] = Math.max(0, h[i] + v[i] * dt)
          if (h[i] <= 0) v[i] = 0
        }
      } else if (mode === "submit") {
        // Slam to the top.
        v[i] = Math.max(v[i], 0) + 40 * dt
        h[i] = Math.min(1, h[i] + v[i] * dt)
        if (h[i] >= 1) v[i] = 0
      } else {
        var target = restingHeight(i, l)
        if (shimmer > 0 && l > 0)
          target = Math.max(0, Math.min(1, target + shimmer * Math.sin(now * (6 + (i * 7) % 5) + i * 1.7)))
        // Underdamped spring back toward the skyline.
        var k = 110, c = 2 * 0.5 * Math.sqrt(k)
        v[i] += (k * (target - h[i]) - c * v[i]) * dt
        h[i] += v[i] * dt
        if (h[i] > 1) { h[i] = 1; v[i] = Math.min(0, v[i]) }
        if (h[i] < 0) { h[i] = 0; v[i] = Math.max(0, v[i]) }
        if (Math.abs(target - h[i]) > 0.0008 || Math.abs(v[i]) > 0.002) settled = false
      }

      // Peak caps: pushed up by their bar, hold, then fall slowly.
      if (h[i] >= cap[i]) {
        cap[i] = h[i]; capV[i] = 0
        if (mode !== "fail") capHold[i] = 0.32
      } else if (capHold[i] > 0) {
        capHold[i] -= dt
      } else {
        capV[i] += (mode === "fail" ? 9 : 1.4) * dt
        cap[i] = Math.max(h[i], cap[i] - capV[i] * dt)
      }
      if (cap[i] > h[i] + 0.0005) settled = false
    }

    if (mode === "submit") {
      slam = clock < 0.08 ? clock / 0.08 : Math.max(0, 1 - (clock - 0.08) / 0.45)
      fullness = Math.min(1, Math.max(0, (clock - 0.08) / 0.2))
      if (clock >= 0.55) { slam = 0; fullness = 1; frames.running = false }
    } else if (mode === "fail") {
      fullness = Math.max(0, fullness - dt / 0.08)
      var done = clock > columns * 0.018 + 0.2
      for (var j = 0; j < columns && done; j++)
        if (h[j] > 0 || cap[j] > 0) done = false
      if (done) { mode = "type"; failing = false; frames.running = false }
    } else {
      fullness = Math.max(0, fullness - dt / 0.12)
      if (settled && sinceKey > 1.2 && fullness <= 0) frames.running = false
    }
    paint()
  }

  // Push the simulation into the mask rectangles.
  function paint() {
    var sum = 0
    for (var i = 0; i < columns; i++) {
      var b = barRepeater.itemAt(i), p = capRepeater.itemAt(i)
      if (!b || !p) continue
      if (reducedMotion) {
        var lo = Math.min(fadeFrom, fadeTo), hi = Math.max(fadeFrom, fadeTo)
        b.lit = lo; b.fadeLo = lo; b.fadeHi = hi
        b.fadeOpacity = fadeTo > fadeFrom ? fadeT : 1 - fadeT
        p.peak = 0; p.opacity = 0
        sum += fadeFrom + (fadeTo - fadeFrom) * fadeT
      } else {
        b.lit = h[i]; b.fadeOpacity = 0
        p.peak = cap[i]
        // Caps show while they float above their bar, and flash on submit.
        var sep = (cap[i] - h[i]) * inkH
        p.opacity = Math.max(Math.min(1, sep / (capH * 1.5)), slam)
        sum += h[i]
      }
    }
    meanHeight = sum / columns
  }

  FrameAnimation {
    id: frames
    running: false
    onTriggered: root.step(frameTime)
  }

  // Lit columns, in the source's coordinates.
  Item {
    id: barMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      x: root.inkRect.x; y: root.inkRect.y
      width: root.inkRect.width; height: root.inkRect.height
      color: "white"
      opacity: root.fullness
    }

    Repeater {
      id: barRepeater
      model: root.columns
      Item {
        required property int index
        property real lit: 0
        property real fadeLo: 0
        property real fadeHi: 0
        property real fadeOpacity: 0
        readonly property real floor: root.inkRect.y + root.inkRect.height
        x: root.inkRect.x + index * root.pitch + root.gap / 2
        width: root.pitch - root.gap

        Rectangle {
          width: parent.width
          y: parent.floor - height
          height: parent.lit * root.inkH
          color: "white"
        }
        // Reduced motion: the band between two levels, fading.
        Rectangle {
          width: parent.width
          y: parent.floor - parent.fadeHi * root.inkH
          height: (parent.fadeHi - parent.fadeLo) * root.inkH
          color: "white"
          opacity: parent.fadeOpacity
        }
      }
    }
  }

  // Peak caps.
  Item {
    id: capMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      id: capRepeater
      model: root.columns
      Rectangle {
        required property int index
        property real peak: 0
        x: root.inkRect.x + index * root.pitch + root.gap / 2
        width: root.pitch - root.gap
        height: root.capH
        y: root.inkRect.y + root.inkRect.height - peak * root.inkH
        color: "white"
        opacity: 0
      }
    }
  }

  MultiEffect {
    anchors.fill: parent
    source: root.source
    autoPaddingEnabled: false
    maskEnabled: true
    maskSource: barMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
  }

  MultiEffect {
    anchors.fill: parent
    source: root.source
    autoPaddingEnabled: false
    maskEnabled: true
    maskSource: capMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: 1
    colorizationColor: root.failing ? root.errorColor : root.accent
    brightness: 0.1
  }
}
