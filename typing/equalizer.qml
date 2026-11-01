import QtQuick
import QtQuick.Effects

// Equalizer: the logo is lit by vertical bars rising from the bottom like an
// audio level meter. The skyline tracks the charge level; each keystroke
// kicks a few columns up, leaving accent peak caps that hold, then fall back
// slowly. Idle, the bars rest as a steady, slightly uneven skyline and
// nothing runs. Submit slams every bar to the top; failure drops the bars in
// a fast cascade, the caps last. Reduced motion: even bars built from twelve
// rows that each fade on their own, so fast typing never pops.
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
  readonly property real glowLevel: reducedMotion ? calmGlow : Math.max(0, Math.min(1, meanHeight)) * 0.9
  readonly property bool busy: frames.running || calmTimer.running

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
    if (reducedMotion) return
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

  // Reduced motion: the rows follow `level` (the host's hold), nothing else.
  function submit() {
    ensure()
    if (reducedMotion) return
    mode = "submit"
    failing = false
    clock = 0
    wake()
  }

  function fail() {
    ensure()
    if (reducedMotion) return
    mode = "fail"
    failing = true
    clock = 0
    for (var i = 0; i < columns; i++) {
      v[i] = 0
      capV[i] = 0
      cap[i] = Math.max(cap[i], h[i])
      // Caps hang on until after their bar has gone.
      capHold[i] = 0.1 + i * 0.006
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
    for (var i = 0; i < columns; i++) {
      h[i] = restingHeight(i, level); v[i] = 0
      cap[i] = h[i]; capV[i] = 0; capHold[i] = 0
    }
    paint()
  }

  onLevelChanged: if (mode === "type" && !reducedMotion) wake()
  onColumnsChanged: reset()
  onReducedMotionChanged: { reset(); calmTimer.restart() }

  function step(dt) {
    dt = Math.min(dt, 1 / 30)
    clock += dt
    now += dt
    sinceKey += dt

    var settled = true
    // Typing shimmer: a little life in every column, gone ~1.2 s after a key.
    var shimmer = mode === "type" ? 0.045 * Math.max(0, Math.min(1, (1.2 - sinceKey) / 0.6)) : 0
    var l = holding ? 1 : level

    for (var i = 0; i < columns; i++) {
      if (mode === "fail") {
        // Fast cascade, left to right: each bar falls away under gravity.
        var start = i * 0.012
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
        // Underdamped spring back toward the skyline: retargets with its
        // velocity intact, so fast typing flows instead of restarting.
        var k = 150, c = 2 * 0.55 * Math.sqrt(k)
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
        capV[i] += (mode === "fail" ? 14 : 1.4) * dt
        cap[i] = Math.max(h[i], cap[i] - capV[i] * dt)
      }
      if (cap[i] > h[i] + 0.0005) settled = false
    }

    if (mode === "submit") {
      // Caps flash in fast, then decay; the gaps fill with an ease-out.
      var fall = Math.max(0, 1 - (clock - 0.08) / 0.45)
      slam = clock < 0.08 ? 1 - Math.pow(1 - clock / 0.08, 2) : fall * fall
      var fill = Math.min(1, Math.max(0, (clock - 0.08) / 0.2))
      fullness = 1 - Math.pow(1 - fill, 3)
      if (clock >= 0.55) { slam = 0; fullness = 1; frames.running = false }
    } else if (mode === "fail") {
      fullness = Math.max(0, fullness - dt / 0.08)
      var done = clock > columns * 0.012 + 0.2
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
      b.lit = h[i]
      p.peak = cap[i]
      // Caps show while they float above their bar, and flash on submit.
      var sep = (cap[i] - h[i]) * inkH
      p.opacity = reducedMotion ? 0 : Math.max(Math.min(1, sep / (capH * 1.5)), slam)
      sum += h[i]
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
        readonly property real floor: root.inkRect.y + root.inkRect.height
        x: root.inkRect.x + index * root.pitch + root.gap / 2
        width: root.pitch - root.gap
        // Opacity, not visible: a hidden layered parent may not repaint on
        // a visibility flip.
        opacity: root.reducedMotion ? 0 : 1

        Rectangle {
          width: parent.width
          y: parent.floor - height
          height: parent.lit * root.inkH
          color: "white"
        }
      }
    }

    // Reduced motion: the even columns, cut by the fading rows.
    MultiEffect {
      anchors.fill: parent
      opacity: root.reducedMotion ? 1 : 0
      source: calmColumns
      autoPaddingEnabled: false
      maskEnabled: true
      maskSource: calmRows
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1
    }
  }

  // Reduced motion: full-height columns (and the gap fill once submitted)...
  Item {
    id: calmColumns
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      model: root.columns
      Rectangle {
        required property int index
        x: root.inkRect.x + index * root.pitch + root.gap / 2
        y: root.inkRect.y
        width: root.pitch - root.gap
        height: root.inkRect.height
        color: "white"
      }
    }
    Rectangle {
      x: root.inkRect.x; y: root.inkRect.y
      width: root.inkRect.width; height: root.inkRect.height
      color: "white"
      opacity: root.reducedMotion && root.holding ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
    }
  }

  // ...shown through twelve rows from the bottom, each fading on its own.
  // Behaviors retarget from the current opacity, so nothing pops.
  Item {
    id: calmRows
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      model: 12
      Rectangle {
        required property int index
        readonly property real floor: root.inkRect.y + root.inkRect.height
        x: root.inkRect.x
        y: floor - Math.floor((index + 1) * root.inkRect.height / 12)
        width: root.inkRect.width
        height: Math.floor((index + 1) * root.inkRect.height / 12) - Math.floor(index * root.inkRect.height / 12)
        color: "white"
        opacity: root.reducedMotion ? Math.max(0, Math.min(1, root.level * 12 - index)) : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
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

  // Reduced motion: glow eases with the level; busy while the rows fade.
  property real calmGlow: reducedMotion ? level * 0.9 : 0
  Behavior on calmGlow { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }
  Connections {
    target: root
    enabled: root.reducedMotion
    function onLevelChanged() { calmTimer.restart() }
    function onHoldingChanged() { calmTimer.restart() }
  }
  Timer { id: calmTimer; interval: 300 }
}
