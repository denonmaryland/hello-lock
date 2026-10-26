import QtQuick
import QtQuick.Effects

// Scanline: CRT burn-in. Each keystroke burns the next horizontal band of the
// logo in, top to bottom: an accent beam sweeps down to the new edge and the
// fresh band glows with phosphor and fine scanlines, then settles to the logo
// colour. Backspace retreats the beam and the band dims away. Submit races the
// beam to the bottom. Failure loses vertical hold: the picture jitters, rolls
// with a horizontal tear, then collapses to a line and goes dark.
// Reduced motion: bands fade in and out, top to bottom; no beam or roll.
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
  readonly property real glowLevel: reducedMotion ? calmGlow
    : Math.min(1, edge) * (failing ? 1 - smooth(600, 900, failMs) : 1)
  readonly property bool busy: edgeAnim.running || coolAnim.running || heatAnim.running
    || beamAnim.running || ghostAnim.running || failAnim.running || calmTimer.running

  // Beam position and settled phosphor edge, as fractions of the ink height.
  // `cool` trails `edge` on the way down; the band between them is still hot.
  property real edge: 0
  property real cool: 0
  property real heat: 0
  property real beam: 0
  // Band left behind by a retreat, dimming out.
  property real ghostTop: 0
  property real ghostBottom: 0
  property real ghost: 0
  // Failure timeline, 0..1 over failDuration.
  property bool failing: false
  property real failT: 0
  readonly property int failDuration: 1000
  readonly property real failMs: failT * failDuration

  readonly property real inkTop: inkRect.y
  readonly property real inkH: inkRect.height
  readonly property real edgeY: inkTop + edge * inkH
  readonly property real coolY: inkTop + Math.min(cool, edge) * inkH
  // Vivid accent for the beam and phosphor, readable even when the theme's
  // accent sits close to its foreground (same recipe as the cells effect).
  readonly property color beamColor: accent.hslHue < 0 ? Qt.hsla(0, 0, 0.95, 1)
    : Qt.hsla(accent.hslHue, Math.min(1, accent.hslSaturation * 1.3 + 0.15), 0.66, 1)

  function smooth(a, b, x) {
    var p = Math.max(0, Math.min(1, (x - a) / (b - a)))
    return p * p * (3 - 2 * p)
  }

  function keystroke(length, delta) {
    if (failing) stopFail()
    sync(delta)
  }

  function submit() {
    if (failing) stopFail()
    moveTo(1, 250, Easing.InOutQuad)
  }

  function fail() {
    if (reducedMotion) return
    stopAll()
    if (edge < 0.01) { snapTo(0); return }
    heat = 0
    beam = 0
    ghost = 0
    failing = true
    failAnim.restart()
  }

  function reset() {
    stopFail()
    stopAll()
    snapTo(0)
  }

  // Follows the host's level when it changes without a call (e.g. a submit
  // that never got a verdict). Deferred so fail() can claim the change first.
  // A Timer, not Qt.callLater: it dies with the effect, so a switch away
  // can't call into a destroyed item.
  onLevelChanged: syncTimer.restart()
  Timer { id: syncTimer; interval: 0; onTriggered: sync(0) }

  function sync(delta) {
    if (failing || reducedMotion) return
    var target = Math.max(0, Math.min(1, level))
    if (Math.abs(target - edgeAnim.to) < 0.001 && edgeAnim.running) return
    if (Math.abs(target - edge) < 0.001 && !edgeAnim.running) return
    if (target > edge) moveTo(target, holding ? 250 : 190, Easing.OutCubic)
    else moveTo(target, target === 0 && delta < -1 ? 340 : 170, Easing.OutCubic)
  }

  function moveTo(target, ms, easing) {
    if (reducedMotion) return
    var down = target > edge
    edgeAnim.stop()
    edgeAnim.from = edge
    edgeAnim.to = target
    edgeAnim.duration = ms
    edgeAnim.easing.type = easing
    edgeAnim.start()
    coolAnim.stop()
    coolAnim.from = Math.min(cool, edge)
    coolAnim.to = target
    // Going down the phosphor settles slowly behind the beam; going up the
    // settled edge simply follows it.
    coolAnim.duration = down ? 820 : ms
    coolAnim.easing.type = down ? Easing.InOutSine : easing
    coolAnim.start()
    if (down) {
      heatAnim.stop()
      heatAnim.from = Math.max(heat, 0.75)
      heatAnim.start()
    } else {
      ghostAnim.stop()
      ghostTop = target
      ghostBottom = Math.max(edge, ghost > 0.05 ? ghostBottom : 0)
      ghostAnim.start()
    }
    beamAnim.stop()
    beamAnim.peak = down ? 1 : 0.6
    beamAnim.hold = ms
    beamAnim.start()
  }

  function snapTo(v) {
    edge = v
    cool = v
    heat = 0
    beam = 0
    ghost = 0
  }

  function stopAll() {
    edgeAnim.stop()
    coolAnim.stop()
    heatAnim.stop()
    beamAnim.stop()
    ghostAnim.stop()
  }

  function stopFail() {
    if (!failing) return
    failAnim.stop()
    failing = false
    failT = 0
    snapTo(0)
  }

  NumberAnimation { id: edgeAnim; target: root; property: "edge" }
  NumberAnimation { id: coolAnim; target: root; property: "cool" }
  NumberAnimation { id: heatAnim; target: root; property: "heat"; to: 0; duration: 900; easing.type: Easing.InQuad }
  NumberAnimation { id: ghostAnim; target: root; property: "ghost"; from: 1; to: 0; duration: 300; easing.type: Easing.OutQuad }
  SequentialAnimation {
    id: beamAnim
    property real peak: 1
    property int hold: 190
    NumberAnimation { target: root; property: "beam"; to: beamAnim.peak; duration: 60; easing.type: Easing.OutQuad }
    PauseAnimation { duration: Math.max(0, beamAnim.hold - 60) }
    NumberAnimation { target: root; property: "beam"; to: 0; duration: 420; easing.type: Easing.InQuad }
  }
  NumberAnimation {
    id: failAnim
    target: root; property: "failT"
    from: 0; to: 1; duration: root.failDuration
    onFinished: {
      root.failing = false
      root.failT = 0
      root.snapTo(0)
    }
  }

  // ---- Failure timeline (ms since fail). Vertical offset in frame heights,
  // wrapped so the picture rolls round; then a CRT collapse to a line.
  readonly property real rollOffset: {
    var t = failMs
    if (t < 170) return 0.035 * Math.sin(t / 170 * Math.PI * 3) * (1 - t / 340)
    if (t < 470) { var p = (t - 170) / 300; return -(p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2) }
    if (t < 620) { var q = (t - 470) / 150; return -1 - q * q * 0.55 }
    if (t < 720) { var r = (t - 620) / 100; return -1.55 - 0.45 * (1 - (1 - r) * (1 - r)) }
    return 0
  }
  readonly property real rollY: { var y = rollOffset % 1; if (y < 0) y += 1; return y * height }
  readonly property bool tearOn: failing && failMs > 70 && failMs < 660 && Math.floor(failMs / 55) % 3 !== 1
  readonly property real tearY: inkTop + inkH * (0.12 + 0.62 * ((failMs / 430) % 1))
  readonly property real tearH: tearOn ? Math.max(4, inkH * (Math.floor(failMs / 110) % 2 ? 0.1 : 0.16)) : 0
  readonly property real tearDx: (Math.floor(failMs / 85) % 2 ? 1 : -0.6) * Math.max(8, inkRect.width * 0.045)
  readonly property real failRed: failing ? 0.8 * smooth(0, 160, failMs) : 0
  readonly property real collapseY: failing ? 1 - 0.988 * Math.pow(smooth(720, 860, failMs), 1.6) : 1
  readonly property real collapseX: failing ? 1 - smooth(860, 990, failMs) : 1
  readonly property real collapseGlow: failing ? smooth(740, 860, failMs) * (1 - smooth(900, 1000, failMs)) : 0

  // ---- Masks (hidden, permanently layered).

  // Lit area: settled ink, the hot band with scanlines, and a dimming band.
  Item {
    id: litMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Item {
      x: 0
      y: root.inkTop
      width: parent.width
      height: Math.max(0, root.edgeY - root.inkTop)
      clip: true
      opacity: root.reducedMotion ? 0 : 1

      // Settled: subtle permanent scanlines.
      Rectangle {
        width: parent.width
        height: root.coolY - root.inkTop
        color: "white"
        opacity: 0.84
      }
      // Hot band: deep scanlines that fill in as it cools.
      Rectangle {
        y: root.coolY - root.inkTop
        width: parent.width
        height: root.edgeY - root.coolY
        color: "white"
        opacity: 0.84 - 0.6 * root.heat
      }
      Repeater {
        model: Math.ceil(root.inkH / 3)
        Rectangle {
          required property int index
          y: index * 3
          width: parent.width
          height: 2
          color: "white"
        }
      }
    }

    Rectangle {
      x: 0
      y: root.inkTop + root.ghostTop * root.inkH
      width: parent.width
      height: Math.max(0, (root.ghostBottom - root.ghostTop) * root.inkH)
      color: "white"
      opacity: root.reducedMotion ? 0 : root.ghost * 0.8
    }

    // Reduced motion: twelve bands, each fading on its own.
    Repeater {
      model: 12
      Rectangle {
        required property int index
        x: 0
        y: root.inkTop + Math.floor(index * root.inkH / 12)
        width: parent.width
        height: Math.floor((index + 1) * root.inkH / 12) - Math.floor(index * root.inkH / 12)
        color: "white"
        opacity: root.reducedMotion ? Math.max(0, Math.min(1, root.level * 12 - index)) : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
      }
    }
  }

  // Phosphor: brightest at the beam, fading back toward the settled edge.
  Item {
    id: hotMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      x: 0
      width: parent.width
      // A little above the settled edge so the glow tails off smoothly.
      readonly property real y0: Math.max(root.inkTop, root.coolY - root.inkH * 0.04)
      y: y0
      height: Math.max(0, root.edgeY - y0)
      opacity: root.heat
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.45) }
        GradientStop { position: 1; color: "white" }
      }
    }
    // The line of ink right under the beam.
    Rectangle {
      x: 0
      y: root.edgeY - height
      width: parent.width
      height: Math.max(2, root.inkH * 0.035)
      opacity: root.beam
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 1; color: "white" }
      }
    }
  }

  // ---- The picture: lit logo, phosphor and beam, as one layer that the
  // failure can roll, tear and collapse.
  Item {
    id: screen
    anchors.fill: parent
    visible: false
    layer.enabled: true

    MultiEffect {
      anchors.fill: parent
      source: root.source
      autoPaddingEnabled: false
      maskEnabled: true
      maskSource: litMask
      // Min 0.5 with spread 1 maps mask alpha 0..1 smoothly to 0..1.
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1
    }
    MultiEffect {
      anchors.fill: parent
      source: root.source
      autoPaddingEnabled: false
      opacity: root.reducedMotion ? 0 : 1
      maskEnabled: true
      maskSource: hotMask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1
      colorization: 1
      colorizationColor: root.beamColor
      brightness: 0.15
    }

    // Beam: a thin line across the ink with a soft halo, ends faded out.
    Item {
      x: root.inkRect.x - 12
      y: root.edgeY
      width: root.inkRect.width + 24
      opacity: root.reducedMotion ? 0 : root.beam

      Rectangle {
        y: -height / 2
        width: parent.width
        height: Math.max(10, root.inkH * 0.07)
        opacity: 0.22
        gradient: Gradient {
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 0.5; color: root.beamColor }
          GradientStop { position: 1; color: "transparent" }
        }
      }
      Rectangle {
        y: -height / 2
        width: parent.width
        height: 1.5
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 0.12; color: root.beamColor }
          GradientStop { position: 0.88; color: root.beamColor }
          GradientStop { position: 1; color: "transparent" }
        }
      }
    }
  }

  // Three horizontal slices of the picture (above, in and below the tear),
  // each drawn twice so the vertical roll wraps round.
  component Slice: Item {
    id: slice
    property real dx: 0
    x: 0
    width: root.width
    clip: true
    visible: height > 0

    MultiEffect {
      x: slice.dx
      y: root.rollY - slice.y
      width: root.width
      height: root.height
      source: screen
      autoPaddingEnabled: false
      colorization: root.failRed
      colorizationColor: root.errorColor
      brightness: 0.5 * root.collapseGlow
    }
    MultiEffect {
      x: slice.dx
      y: root.rollY - root.height - slice.y
      width: root.width
      height: root.height
      visible: root.failing && root.rollY > 0
      source: screen
      autoPaddingEnabled: false
      colorization: root.failRed
      colorizationColor: root.errorColor
      brightness: 0.5 * root.collapseGlow
    }
  }

  Item {
    anchors.fill: parent
    clip: root.failing

    Item {
      anchors.fill: parent
      transform: Scale {
        origin.x: root.inkRect.x + root.inkRect.width / 2
        origin.y: root.inkRect.y + root.inkRect.height / 2
        xScale: root.collapseX
        yScale: root.collapseY
      }

      Slice { y: 0; height: root.tearH > 0 ? root.tearY : root.height }
      Slice { y: root.tearY; height: root.tearH; dx: root.tearDx }
      Slice { y: root.tearY + root.tearH; height: root.tearH > 0 ? root.height - y : 0 }
    }

    // The collapsed picture: a bright line that shrinks to nothing.
    Rectangle {
      x: root.inkRect.x + root.inkRect.width * (1 - root.collapseX) / 2
      y: root.inkRect.y + root.inkRect.height / 2 - height / 2
      width: root.inkRect.width * root.collapseX
      height: 2
      visible: root.collapseGlow > 0
      opacity: root.collapseGlow
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.2; color: root.errorColor }
        GradientStop { position: 0.5; color: Qt.lighter(root.errorColor, 1.35) }
        GradientStop { position: 0.8; color: root.errorColor }
        GradientStop { position: 1; color: "transparent" }
      }
    }
  }

  // Reduced motion: glow eases with the level; busy while the bands fade.
  property real calmGlow: reducedMotion ? level : 0
  Behavior on calmGlow { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }
  onReducedMotionChanged: calmTimer.restart()
  Connections {
    target: root
    enabled: root.reducedMotion
    function onLevelChanged() { calmTimer.restart() }
  }
  Timer { id: calmTimer; interval: 300 }
}
