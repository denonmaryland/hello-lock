import QtQuick
import QtQuick.Effects

// Cells: the logo rests dim; a mosaic of square cells over its inked area
// lights up, a chunk per typed character, in a shuffled order fixed for this
// view. Enter fills the rest in a quick sweep; a wrong password breaks the lit
// cells loose as tumbling pieces. Cells live in an alpha mask over a
// full-brightness copy of the logo, so they only ever show where it has ink.
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
  // Optional host extra: the logo's drop shadow colour (the host's plain logo
  // has the same shadow, so a fully lit logo looks exactly like the plain one).
  property color backgroundColor: "black"

  readonly property real baseOpacity: chargeActive ? chargeDim : 1
  // Fraction lit, eased; drives the host glow.
  readonly property real glowLevel: chargeLevel
  // Optional host extra: brief additive glow on each keystroke.
  property real glowKick: 0
  readonly property bool busy: frameClock.running || scatterAnimation.running || glowKickAnimation.running
    || levelAnimation.running || failTintAnimation.running || rebuildTimer.running || inkProbe.active

  readonly property int fullAt: 12
  readonly property real chargeDim: 0.22
  property real cellSize: 0
  property real gridX: 0
  property real gridY: 0
  property int gridCols: 0
  property int gridRows: 0
  // Ink cells only: [{ x, y, rank }] in this item's coordinates.
  property var cells: []
  readonly property int total: cells.length
  readonly property bool chargeActive: total > 0
  property int lit: 0
  // Previous lit count and per-cell delay of the change in flight, so each
  // chunk ripples in (or out, in reverse order) instead of switching at once.
  property int litFrom: 0
  property real stagger: 0
  property real stamp: 0
  property bool snap: false
  // Frame clock for the cell animations; only ticks while a change plays.
  property real now: 0
  property real busyUntil: 0
  // Submitted: hold full charge until the verdict arrives.
  property bool chargeHold: false
  readonly property real seed: Math.floor(Math.random() * 4294967296)
  property real chargeLevel: chargeActive ? lit / total : 1
  Behavior on chargeLevel { NumberAnimation { id: levelAnimation; duration: 260; easing.type: Easing.OutCubic } }
  // The accent pushed to a vivid, mid-light tone so the flash reads even
  // when a theme's accent sits close to its foreground.
  readonly property color flashColor: accent.hslHue < 0
    ? Qt.hsla(0, 0, 0.95, 1)
    : Qt.hsla(accent.hslHue, Math.min(1, accent.hslSaturation * 1.3 + 0.15), 0.62, 1)
  // Failure scatter: lit cells break loose as textured pieces.
  property var scatterPieces: []
  property real scatterT: 0
  // Brief error tint of the lit cells on a failure (seen while they fade with
  // reduced motion; otherwise they have already broken loose).
  property real failTint: 0

  // ---- Contract.
  function keystroke(length, delta) {
    if (delta > 0 && !reducedMotion) glowKickAnimation.restart()
    updateCharge(length)
  }

  function submit() {
    if (chargeHold) return
    chargeHold = true
    // The remaining dark cells fill in a ~250 ms sweep.
    setCharge(total, reducedMotion ? 120 : 170)
  }

  function fail() {
    chargeHold = false
    failTintAnimation.restart()
    if (lit === 0) return
    if (reducedMotion) { setCharge(0, 0); return }
    var pieces = []
    var cs = cellSize
    var cx = width / 2
    for (var i = 0; i < cells.length; i++) {
      var c = cells[i]
      if (c.rank >= lit) continue
      var r1 = Math.random(), r2 = Math.random(), r3 = Math.random()
      pieces.push({
        x: c.x, y: c.y,
        // Burst outward from the middle, a small upward kick, then fall.
        dx: ((c.x + cs / 2 - cx) / cx) * cs * 0.9 + (r1 - 0.5) * cs * 0.9,
        dy: -(0.15 + r2 * 0.55) * cs,
        g: (1.4 + r3 * 1.8) * cs,
        rot: (Math.random() - 0.5) * 80,
        d: Math.random() * 0.22
      })
    }
    scatterPieces = pieces
    // Pieces start exactly where the lit cells were, so the swap is seamless.
    setCharge(0, 0, true)
    scatterAnimation.restart()
  }

  function reset() {
    scatterAnimation.stop()
    scatterPieces = []
    glowKickAnimation.stop()
    glowKick = 0
    failTintAnimation.stop()
    failTint = 0
    chargeHold = holding
    setCharge(holding ? total : targetFor(typedLength), 0, true)
  }

  onHoldingChanged: {
    if (holding) submit()
    else if (chargeHold) { chargeHold = false; updateCharge(typedLength) }
  }

  // ---- Charge state.
  function targetFor(len) {
    if (len <= 0 || total === 0) return 0
    return Math.min(total, Math.ceil(total * Math.min(len, fullAt) / fullAt))
  }

  function setCharge(n, spanMs, snapNow) {
    n = Math.max(0, Math.min(total, n))
    if (n === lit) return
    var d = Math.abs(n - lit)
    litFrom = lit
    stagger = d > 1 ? spanMs / (d - 1) : 0
    snap = !!snapNow
    stamp = Date.now()
    now = stamp
    busyUntil = Math.max(busyUntil, stamp + spanMs + 420)
    lit = n
    snap = false
  }

  function updateCharge(len) {
    if (chargeHold) return
    var n = targetFor(len)
    // Typing: a quick sparkle per chunk. Backspace: a little faster. Clear
    // (Escape, Ctrl+U): a gentle reverse ripple across everything lit.
    setCharge(n, n > lit ? 70 : (n === 0 ? 180 : 50))
  }

  // Seeded shuffle so the fill order is stable for this view.
  function makeRandom(s0) {
    var s = s0 >>> 0
    return function() {
      s = (s + 0x6D2B79F5) >>> 0
      var t = s
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }

  // Lay out the grid over the logo's painted rect, then sample its alpha.
  function rebuild() {
    var w = inkRect.width
    var h = inkRect.height
    inkProbe.active = false
    if (!(w > 0 && h > 0) || !source) { cells = []; return }
    // Not on screen yet (a hidden preview window): wait for a window.
    awaitingWindow = !Window.window
    if (awaitingWindow) return
    // ~12 cells across the shorter side, capped near 420 grid cells.
    var cs = Math.max(8, Math.round(Math.max(Math.min(w, h) / 12, Math.sqrt(w * h / 420))))
    cellSize = cs
    gridCols = Math.ceil(w / cs)
    gridRows = Math.ceil(h / cs)
    gridX = Math.floor((w - gridCols * cs) / 2)
    gridY = Math.floor((h - gridRows * cs) / 2)
    // Grab the source at 4×4 samples per cell; the probe reads the result.
    var k = 4 / cs
    var gw = Math.max(1, Math.round(width * k))
    var gh = Math.max(1, Math.round(height * k))
    var ok = false
    try {
      ok = source.grabToImage(function(result) {
        inkProbe.url = String(result.url)
        inkProbe.grab = result
        inkProbe.active = true
      }, Qt.size(gw, gh))
    } catch (e) { ok = false }
    probing = ok
    if (!ok) applyInk(null)
  }

  property bool probing: false
  property bool awaitingWindow: false
  readonly property var hostWindow: Window.window
  onHostWindowChanged: if (hostWindow && awaitingWindow) rebuildTimer.restart()

  // alpha: per-cell max alpha (0..255) or null when the logo could not be read.
  function applyInk(alpha) {
    probing = false
    inkProbe.active = false
    inkProbe.grab = null
    var idx = []
    for (var i = 0; i < gridCols * gridRows; i++)
      if (!alpha || alpha[i] > 40) idx.push(i)
    var rnd = makeRandom(seed)
    for (var j = idx.length - 1; j > 0; j--) {
      var k = Math.floor(rnd() * (j + 1))
      var tmp = idx[j]; idx[j] = idx[k]; idx[k] = tmp
    }
    var list = []
    for (var r = 0; r < idx.length; r++) {
      var col = idx[r] % gridCols
      var row = Math.floor(idx[r] / gridCols)
      list.push({ x: inkRect.x + gridX + col * cellSize, y: inkRect.y + gridY + row * cellSize, rank: r })
    }
    // A rebuild (resize) keeps the current charge without replaying it.
    snap = true
    lit = 0
    cells = list
    litFrom = 0
    lit = chargeHold ? total : targetFor(typedLength)
    snap = false
  }

  onWidthChanged: rebuildTimer.restart()
  onHeightChanged: rebuildTimer.restart()
  onInkRectChanged: rebuildTimer.restart()
  onSourceChanged: rebuildTimer.restart()

  Timer {
    id: rebuildTimer
    interval: 120
    onTriggered: root.rebuild()
  }

  // The grab or the probe never answered: fall back to the full grid.
  Timer {
    id: probeWatchdog
    interval: 1500
    running: root.probing
    onTriggered: {
      console.warn("hello-lock cells: logo alpha probe timed out, using the full grid")
      root.applyInk(null)
    }
  }

  Timer {
    id: inkApplyTimer
    property var alpha: null
    interval: 0
    onTriggered: root.applyInk(alpha)
  }

  FrameAnimation {
    id: frameClock
    running: root.now < root.busyUntil
    onTriggered: root.now = Date.now()
  }

  NumberAnimation {
    id: scatterAnimation
    target: root
    property: "scatterT"
    from: 0
    to: 1
    duration: 760
    onFinished: root.scatterPieces = []
  }

  NumberAnimation {
    id: glowKickAnimation
    target: root
    property: "glowKick"
    from: 0.14
    to: 0
    duration: 380
    easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: failTintAnimation
    NumberAnimation { target: root; property: "failTint"; to: 1; duration: 50; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 220 }
    NumberAnimation { target: root; property: "failTint"; to: 0; duration: 180; easing.type: Easing.InOutQuad }
  }

  // Full-brightness logo with the same drop shadow as the host's plain logo;
  // the lit cells and scatter pieces show this.
  Item {
    id: litLogo
    anchors.fill: parent
    visible: false
    layer.enabled: true

    MultiEffect {
      anchors.fill: parent
      source: root.source
      autoPaddingEnabled: false
      shadowEnabled: true
      shadowColor: root.backgroundColor
      shadowOpacity: 0.55
      shadowBlur: 0.8
      shadowVerticalOffset: 2
      shadowHorizontalOffset: 0
    }
  }

  // White silhouette of the logo, recoloured for the accent flash.
  Item {
    id: silhouette
    anchors.fill: parent
    visible: false
    layer.enabled: true

    MultiEffect {
      anchors.fill: parent
      source: root.source
      autoPaddingEnabled: false
      brightness: 1
    }
  }

  // Charge masks. chargeMask holds the lit cells; flashMask the accent flash
  // of each cell as it lights. Cell state is a pure function of the frame
  // clock, so a few hundred cells cost no animation objects and nothing runs
  // when idle.
  Item {
    id: chargeMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    // Covers the whole rect once fully charged, so the shadow around the
    // logo edge comes back exactly as without the mosaic.
    Rectangle {
      anchors.fill: parent
      color: "white"
      opacity: root.chargeActive && root.lit >= root.total ? 1 : 0
      Behavior on opacity { enabled: !root.snap; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }

    Repeater {
      id: cellRepeater
      model: root.cells

      Rectangle {
        id: cell
        required property var modelData
        readonly property int rank: modelData.rank
        readonly property bool lit: rank < root.lit
        property real startAt: -1e12
        property real fromOpacity: 0
        // Settled-to state; lags lit until restate() has captured the start.
        property bool on: false
        readonly property real t: root.now - startAt
        readonly property bool calm: root.reducedMotion
        x: modelData.x
        y: modelData.y
        width: root.cellSize
        height: root.cellSize
        color: "white"
        // Lighting: ~90 ms ease in with a 0.45 → 1.14 → 1 pop. Dimming:
        // a 200 ms ease out with a slight shrink. Reduced motion: opacity.
        opacity: {
          if (t < 0) return fromOpacity
          var p = Math.min(1, t / (calm ? 160 : (on ? 90 : 200)))
          if (on) return fromOpacity + (1 - fromOpacity) * (calm ? p : 1 - Math.pow(1 - p, 3))
          return fromOpacity * (1 - (calm ? p : p * p * (3 - 2 * p)))
        }
        scale: {
          if (calm || t < 0) return 1
          if (!on) return 1 - 0.18 * Math.min(1, t / 200)
          if (fromOpacity > 0.5) return 1
          if (t < 110) return 0.45 + 0.69 * (1 - Math.pow(1 - t / 110, 3))
          if (t < 260) return 1.14 - 0.14 * (0.5 - 0.5 * Math.cos(Math.PI * (t - 110) / 150))
          return 1
        }
        readonly property real flash: (calm || !on || t < 0 || fromOpacity > 0.5) ? 0 : Math.pow(1 - Math.min(1, t / 420), 2)

        function restate(snapNow) {
          if (snapNow) {
            on = lit
            startAt = -1e12
            fromOpacity = lit ? 1 : 0
            return
          }
          // Read the current value before switching state, so a reversal
          // mid-animation continues from where the cell is.
          var from = opacity
          on = lit
          var delay = lit ? Math.max(0, rank - root.litFrom) : Math.max(0, root.litFrom - 1 - rank)
          fromOpacity = from
          startAt = root.stamp + delay * root.stagger
        }

        onLitChanged: restate(root.snap)
        Component.onCompleted: restate(true)
      }
    }
  }

  Item {
    id: flashMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      model: root.cells

      Rectangle {
        required property int index
        readonly property Item twin: cellRepeater.count > index ? cellRepeater.itemAt(index) : null
        x: twin ? twin.x : 0
        y: twin ? twin.y : 0
        width: root.cellSize
        height: root.cellSize
        scale: twin ? twin.scale : 1
        color: "white"
        // No visible-binding here: inside a hidden layered parent a
        // visibility flip does not repaint the layer; opacity does.
        opacity: twin ? twin.flash : 0
      }
    }
  }

  // Lit cells: the full-brightness logo through the cell mask.
  MultiEffect {
    anchors.fill: parent
    source: litLogo
    autoPaddingEnabled: false
    visible: root.chargeActive && root.source !== null
    maskEnabled: true
    maskSource: chargeMask
    // Min 0.5 with spread 1 maps mask alpha 0..1 smoothly to 0..1.
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: root.failTint
    colorizationColor: root.errorColor
  }

  // Accent flash of freshly lit cells, fading to the logo colour.
  MultiEffect {
    anchors.fill: parent
    source: silhouette
    autoPaddingEnabled: false
    visible: root.chargeActive && !root.reducedMotion && root.source !== null
    maskEnabled: true
    maskSource: flashMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: 1
    colorizationColor: root.flashColor
  }

  // Failure scatter: each lit cell becomes a piece of the lit logo that
  // breaks loose, drifts, tumbles and falls a little while fading.
  Repeater {
    model: root.scatterPieces

    ShaderEffectSource {
      required property var modelData
      readonly property real p: Math.max(0, Math.min(1, (root.scatterT - modelData.d) / (1 - modelData.d)))
      readonly property real ease: 1 - Math.pow(1 - p, 3)
      sourceItem: litLogo
      sourceRect: Qt.rect(modelData.x, modelData.y, root.cellSize, root.cellSize)
      x: modelData.x + modelData.dx * ease
      y: modelData.y + modelData.dy * ease + modelData.g * p * p
      width: root.cellSize
      height: root.cellSize
      rotation: modelData.rot * ease
      scale: 1 - 0.3 * p
      opacity: 1 - p * p
      antialiasing: true
    }
  }

  // One-shot alpha probe: draws the grabbed logo into a small canvas (4×4
  // samples per cell) and keeps the cells that contain ink. Parked
  // off-screen; unloaded as soon as it has answered.
  Loader {
    id: inkProbe
    property string url: ""
    property var grab: null
    active: false
    x: -width - 64
    sourceComponent: Canvas {
      readonly property int samples: 4
      width: root.gridCols * samples
      height: root.gridRows * samples
      renderStrategy: Canvas.Immediate

      Component.onCompleted: {
        if (isImageLoaded(inkProbe.url)) requestPaint()
        else loadImage(inkProbe.url)
      }
      onImageLoaded: requestPaint()

      onPaint: {
        if (!isImageLoaded(inkProbe.url)) return
        var cols = root.gridCols
        var rows = root.gridRows
        var k = samples / root.cellSize
        var alpha = null
        try {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          ctx.drawImage(inkProbe.url, -(root.inkRect.x + root.gridX) * k, -(root.inkRect.y + root.gridY) * k, root.width * k, root.height * k)
          var data = ctx.getImageData(0, 0, width, height).data
          alpha = []
          for (var c = 0; c < cols * rows; c++) alpha.push(0)
          for (var py = 0; py < height; py++) {
            var rowBase = Math.floor(py / samples) * cols
            for (var px = 0; px < width; px++) {
              var a = data[(py * width + px) * 4 + 3]
              var ci = rowBase + Math.floor(px / samples)
              if (a > alpha[ci]) alpha[ci] = a
            }
          }
        } catch (e) {
          console.warn("hello-lock cells: logo alpha probe failed, using the full grid: " + e)
          alpha = null
        }
        // Applied from a timer owned by this effect (not Qt.callLater), so a
        // probe answering after the effect is unloaded does nothing.
        inkApplyTimer.alpha = alpha
        inkApplyTimer.restart()
      }
    }
  }
}
