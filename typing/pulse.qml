import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Pulse: no progress, just a heartbeat. The logo stays fully lit; each
// keystroke sends a soft band of accent light from the ink's centre outward
// (masked to the logo) with a tiny breath of the ripple light. Backspace pulls a smaller,
// dimmer ripple inward, submit is one bright full pulse, failure one ripple in
// the error colour. Reduced motion: a gentle brightness blink, no scale.
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

  // The host always draws the logo; the breath only scales the ripples. (An
  // own scaled copy swapped in for the host's flickered on the real lock.)
  readonly property real baseOpacity: 1
  readonly property real glowLevel: Math.max(0, Math.min(1, glowBase + kick))
  readonly property bool busy: breathing || kickAnimation.running || flashAnimation.running || ripplesRunning > 0

  readonly property bool breathing: breathAnimation.running || breath !== 1
  property real breath: 1
  property real kick: 0
  property real flash: 0
  property color flashColor: lightAccent
  property int ripplesRunning: 0
  property int nextRipple: 0

  // Calm baseline glow; a little lower with an empty field.
  property real glowBase: typedLength > 0 || holding ? 0.3 : 0.18
  Behavior on glowBase { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

  function shade(c, l, satBoost) {
    if (c.hslHue < 0) return Qt.hsla(0, 0, l, 1)
    return Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * satBoost + 0.1), l, 1)
  }
  readonly property color lightAccent: shade(accent, 0.78, 1.25)
  readonly property color brightAccent: shade(accent, 0.86, 1.1)

  // Ripple centre and reach, from the ink's bounds (probe) or inkRect.
  property rect ink: inkRect
  readonly property real cx: ink.x + ink.width / 2
  readonly property real cy: ink.y + ink.height / 2
  readonly property real reach: Math.max(8, Math.sqrt(ink.width * ink.width + ink.height * ink.height) / 2)
  readonly property real band: Math.max(14, Math.min(64, reach * 0.16))

  function ripple(fromR, toR, strength, color, ms) {
    var r = rippleRepeater.itemAt(nextRipple)
    nextRipple = (nextRipple + 1) % rippleRepeater.count
    if (r) r.play(fromR, toR, strength, color, ms)
  }

  function pulseGlow(amount) {
    kickAnimation.from = Math.min(0.5, kick + amount)
    kickAnimation.restart()
  }

  function breathe(peak, inMs, outMs) {
    if (reducedMotion) return
    breathIn.to = peak
    breathIn.duration = inMs
    breathOut.duration = outMs
    breathAnimation.restart()
  }

  function blink(color, peak, ms) {
    flashColor = color
    flashAnimation.stop()
    flashUp.to = Math.max(flash, peak)
    flashUp.duration = reducedMotion ? 110 : 60
    flashDown.duration = ms
    flashAnimation.start()
  }

  function keystroke(length, delta) {
    if (delta > 0) {
      if (reducedMotion) blink(lightAccent, 0.26, 380)
      else { ripple(0, 1, 0.85, lightAccent, 640); breathe(1.015, 90, 420) }
      pulseGlow(0.16)
    } else if (delta === -1) {
      if (reducedMotion) blink(lightAccent, 0.13, 300)
      else { ripple(0.7, 0, 0.45, lightAccent, 460); breathe(0.993, 80, 360) }
      pulseGlow(0.07)
    } else {
      // Clear: one soft inward sweep from the edges.
      if (reducedMotion) blink(lightAccent, 0.16, 360)
      else { ripple(1, 0, 0.55, lightAccent, 560); breathe(0.99, 100, 420) }
      pulseGlow(0.08)
    }
  }

  function submit() {
    blink(brightAccent, reducedMotion ? 0.5 : 0.62, reducedMotion ? 520 : 640)
    if (!reducedMotion) { ripple(0, 1.05, 1, brightAccent, 700); breathe(1.022, 110, 520) }
    pulseGlow(0.35)
  }

  function fail() {
    if (reducedMotion) blink(errorColor, 0.45, 520)
    else { ripple(0, 1.05, 1, errorColor, 720); breathe(0.985, 90, 480) }
    pulseGlow(0.12)
  }

  function reset() {
    breathAnimation.stop()
    kickAnimation.stop()
    flashAnimation.stop()
    breath = 1; kick = 0; flash = 0
    for (var i = 0; i < rippleRepeater.count; i++) {
      var r = rippleRepeater.itemAt(i)
      if (r) r.stop()
    }
  }

  // ---- Alpha probe: the ink's bounding box, so ripples start at its centre.
  function probe() {
    if (!source || !(width > 0 && height > 0)) return
    var k = Math.min(1, 256 / width, 256 / height)
    var pw = Math.max(8, Math.round(width * k)), ph = Math.max(8, Math.round(height * k))
    source.grabToImage(function(r) {
      probeCanvas.pw = pw; probeCanvas.ph = ph; probeCanvas.k = k
      probeImage.source = r.url
    }, Qt.size(pw, ph))
  }

  onWidthChanged: probeTimer.restartFresh()
  onHeightChanged: probeTimer.restartFresh()
  onInkRectChanged: { ink = inkRect; probeTimer.restartFresh() }
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
      var x0 = pw, y0 = ph, x1 = -1, y1 = -1
      try {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, pw, ph)
        ctx.drawImage(probeImage, 0, 0, pw, ph)
        var d = ctx.getImageData(0, 0, pw, ph).data
        for (var y = 0; y < ph; y++)
          for (var x = 0; x < pw; x++)
            if (d[(y * pw + x) * 4 + 3] > 24) {
              if (x < x0) x0 = x
              if (x > x1) x1 = x
              if (y < y0) y0 = y
              if (y > y1) y1 = y
            }
      } catch (e) {
        console.warn("hello-lock: pulse alpha probe failed: " + e)
      }
      probeImage.source = ""
      if (x1 >= 0) root.ink = Qt.rect(x0 / k, y0 / k, (x1 + 1 - x0) / k, (y1 + 1 - y0) / k)
      else if (probeTimer.tries++ < 6) probeTimer.restart()
    }
  }

  // White silhouette of the logo; ripples and blinks tint it.
  Item {
    id: whiteSil
    anchors.fill: parent
    visible: false
    layer.enabled: true
    MultiEffect { anchors.fill: parent; source: root.source; brightness: 1 }
  }

  // Everything we draw breathes around the ink's centre.
  Item {
    id: stage
    anchors.fill: parent
    transform: Scale { origin.x: root.cx; origin.y: root.cy; xScale: root.breath; yScale: root.breath }

    Repeater {
      id: rippleRepeater
      model: 4

      delegate: Item {
        id: ripple
        required property int index
        anchors.fill: parent
        property real t: 0
        property real fromR: 0
        property real toR: 1
        property real strength: 0
        property color tint: root.lightAccent
        property bool live: false
        // Radius eases out; the band fades as it travels.
        readonly property real eased: 1 - Math.pow(1 - t, 1.7)
        readonly property real r: (fromR + (toR - fromR) * eased) * root.reach
        readonly property real fade: Math.min(1, t / 0.06) * Math.pow(1 - t, 0.85)
        readonly property real outer: r + root.band

        function play(f, to, s, c, ms) {
          fromR = f; toR = to; strength = s; tint = c
          anim.duration = ms
          if (!live) root.ripplesRunning += 1
          live = true
          anim.restart()
        }
        function stop() {
          anim.stop()
          t = 0
          if (live) root.ripplesRunning -= 1
          live = false
        }

        // Soft ring mask (layered, never shown directly).
        Item {
          id: ring
          anchors.fill: parent
          visible: false
          layer.enabled: true
          Shape {
            anchors.fill: parent
            ShapePath {
              strokeColor: "transparent"
              fillGradient: RadialGradient {
                centerX: root.cx; centerY: root.cy
                focalX: root.cx; focalY: root.cy
                centerRadius: Math.max(1, ripple.outer)
                focalRadius: 0
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, ripple.r < root.band ? 1 - ripple.r / root.band : 0) }
                GradientStop { position: Math.max(0, (ripple.r - root.band) / ripple.outer); color: Qt.rgba(1, 1, 1, ripple.r < root.band ? 1 - ripple.r / root.band : 0) }
                GradientStop { position: Math.max(0.001, (ripple.r - root.band * 0.45) / ripple.outer); color: Qt.rgba(1, 1, 1, 0.55) }
                GradientStop { position: Math.max(0.002, ripple.r / ripple.outer); color: "white" }
                GradientStop { position: Math.max(0.003, (ripple.r + root.band * 0.45) / ripple.outer); color: Qt.rgba(1, 1, 1, 0.4) }
                GradientStop { position: 1; color: "transparent" }
              }
              PathRectangle { x: 0; y: 0; width: root.width; height: root.height }
            }
          }
        }

        MultiEffect {
          anchors.fill: parent
          source: whiteSil
          colorization: 1
          colorizationColor: ripple.tint
          maskEnabled: true
          maskSource: ring
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1
          opacity: ripple.live ? ripple.strength * ripple.fade : 0
        }

        NumberAnimation {
          id: anim
          target: ripple; property: "t"; from: 0; to: 1
          onFinished: ripple.stop()
        }
      }
    }

    // Whole-logo blink: submit, and every pulse under reduced motion.
    MultiEffect {
      anchors.fill: parent
      source: whiteSil
      colorization: 1
      colorizationColor: root.flashColor
      opacity: root.flash
    }
  }

  SequentialAnimation {
    id: breathAnimation
    NumberAnimation { id: breathIn; target: root; property: "breath"; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { id: breathOut; target: root; property: "breath"; to: 1; duration: 420; easing.type: Easing.InOutSine }
  }

  NumberAnimation {
    id: kickAnimation
    target: root; property: "kick"; to: 0
    duration: 620; easing.type: Easing.OutCubic
  }

  SequentialAnimation {
    id: flashAnimation
    NumberAnimation { id: flashUp; target: root; property: "flash"; duration: 60; easing.type: Easing.OutQuad }
    NumberAnimation { id: flashDown; target: root; property: "flash"; to: 0; duration: 400; easing.type: Easing.OutCubic }
  }
}
