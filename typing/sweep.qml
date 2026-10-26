import QtQuick
import QtQuick.Effects

// Sweep: a charge meter. The logo fills left to right, a step per keystroke,
// behind a bright accent leading edge; each keystroke sends a sheen along the
// lit part. Backspace pulls the edge back. Submit snaps to full with a quick
// white-to-accent flash across. Failure is a power failure: the edge turns
// red, flickers and stutters back to zero, ending dark.
// Reduced motion: column steps fade in and out, left to right; no sheen.
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
  readonly property real glowLevel: reducedMotion ? calmGlow : Math.min(1, edge) * (failing ? failLit * 0.8 : 1)
  readonly property bool busy: edgeAnim.running || kickAnim.running || sheenAnim.running
    || flashAnim.running || failAnim.running || calmTimer.running

  // Fill edge as a fraction of the ink width.
  property real edge: 0
  // Extra brightness on the leading edge right after a keystroke.
  property real kick: 0
  // Sheen travelling along the lit part, 0..1 (1 = past the edge).
  property real sheen: 1
  // Submit flash: strength and white-to-accent progress.
  property real flash: 0
  property real flashTint: 0
  property real flashSweep: 1
  // Failure timeline, 0..1 over failDuration; edge is driven from it.
  property bool failing: false
  property real failT: 0
  property real failFrom: 1
  readonly property int failDuration: 900
  readonly property real failMs: failT * failDuration

  readonly property real inkX: inkRect.x
  readonly property real inkW: inkRect.width
  readonly property real edgeX: inkX + edge * inkW
  // Vivid accent for the edge, readable even when the theme's accent sits
  // close to its foreground (same recipe as the cells effect).
  readonly property color edgeColor: accent.hslHue < 0 ? Qt.hsla(0, 0, 0.95, 1)
    : Qt.hsla(accent.hslHue, Math.min(1, accent.hslSaturation * 1.3 + 0.15), 0.66, 1)
  readonly property color paleColor: accent.hslHue < 0 ? Qt.hsla(0, 0, 0.98, 1)
    : Qt.hsla(accent.hslHue, Math.min(1, accent.hslSaturation * 0.6 + 0.2), 0.9, 1)
  readonly property color frontColor: failing ? errorColor : edgeColor
  // The front fades once the meter is full: charged, nothing left to fill.
  readonly property real frontOpacity: edge <= 0.001 ? 0
    : (0.62 + 0.38 * kick) * (1 - smooth(0.985, 1, edge)) * (failing ? failLit : 1)

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
    if (reducedMotion) return
    moveTo(1, 220, Easing.OutCubic)
    flashAnim.restart()
  }

  function fail() {
    if (reducedMotion) return
    edgeAnim.stop()
    sheenAnim.stop()
    sheen = 1
    flashAnim.stop()
    flash = 0
    flashSweep = 1
    if (edge < 0.01) { snapTo(0); return }
    failFrom = edge
    failing = true
    failAnim.restart()
  }

  function reset() {
    stopFail()
    edgeAnim.stop()
    kickAnim.stop()
    sheenAnim.stop()
    flashAnim.stop()
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
    if (target > edge) {
      moveTo(target, holding ? 220 : 200, Easing.OutCubic)
      sheenAnim.restart()
    } else {
      moveTo(target, target === 0 && delta < -1 ? 360 : 170, Easing.OutCubic)
    }
  }

  function moveTo(target, ms, easing) {
    edgeAnim.stop()
    edgeAnim.from = edge
    edgeAnim.to = target
    edgeAnim.duration = ms
    edgeAnim.easing.type = easing
    edgeAnim.start()
    kickAnim.restart()
  }

  function snapTo(v) {
    edge = v
    kick = 0
    sheen = 1
    flash = 0
  }

  function stopFail() {
    if (!failing) return
    failAnim.stop()
    failing = false
    failT = 0
    snapTo(0)
  }

  NumberAnimation { id: edgeAnim; target: root; property: "edge" }
  NumberAnimation { id: kickAnim; target: root; property: "kick"; from: 1; to: 0; duration: 520; easing.type: Easing.OutQuad }
  NumberAnimation { id: sheenAnim; target: root; property: "sheen"; from: 0; to: 1; duration: 560; easing.type: Easing.InOutSine }
  ParallelAnimation {
    id: flashAnim
    NumberAnimation { target: root; property: "flashSweep"; from: 0; to: 1; duration: 230; easing.type: Easing.OutQuad }
    SequentialAnimation {
      PropertyAction { target: root; property: "flash"; value: 1 }
      PauseAnimation { duration: 200 }
      NumberAnimation { target: root; property: "flash"; to: 0; duration: 520; easing.type: Easing.InQuad }
    }
    NumberAnimation { target: root; property: "flashTint"; from: 0; to: 1; duration: 420; easing.type: Easing.InOutQuad }
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

  // ---- Failure: the edge stutters back in steps ([ms, fraction of the
  // starting charge]), with a brief surge, while the lit part flickers.
  readonly property var failKeys: [[0, 1], [70, 1], [130, 0.8], [230, 0.8], [270, 0.86], [340, 0.56],
    [440, 0.56], [490, 0.32], [580, 0.32], [610, 0.36], [680, 0.1], [780, 0.1], [860, 0]]
  readonly property real failEdge: {
    var t = failMs, k = failKeys
    for (var i = 1; i < k.length; i++) {
      if (t < k[i][0]) {
        var p = (t - k[i - 1][0]) / (k[i][0] - k[i - 1][0])
        return k[i - 1][1] + (k[i][1] - k[i - 1][1]) * (1 - Math.pow(1 - p, 3))
      }
    }
    return 0
  }
  onFailEdgeChanged: if (failing) edge = failFrom * failEdge
  // Lit brightness: a power flicker, browning out as it goes.
  readonly property var flickerSteps: [1, 0.45, 1, 0.85, 0.3, 1, 0.7, 0.2, 0.9, 0.5, 0.15, 0.75, 0.35, 0.6, 0.1, 0.4, 0.2, 0.3]
  readonly property real failLit: failing ? flickerSteps[Math.min(flickerSteps.length - 1, Math.floor(failMs / 50))] * (1 - 0.5 * smooth(500, 900, failMs)) : 1

  // ---- Masks (hidden, permanently layered).

  // Lit part: everything left of the edge.
  Item {
    id: litMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      width: Math.max(0, root.edgeX)
      height: parent.height
      color: "white"
      opacity: root.reducedMotion ? 0 : 1
    }

    // Reduced motion: twelve columns, each fading on its own.
    Repeater {
      model: 12
      Rectangle {
        required property int index
        x: root.inkX + Math.floor(index * root.inkW / 12)
        width: Math.floor((index + 1) * root.inkW / 12) - Math.floor(index * root.inkW / 12)
        height: parent.height
        color: "white"
        opacity: root.reducedMotion ? Math.max(0, Math.min(1, root.level * 12 - index)) : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
      }
    }
  }

  // Leading edge: the ink just behind the front, brightest at the front.
  Item {
    id: frontMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      readonly property real span: Math.max(14, root.inkW * 0.07) * (0.7 + 0.3 * root.kick)
      x: Math.max(0, root.edgeX - span)
      width: Math.min(span, Math.max(0, root.edgeX))
      height: parent.height
      opacity: root.reducedMotion ? 0 : root.frontOpacity
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.6) }
        GradientStop { position: 1; color: "white" }
      }
    }
  }

  // Sheen, clipped to the lit part.
  Item {
    id: sheenMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Item {
      width: Math.max(0, root.edgeX)
      height: parent.height
      clip: true
      opacity: root.reducedMotion ? 0 : 1

      Rectangle {
        readonly property real band: Math.max(40, root.inkW * 0.16)
        x: root.inkX - band + root.sheen * (root.edgeX - root.inkX + band)
        width: band
        height: parent.height
        opacity: 0.7 * Math.sin(Math.PI * root.sheen)
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 0.5; color: "white" }
          GradientStop { position: 1; color: "transparent" }
        }
      }
    }
  }

  // Submit flash: a white head racing across, the lit part behind it
  // flashing and cooling to accent.
  Item {
    id: flashMask
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Rectangle {
      x: root.inkX
      width: Math.max(0, Math.min(root.edgeX, root.inkX + root.flashSweep * root.inkW) - root.inkX)
      height: parent.height
      opacity: root.reducedMotion ? 0 : root.flash
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.5) }
        GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.8) }
        GradientStop { position: 1; color: "white" }
      }
    }
  }

  // ---- The picture.
  MultiEffect {
    anchors.fill: parent
    source: root.source
    autoPaddingEnabled: false
    opacity: root.failLit
    maskEnabled: true
    maskSource: litMask
    // Min 0.5 with spread 1 maps mask alpha 0..1 smoothly to 0..1.
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: root.failing ? 0.35 * root.smooth(0, 150, root.failMs) : 0
    colorizationColor: root.errorColor
  }
  MultiEffect {
    anchors.fill: parent
    source: root.source
    autoPaddingEnabled: false
    visible: !root.reducedMotion
    maskEnabled: true
    opacity: 0.6
    maskSource: sheenMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: 1
    colorizationColor: root.edgeColor
    brightness: 0.1
  }
  MultiEffect {
    anchors.fill: parent
    source: root.source
    autoPaddingEnabled: false
    visible: !root.reducedMotion && root.flash > 0
    maskEnabled: true
    maskSource: flashMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: 1
    colorizationColor: Qt.tint(root.paleColor, Qt.rgba(root.edgeColor.r, root.edgeColor.g, root.edgeColor.b, root.flashTint))
    brightness: 0.3 * (1 - root.flashTint)
  }
  MultiEffect {
    anchors.fill: parent
    source: root.source
    autoPaddingEnabled: false
    visible: !root.reducedMotion
    maskEnabled: true
    maskSource: frontMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
    colorization: 1
    colorizationColor: root.frontColor
    brightness: 0.12
  }

  // The front itself: a thin vertical line over the ink with a soft halo,
  // ends faded out.
  Item {
    x: root.edgeX
    y: root.inkRect.y - 8
    height: root.inkRect.height + 16
    visible: !root.reducedMotion && opacity > 0
    opacity: root.frontOpacity

    Rectangle {
      x: -width / 2
      width: Math.max(10, root.inkRect.height * 0.08)
      height: parent.height
      opacity: 0.35
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.5; color: root.frontColor }
        GradientStop { position: 1; color: "transparent" }
      }
    }
    Rectangle {
      x: -width / 2
      width: 1.5
      height: parent.height
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 0.15; color: root.frontColor }
        GradientStop { position: 0.85; color: root.frontColor }
        GradientStop { position: 1; color: "transparent" }
      }
    }
  }

  // Reduced motion: glow eases with the level; busy while the columns fade.
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
