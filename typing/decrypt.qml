import QtQuick
import QtQuick.Effects
import QtQuick.Window

// Decrypt: the logo is cut into horizontal slices that start "encrypted":
// shoved sideways, dim, with accent-tinted chromatic ghosts. Each keystroke
// snaps the next slice(s) into place with a bright flash and a tiny overshoot,
// so a full charge shows the clean logo. Unresolved slices jitter only while
// typing. Backspace re-scrambles the last slice, submit locks the rest in top
// to bottom, failure bursts everything apart in the error colour. Reduced
// motion: no offsets, slices just fade from dim to full.
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

  readonly property real baseOpacity: 0
  readonly property real glowLevel: Math.max(0, Math.min(1, 0.06 + 0.8 * resolvedEased + flashKick))
  readonly property bool busy: busyTimer.running || jitterAnimation.running || burstAnimation.running
    || errorAnimation.running || flashKickAnimation.running

  readonly property int fullAt: 12
  readonly property real dim: 0.28

  // Ink extent (root coords) from the alpha probe; inkRect until it lands.
  property real inkTop: inkRect.y
  property real inkBottom: inkRect.y + inkRect.height
  property var rowAlpha: null
  property real probeScale: 1

  // Slices: [{ y0, y1, rank, dx, w, ph }]; rank -1 = no ink (always clean).
  property var slices: []
  property int rankCount: 0
  property int resolved: 0
  property bool held: false

  // Encrypted offset scale and chromatic split, from the logo's size.
  readonly property real amp: Math.max(14, Math.min(40, (inkBottom - inkTop) * 0.2))
  readonly property real split: Math.max(2.5, Math.min(5, amp * 0.12))
  // Side room for shoved bands; band edges land on device pixels.
  readonly property real padX: snap(amp * 3.5)
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  function snap(v) { return Math.round(v * dpr) / dpr }
  onDprChanged: probeTimer.restartFresh()

  // Motion state: jitter envelope while typing, failure burst, clock.
  property real jitter: 0
  property real burst: 0
  property real errorMix: 0
  property real clock: 0
  property real burstSeed: 0
  property real flashKick: 0
  property real resolvedEased: rankCount > 0 ? resolved / rankCount : 0
  Behavior on resolvedEased { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

  function shade(c, l, satBoost) {
    if (c.hslHue < 0) return Qt.hsla(0, 0, l, 1)
    return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * satBoost + 0.1), l, 1)
  }
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  readonly property color ghostAColor: mix(shade(accent, 0.6, 1.3), errorColor, errorMix)
  readonly property color ghostBColor: mix(shade(accent, 0.82, 1.0), shade(errorColor, 0.8, 1.0), errorMix)
  readonly property color flashColor: shade(accent, 0.92, 1.0)

  function hash(n) {
    var s = Math.sin(n * 12.9898 + 78.233) * 43758.5453
    return s - Math.floor(s)
  }

  // Seeded shuffle so the resolve order is stable.
  function seeded(seed) {
    var s = seed >>> 0
    return function() {
      s = (s + 0x6D2B79F5) >>> 0
      var t = s
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }

  function targetFor(len) {
    if (len <= 0 || rankCount === 0) return 0
    return Math.min(rankCount, Math.ceil(rankCount * Math.min(len, fullAt) / fullAt - 1e-6))
  }

  function sliceAt(i) { return sliceRepeater.itemAt(i) }

  function extendBusy(ms) {
    var now = Date.now()
    var left = busyTimer.running ? busyTimer.endsAt - now : 0
    if (ms <= left) return
    busyTimer.endsAt = now + ms
    busyTimer.interval = ms
    busyTimer.restart()
  }

  function kickJitter() {
    if (reducedMotion) return
    jitterAnimation.stop()
    jitterAnimation.start()
  }

  // Move to n resolved ranks; new ones snap in, dropped ones re-scramble.
  function setResolved(n, stagger) {
    n = Math.max(0, Math.min(rankCount, n))
    if (n === resolved) return
    var up = n > resolved
    var order = 0
    for (var i = 0; i < slices.length; i++) {
      var s = sliceAt(i)
      if (!s || s.rank < 0) continue
      if (up && s.rank >= resolved && s.rank < n) s.resolveIn((s.rank - resolved) * stagger)
      else if (!up && s.rank >= n && s.rank < resolved) s.scramble((resolved - 1 - s.rank) * stagger)
    }
    extendBusy(Math.abs(n - resolved) * stagger + 420)
    resolved = n
  }

  function keystroke(length, delta) {
    if (held) return
    kickJitter()
    var n = targetFor(length)
    // Clear (Escape, Ctrl+U): a quick reverse ripple through everything.
    setResolved(n, n > resolved ? 45 : (delta < -1 ? 28 : 40))
  }

  function submit() {
    held = true
    // Remaining slices lock in top to bottom over ~200 ms.
    var pending = []
    for (var i = 0; i < slices.length; i++) {
      var s = sliceAt(i)
      if (s && s.rank >= resolved) pending.push(s)
    }
    var step = pending.length > 1 ? 200 / (pending.length - 1) : 0
    for (var j = 0; j < pending.length; j++) pending[j].resolveIn(j * step, true)
    resolved = rankCount
    extendBusy(200 + 420)
    flashKickAnimation.restart()
  }

  function fail() {
    held = false
    resolved = 0
    for (var i = 0; i < slices.length; i++) {
      var s = sliceAt(i)
      if (s) s.scrambleNow(reducedMotion)
    }
    if (reducedMotion) { extendBusy(360); return }
    burstSeed = Math.random() * 1000
    jitterAnimation.stop()
    jitter = 0
    burstAnimation.restart()
    errorAnimation.restart()
  }

  function reset() {
    held = false
    jitterAnimation.stop()
    burstAnimation.stop()
    errorAnimation.stop()
    flashKickAnimation.stop()
    jitter = 0; burst = 0; errorMix = 0; flashKick = 0
    resolved = targetFor(typedLength)
    for (var i = 0; i < slices.length; i++) {
      var s = sliceAt(i)
      if (s) s.settle(s.rank < resolved)
    }
  }

  onHoldingChanged: if (!holding && held) { held = false; setResolved(targetFor(typedLength), 40) }

  // ---- Slicing: cut the ink's height into 10..16 bands, skip empty ones.
  function rebuild() {
    var top = inkTop, bottom = inkBottom
    var h = bottom - top
    if (!(h > 4) || !(width > 0)) { slices = []; rankCount = 0; return }
    var n = Math.max(10, Math.min(16, Math.round(h / 13)))
    var rnd = seeded(0x5eed + n)
    var list = []
    var ranked = []
    for (var i = 0; i < n; i++) {
      var y0 = i === 0 ? Math.min(0, Math.floor(top)) : snap(top + h * i / n)
      var y1 = i === n - 1 ? Math.max(height, Math.ceil(bottom)) : snap(top + h * (i + 1) / n)
      // Random shove, kept clearly apart from the slice above.
      var dx = 0
      for (var tries = 0; tries < 8; tries++) {
        dx = (rnd() < 0.5 ? -1 : 1) * (0.3 + 0.7 * rnd())
        if (!list.length || Math.abs(dx - list[list.length - 1].dx) > 0.45) break
      }
      list.push({ y0: y0, y1: y1, rank: -1, dx: dx,
                  w: 0.6 + rnd() * 0.9, ph: rnd() * 6.283 })
      if (hasInk(Math.max(y0, top), Math.min(y1, bottom))) ranked.push(i)
    }
    for (var j = ranked.length - 1; j > 0; j--) {
      var k = Math.floor(rnd() * (j + 1))
      var t = ranked[j]; ranked[j] = ranked[k]; ranked[k] = t
    }
    for (var r = 0; r < ranked.length; r++) list[ranked[r]].rank = r
    rankCount = ranked.length
    slices = list
    reset()
  }

  function hasInk(y0, y1) {
    if (!rowAlpha) return true
    var a = Math.floor(y0 * probeScale), b = Math.ceil(y1 * probeScale)
    for (var y = Math.max(0, a); y < Math.min(rowAlpha.length, b); y++)
      if (rowAlpha[y] > 24) return true
    return false
  }

  // ---- Alpha probe: grab the logo small and read each row's peak alpha.
  function probe() {
    if (!source || !(width > 0 && height > 0)) return
    var k = Math.min(1, 320 / width, 320 / height)
    var pw = Math.max(8, Math.round(width * k)), ph = Math.max(8, Math.round(height * k))
    source.grabToImage(function(r) {
      probeCanvas.pw = pw; probeCanvas.ph = ph; probeCanvas.k = k
      probeImage.source = r.url
    }, Qt.size(pw, ph))
  }

  function applyProbe(rows, k) {
    var first = -1, last = -1
    for (var y = 0; y < rows.length; y++) if (rows[y] > 24) { if (first < 0) first = y; last = y }
    if (first < 0) {
      // Nothing painted yet (logo still loading): retry a few times.
      if (probeTimer.tries++ < 6) probeTimer.restart()
      rowAlpha = null; inkTop = inkRect.y; inkBottom = inkRect.y + inkRect.height
    } else {
      rowAlpha = rows; probeScale = k
      inkTop = first / k
      inkBottom = (last + 1) / k
    }
    rebuild()
  }

  onWidthChanged: probeTimer.restartFresh()
  onHeightChanged: probeTimer.restartFresh()
  onInkRectChanged: probeTimer.restartFresh()
  onSourceChanged: probeTimer.restartFresh()
  Component.onCompleted: probeTimer.restartFresh()

  Timer {
    id: probeTimer
    property int tries: 0
    interval: 150
    function restartFresh() { tries = 0; restart() }
    onTriggered: root.probe()
  }

  Image {
    id: probeImage
    visible: false
    cache: false
    onStatusChanged: if (status === Image.Ready) probeCanvas.requestPaint()
  }

  Canvas {
    id: probeCanvas
    property int pw: 8
    property int ph: 8
    property real k: 1
    x: -width - 64
    width: pw
    height: ph
    opacity: 0
    renderStrategy: Canvas.Immediate
    onPaint: {
      if (probeImage.status !== Image.Ready) return
      var rows = []
      try {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, pw, ph)
        ctx.drawImage(probeImage, 0, 0, pw, ph)
        var d = ctx.getImageData(0, 0, pw, ph).data
        for (var y = 0; y < ph; y++) {
          var m = 0
          for (var x = 0; x < pw; x++) m = Math.max(m, d[(y * pw + x) * 4 + 3])
          rows.push(m)
        }
      } catch (e) {
        console.warn("hello-lock: decrypt alpha probe failed: " + e)
        rows = []
      }
      probeImage.source = ""
      if (rows.length) root.applyProbe(rows, k)
    }
  }

  // ---- Tinted silhouettes for ghosts and flashes (layered, never shown).
  Item {
    id: whiteSil
    anchors.fill: parent
    visible: false
    layer.enabled: true
    MultiEffect { anchors.fill: parent; source: root.source; brightness: 1 }
  }
  Item {
    id: ghostA
    anchors.fill: parent
    visible: false
    layer.enabled: true
    MultiEffect { anchors.fill: parent; source: whiteSil; colorization: 1; colorizationColor: root.ghostAColor }
  }
  Item {
    id: ghostB
    anchors.fill: parent
    visible: false
    layer.enabled: true
    MultiEffect { anchors.fill: parent; source: whiteSil; colorization: 1; colorizationColor: root.ghostBColor }
  }
  Item {
    id: flashTint
    anchors.fill: parent
    visible: false
    layer.enabled: true
    MultiEffect { anchors.fill: parent; source: whiteSil; colorization: 1; colorizationColor: root.flashColor }
  }

  // Bands render into one layer anchored to our origin, so the clipped band
  // edges (snapped to device pixels) tile exactly at any scale factor.
  Item {
    id: bands
    x: -root.padX
    width: root.width + 2 * root.padX
    height: root.height
    layer.enabled: true

    Repeater {
      id: sliceRepeater
      model: root.slices

      delegate: Item {
        id: slice
        required property var modelData
        required property int index
        readonly property int rank: modelData.rank
        // 0 = encrypted, 1 = in place (overshoots slightly past 1 on snap).
        property real p: rank < 0 ? 1 : 0
        property real flash: 0
        readonly property real open: Math.max(0, 1 - p)
        readonly property real baseDx: modelData.dx * root.amp

        // Sideways offset: rest scramble, typing jitter, failure burst.
        readonly property real offset: {
          if (root.reducedMotion) return 0
          var d = baseDx * (1 - p) * (1 + 1.6 * root.burst)
          if (open <= 0) return d
          var c = root.clock
          var j = 0
          if (root.jitter > 0) {
            var step = Math.floor(c * 11)
            var hop = root.hash(step * 1.7 + index * 13.1)
            j = 1.6 * Math.sin(c * 6.283 * modelData.w + modelData.ph)
              + (hop > 0.82 ? (root.hash(step * 3.3 + index * 7.7) - 0.5) * root.amp * 0.45 : 0)
            j *= root.jitter
          }
          if (root.burst > 0) {
            var bs = Math.floor(c * 22)
            j += (root.hash(bs * 2.1 + index * 5.3 + root.burstSeed) - 0.5) * root.amp * 1.4 * root.burst
          }
          return d + j * open
        }
        readonly property real spread: root.reducedMotion ? 0 : open * (root.split + root.burst * root.split * 2.2)
        readonly property real ghostOpacity: root.reducedMotion ? 0 : Math.min(1, open) * (0.17 + 0.33 * root.burst)

        x: 0
        y: modelData.y0
        width: bands.width
        height: modelData.y1 - modelData.y0
        clip: true

        ShaderEffect {
          x: root.padX + slice.offset - slice.spread
          y: -slice.modelData.y0
          width: root.width; height: root.height
          opacity: slice.ghostOpacity
          property variant source: ghostA
        }
        ShaderEffect {
          x: root.padX + slice.offset + slice.spread
          y: -slice.modelData.y0
          width: root.width; height: root.height
          opacity: slice.ghostOpacity
          property variant source: ghostB
        }
        ShaderEffect {
          x: root.padX + slice.offset
          y: -slice.modelData.y0
          width: root.width; height: root.height
          opacity: root.dim + (1 - root.dim) * Math.min(1, slice.p)
          property variant source: root.source
        }
        ShaderEffect {
          x: root.padX + slice.offset
          y: -slice.modelData.y0
          width: root.width; height: root.height
          opacity: slice.flash
          property variant source: flashTint
        }

        function resolveIn(delay, fast) {
          scrambleAnimation.stop()
          resolvePause.duration = delay
          resolveMove.duration = root.reducedMotion ? 200 : (fast ? 190 : 240)
          resolveAnimation.restart()
        }
        function scramble(delay) {
          resolveAnimation.stop()
          flash = 0
          scramblePause.duration = delay
          scrambleAnimation.restart()
        }
        function scrambleNow(fade) {
          resolveAnimation.stop()
          scrambleAnimation.stop()
          flash = 0
          if (rank < 0) return
          if (fade) { scramblePause.duration = 0; scrambleAnimation.restart() }
          else p = 0
        }
        function settle(on) {
          resolveAnimation.stop()
          scrambleAnimation.stop()
          flash = 0
          p = rank < 0 || on ? 1 : 0
        }

        SequentialAnimation {
          id: resolveAnimation
          PauseAnimation { id: resolvePause; duration: 0 }
          ParallelAnimation {
            NumberAnimation {
              id: resolveMove
              target: slice; property: "p"; to: 1; duration: 240
              easing.type: root.reducedMotion ? Easing.OutCubic : Easing.OutBack
              easing.overshoot: 1.2
            }
            SequentialAnimation {
              PauseAnimation { duration: root.reducedMotion ? 0 : 45 }
              PropertyAction { target: slice; property: "flash"; value: root.reducedMotion ? 0 : 0.95 }
              PauseAnimation { duration: 17 }
              NumberAnimation { target: slice; property: "flash"; to: 0; duration: 170; easing.type: Easing.OutQuad }
            }
          }
        }
        SequentialAnimation {
          id: scrambleAnimation
          PauseAnimation { id: scramblePause; duration: 0 }
          NumberAnimation {
            target: slice; property: "p"; to: 0
            duration: root.reducedMotion ? 300 : 200
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  // ---- Shared motion.
  Timer {
    id: busyTimer
    property real endsAt: 0
    interval: 400
  }

  FrameAnimation {
    running: root.jitter > 0 || root.burst > 0
    onTriggered: root.clock += frameTime
  }

  // Unresolved slices wake on a keystroke and settle ~0.5 s after the last.
  SequentialAnimation {
    id: jitterAnimation
    NumberAnimation { target: root; property: "jitter"; to: 1; duration: 120; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 420 }
    NumberAnimation { target: root; property: "jitter"; to: 0; duration: 520; easing.type: Easing.InOutSine }
  }

  NumberAnimation {
    id: burstAnimation
    target: root; property: "burst"; from: 1; to: 0
    duration: 560; easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: errorAnimation
    PropertyAction { target: root; property: "errorMix"; value: 1 }
    PauseAnimation { duration: 300 }
    NumberAnimation { target: root; property: "errorMix"; to: 0; duration: 260; easing.type: Easing.InOutSine }
  }

  NumberAnimation {
    id: flashKickAnimation
    target: root; property: "flashKick"; from: 0.15; to: 0
    duration: 420; easing.type: Easing.OutCubic
  }
}
