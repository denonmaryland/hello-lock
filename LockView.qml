import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  // Hello Lock: logo shown above the field (SVG/PNG; tinted with the theme's lock
  // text colour unless tintLogo is false) and the clock toggle.
  property string logoPath: ""
  property bool tintLogo: true
  property bool showClock: true
  // Shared hooks from Service.qml: reduced motion (config "motion" or Hyprland
  // animations off), and this surface's screen position for multi-monitor timing.
  property bool reducedMotion: false
  property int screenIndex: 0
  property int screenCount: 1
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  // Set by the service after successful authentication: fades the view into
  // the unlock splash's stage color before the session is released.
  property bool unlocking: false
  // Wrong-password glitch is always a true red (theme "urgent" can be blue).
  readonly property color glitchRed: "#ff4d5e"
  // Must match UnlockSplash's stageDim so the handoff frame is identical.
  readonly property real unlockStageDim: 0.5

  // Lock-entry CRT power-down. The service points snapshotSource at a file
  // URL of a desktop screenshot taken just before locking, then bumps
  // powerDownToken. powerDownFinished() fires once the effect is over (or was
  // skipped because the snapshot could not be loaded) so the file can go.
  property string snapshotSource: ""
  property int powerDownToken: 0
  signal powerDownFinished()

  readonly property string placeholderText: "Enter Password"
  // Slim frosted pill instead of the stock 381×67 block with a 3px outline.
  readonly property int fieldWidth: 288
  readonly property int fieldHeight: 40
  readonly property int outlineThickness: 1
  readonly property int fieldFontSize: Style.font.subtitle
  readonly property int passwordDotFontSize: Style.font.body
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.body * 0.3)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  // Hairline border: faint foreground at rest, theme accent while typing,
  // theme error color after a failed attempt.
  readonly property color inputBorderColor: errorState
    ? Commons.Color.lock.borderError
    : (passwordText.length > 0 ? Util.alpha(Commons.Color.lock.borderActive, 0.85) : Util.alpha(Commons.Color.lock.text, 0.22))

  // Idle motion (wallpaper drift + wordmark breathing) only runs while the
  // lock is actually showing something; it pauses during the unlock handoff.
  readonly property bool ambientActive: visible && loadBackground && !unlocking

  // Wallpaper drift. driftPhase loops linearly; sin/cos of it give smooth
  // sine motion. driftStrength scales everything and eases to exactly 0 when
  // unlocking so the handoff frame is the untransformed splash stage. Scale
  // never drops below ~1.037, which overscans 1.85% per side — more than the
  // largest translate (1.2% × scale), so blurred edges never come into view.
  property real driftPhase: 0
  property real driftStrength: (unlocking || reducedMotion) ? 0 : 1
  Behavior on driftStrength { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
  readonly property real driftScale: 1 + driftStrength * (0.045 + 0.008 * Math.sin(driftPhase))
  readonly property real driftX: driftStrength * width * 0.012 * Math.sin(driftPhase)
  readonly property real driftY: driftStrength * height * 0.010 * Math.cos(driftPhase)

  NumberAnimation on driftPhase {
    from: 0
    to: 2 * Math.PI
    duration: 56000
    loops: Animation.Infinite
    running: root.loadBackground && !root.reducedMotion
    paused: running && !root.ambientActive
  }

  // Wordmark breathing: 0..1 over a ~5 s cycle (held at mid-glow when motion
  // is reduced).
  property real breath: 0
  SequentialAnimation on breath {
    loops: Animation.Infinite
    running: root.loadBackground && !root.reducedMotion
    paused: running && !root.ambientActive
    NumberAnimation { from: 0; to: 1; duration: 2500; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 2500; easing.type: Easing.InOutSine }
  }

  // Lock-entry reveal of the foreground (clock/logo/field), driven by the
  // power-down sequence; 1/1 at rest.
  property real revealOpacity: 1
  property real revealScale: 1

  // Wrong-password glitch state.
  property bool glitching: false
  property real glitchMix: 0
  property int glitchTick: 0
  property real ghostAX: 0
  property real ghostBX: 0
  property var glitchSlices: [
    { y: 0, h: 0, dx: 0, on: false },
    { y: 0, h: 0, dx: 0, on: false },
    { y: 0, h: 0, dx: 0, on: false }
  ]

  // Typing pulse: fires whenever the password grows by a character. The
  // typing effect hears every change of length (never the content).
  readonly property int typedLength: passwordInput.text.length
  property int lastTypedLength: 0
  onTypedLengthChanged: {
    if (typedLength > lastTypedLength && !unlocking && !reducedMotion) pulseAnimation.restart()
    var delta = typedLength - lastTypedLength
    lastTypedLength = typedLength
    if (delta !== 0) fxCall("keystroke", typedLength, delta)
  }

  // ---- Typing effect (typing/<name>.qml, see typing/README.md): what the logo
  // does while the password is typed. Loaded into the logo's padded box over
  // the host's plain logo; a missing or broken effect falls back to "off" and
  // never touches the field or authentication.
  property string typingEffect: "cells"
  readonly property int fxFullAt: 12
  property string fxBroken: ""
  readonly property string fxName: {
    var n = /^[a-z0-9-]+$/.test(typingEffect) ? typingEffect : "cells"
    return n === fxBroken ? "off" : n
  }
  readonly property var fx: fxLoader.status === Loader.Ready ? fxLoader.item : null
  readonly property real fxBase: fx && typeof fx.baseOpacity === "number" ? Math.max(0, Math.min(1, fx.baseOpacity)) : 1
  readonly property real fxGlow: fx && typeof fx.glowLevel === "number" ? Math.max(0, Math.min(1, fx.glowLevel)) : 0
  readonly property real fxKick: fx && typeof fx.glowKick === "number" ? Math.max(0, Math.min(0.3, fx.glowKick)) : 0
  // Submitted (or unlocking): the effect shows full until the verdict
  // arrives. Set only after the effect's submit() and cleared only after its
  // fail(), so effects that follow `level` never see the change first.
  property bool submitHold: false
  readonly property bool fxHolding: submitHold

  onTypingEffectChanged: fxBroken = ""
  onLoadBackgroundChanged: if (loadBackground) fxCall("reset")

  function fxCall(name, a, b) {
    var e = fx
    if (!e || typeof e[name] !== "function") return
    try { e[name](a, b) } catch (err) { console.warn("hello-lock typing/" + fxName + ": " + name + "() failed: " + err) }
  }

  function beginSubmitHold() {
    if (!submitHold) fxCall("submit")
    submitHold = true
    holdReleaseTimer.restart()
  }

  // After a submit the verdict normally lands within a frame or two of
  // authentication ending; if none comes (e.g. the submit was ignored),
  // fall back to the typed state.
  Timer {
    id: holdReleaseTimer
    interval: 400
    onTriggered: if (!root.authenticatingPassword && !root.unlocking) root.submitHold = false
  }

  // ---- Caps Lock and keyboard layout (for the hint after repeated failures).
  // capsOverride: preview-only (-1 = read the LED, 0/1 = forced).
  property int capsOverride: -1
  property bool capsLed: false
  readonly property bool capsLock: capsOverride >= 0 ? capsOverride > 0 : capsLed
  property string capsLedPath: ""
  property string activeKeymap: ""
  property int layoutCount: 1
  readonly property bool watchKeyboard: visible && loadBackground && !unlocking
  readonly property string failureHint: failedAttempts < 3 ? ""
    : (capsLock ? "Caps Lock is on" : (layoutCount > 1 && activeKeymap ? "Keyboard: " + activeKeymap : ""))
  property real statusTyped: 0
  readonly property string statusLine: "ACCESS DENIED · ATTEMPT " + Math.max(1, failedAttempts)

  onWatchKeyboardChanged: if (watchKeyboard) { capsFile.reload(); refreshKeymap() }

  function refreshKeymap() {
    if (!keymapProc.running) keymapProc.running = true
  }

  Process {
    id: capsLedProc
    running: true
    command: ["bash", "-c", "for d in /sys/class/leds/*capslock*; do [[ -r $d/brightness ]] && { echo \"$d/brightness\"; break; }; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.capsLedPath = String(text || "").trim()
    }
  }

  // sysfs has no change notifications; re-read the LED while the lock shows.
  FileView {
    id: capsFile
    path: root.capsLedPath
    printErrors: false
    onLoaded: root.capsLed = parseInt(String(text() || "0").trim()) > 0
  }

  Timer {
    interval: 400
    repeat: true
    running: root.watchKeyboard && root.capsLedPath.length > 0
    onTriggered: capsFile.reload()
  }

  Process {
    id: keymapProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var kbs = JSON.parse(String(text || "{}")).keyboards || []
          var main = kbs.filter(function(k) { return k.main })[0] || kbs[0]
          var count = 1
          for (var i = 0; i < kbs.length; i++)
            count = Math.max(count, String(kbs[i].layout || "").split(",").filter(function(s) { return s.trim() }).length)
          root.layoutCount = count
          root.activeKeymap = main ? String(main.active_keymap || "") : ""
        } catch (e) {
          root.layoutCount = 1
          root.activeKeymap = ""
        }
      }
    }
  }

  NumberAnimation {
    id: statusTypeAnimation
    target: root
    property: "statusTyped"
    from: 0
    to: root.statusLine.length
    duration: 300
  }

  // Clock strings; reassigning an identical string does not notify, so the
  // text only re-lays out when the minute (or day) actually changes.
  property string timeString: ""
  readonly property int clockFontSize: Math.round(height * 0.095)
  readonly property int dateFontSize: Math.max(11, Math.round(height * 0.016))
  property string dateString: ""

  function refreshClock() {
    var now = new Date()
    var h = now.getHours() % 12
    if (h === 0) h = 12
    var m = now.getMinutes()
    timeString = h + ":" + (m < 10 ? "0" + m : m)
    dateString = Qt.formatDate(now, "dddd · MMMM d").toUpperCase()
  }

  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  function startGlitch() {
    glitchTick = 0
    glitching = true
    glitchColorAnimation.restart()
    glitchTimer.restart()
    jitterGlitch()
  }

  function jitterGlitch() {
    var decay = Math.max(0.25, 1 - glitchTick / 12)
    var w = wordmark.width
    var h = wordmark.height
    var sign = Math.random() < 0.5 ? -1 : 1
    ghostAX = sign * (0.006 + Math.random() * 0.008) * w * decay
    ghostBX = -sign * (0.004 + Math.random() * 0.006) * w * decay
    var slices = []
    for (var i = 0; i < 3; i++) {
      var sh = h * (0.03 + Math.random() * 0.09)
      slices.push({
        y: h * (0.12 + Math.random() * 0.7),
        h: sh,
        dx: (Math.random() < 0.5 ? -1 : 1) * (0.01 + Math.random() * 0.025) * w * decay,
        on: Math.random() < 0.8
      })
    }
    glitchSlices = slices
  }

  function stopGlitch() {
    glitchTimer.stop()
    glitching = false
    ghostAX = 0
    ghostBX = 0
  }

  // Multi-monitor: each screen starts its power-down a beat after the one
  // before it, so the effect ripples across the outputs.
  readonly property int powerDownDelay: (reducedMotion || screenCount < 2) ? 0 : Math.min(Math.max(0, screenIndex), 6) * 90

  function startPowerDown() {
    if (!snapshotSource) return
    if (powerDownLoader.item) powerDownLoader.item.cancel()
    powerDownLoader.active = true
    var overlay = powerDownLoader.item
    if (!overlay || unlocking || !overlay.begin(snapshotSource)) {
      // Snapshot unusable: skip straight to the lock screen.
      finishPowerDown()
      return
    }
    revealOpacity = 0
    revealScale = reducedMotion ? 1 : 0.98
  }

  function finishPowerDown() {
    revealOpacity = 1
    revealScale = 1
    // Unload after the current animation tick; the overlay (and the
    // decoded snapshot) only exists while the effect plays.
    Qt.callLater(function() { powerDownLoader.active = false })
    powerDownFinished()
  }

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  // Small horizontal shake on a failed attempt, like macOS, plus a brief red
  // glitch of the wordmark.
  // Reduced motion keeps only the colour change and the status line. The
  // typing effect plays its own failure first, then the hold drops.
  onFailedAttemptsChanged: {
    if (failedAttempts > 0) {
      if (reducedMotion) glitchColorAnimation.restart()
      else { shakeAnimation.restart(); startGlitch() }
      fxCall("fail")
      holdReleaseTimer.stop()
      submitHold = false
      statusTypeAnimation.stop()
      statusTyped = reducedMotion ? statusLine.length : 0
      if (!reducedMotion) statusTypeAnimation.start()
      if (failedAttempts >= 3) refreshKeymap()
    }
  }
  onAuthenticatingPasswordChanged: {
    if (authenticatingPassword) beginSubmitHold()
    else if (submitHold) holdReleaseTimer.restart()
  }
  onPasswordTextChanged: syncPasswordText()
  onPowerDownTokenChanged: startPowerDown()
  onUnlockingChanged: {
    if (!unlocking) {
      submitHold = false
      return
    }
    // Arrive at the unlock fully charged (fingerprint unlocks included).
    holdReleaseTimer.stop()
    if (!submitHold) fxCall("submit")
    submitHold = true
    stopGlitch()
    glitchColorAnimation.stop()
    glitchMix = 0
    if (powerDownLoader.item && powerDownLoader.item.running) {
      powerDownLoader.item.cancel()
      finishPowerDown()
    }
  }
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  onVisibleChanged: if (visible) refreshClock()
  onReducedMotionChanged: if (reducedMotion) { shakeAnimation.stop(); inputField.shakeOffset = 0; stopGlitch() }
  Component.onCompleted: {
    refreshClock()
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Ticks every second but only changes text on a new minute; a per-second
  // check also catches up immediately after suspend/resume.
  Timer {
    interval: 1000
    repeat: true
    running: root.visible && !root.unlocking
    onTriggered: root.refreshClock()
  }

  Timer {
    id: glitchTimer
    interval: 40
    repeat: true
    onTriggered: {
      root.glitchTick += 1
      if (root.glitchTick >= 11) root.stopGlitch()
      else root.jitterGlitch()
    }
  }

  SequentialAnimation {
    id: glitchColorAnimation
    NumberAnimation { target: root; property: "glitchMix"; to: 1; duration: 50; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 220 }
    NumberAnimation { target: root; property: "glitchMix"; to: 0; duration: 180; easing.type: Easing.InOutQuad }
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    // Blurred once; only the finished output is moved for the drift, so the
    // blur passes are not re-run per frame. Identity transform when
    // driftStrength is 0, matching the unlock splash stage exactly.
    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
      scale: root.driftScale
      transform: Translate { x: root.driftX; y: root.driftY }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // Foreground: clock, wordmark and field. Fades out for the unlock
    // handoff; the inner item is driven by the power-down reveal.
    Item {
      id: unlockFade
      anchors.fill: parent
      opacity: root.unlocking ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

      Item {
        id: content
        anchors.fill: parent
        opacity: root.revealOpacity
        scale: root.revealScale

        // macOS-style clock, centered around 15% of the screen height —
        // well clear of the wordmark, which starts near 29%.
        Column {
          id: clock
          visible: root.showClock
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(parent.height * 0.15 - height / 2)
          spacing: Math.round(parent.height * 0.004)
          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Commons.Color.background
            shadowOpacity: 0.45
            shadowBlur: 0.7
            shadowVerticalOffset: 1
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.timeString
            color: Commons.Color.lock.text
            font.family: "Oxanium"
            font.weight: Font.Light
            font.variableAxes: ({ "wght": 270 })
            font.pixelSize: root.clockFontSize
            font.letterSpacing: root.clockFontSize * 0.01
            renderType: Text.QtRendering
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.dateString
            color: Util.alpha(Commons.Color.accent, 0.85)
            font.family: "Share Tech Mono"
            font.pixelSize: root.dateFontSize
            font.letterSpacing: root.dateFontSize * 0.35
            // Letter spacing trails the last glyph; pad the left by the same
            // amount so the line stays optically centered.
            leftPadding: root.dateFontSize * 0.35
          }
        }

        // Small off-screen copy used only to measure the logo's aspect ratio
        // (the visible image's size depends on it, so it cannot measure itself).
        Image {
          id: logoProbe
          visible: false
          source: wordmark.source
          sourceSize.width: 400
        }

        // The user's logo above the password field, tinted with the theme's lock
        // text color (unless tintLogo is false) so it follows every theme switch.
        // Purely decorative.
        Image {
          id: wordmark
          // Hero-sized: fit inside 72% of the screen width and 30% of its height,
          // keeping the logo's own aspect ratio (wide wordmarks reach the width
          // limit, square symbols the height limit). Centered at 44% height,
          // just above the optical middle.
          readonly property real boxWidth: parent.width * 0.72
          readonly property real boxHeight: parent.height * 0.30
          readonly property real aspect: logoProbe.implicitHeight > 0 ? logoProbe.implicitWidth / logoProbe.implicitHeight : 4
          width: Math.min(boxWidth, boxHeight * aspect)
          height: width / aspect
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -parent.height * 0.06
          source: root.logoPath ? "file://" + root.logoPath.split("/").map(encodeURIComponent).join("/") : ""
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(width * 1.5)
          visible: false
          layer.enabled: true
        }

        // What every logo effect below draws from. Tinting recolors by
        // brightness, so when tinted the logo is first flattened to a white
        // silhouette: black, white and coloured logos all take the theme colour.
        // Untinted logos pass through unchanged.
        Item {
          id: logoSource
          x: wordmark.x
          y: wordmark.y
          width: wordmark.width
          height: wordmark.height
          visible: false
          layer.enabled: true

          MultiEffect {
            anchors.fill: parent
            source: wordmark
            brightness: root.tintLogo ? 1 : 0
          }
        }

        // Breathing accent glow behind the wordmark. The blur of the static
        // source is cached; only this item's opacity animates.
        // The wordmark texture has almost no transparent margin, and a
        // MultiEffect with auto-padding stretches a layered source over its
        // padded rect (which used to inflate the letters ~7% wide and ~29%
        // tall). Render it once into an explicitly padded texture instead, so
        // the glow and shadow have room and the letters keep their true size.
        ShaderEffectSource {
          id: wordmarkSource
          readonly property real pad: Math.round(wordmark.height * 0.3)
          x: wordmark.x - pad
          y: wordmark.y - pad
          width: wordmark.width + pad * 2
          height: wordmark.height + pad * 2
          sourceItem: logoSource
          sourceRect: Qt.rect(-pad, -pad, width, height)
          visible: false
        }

        // Breathing accent glow behind the wordmark. The blur of the static
        // source is cached; only this item's opacity animates.
        MultiEffect {
          anchors.fill: wordmarkSource
          source: wordmarkSource
          autoPaddingEnabled: false
          visible: wordmark.status === Image.Ready
          // Glow grows with the typing effect's charge (and its keystroke kick).
          opacity: (0.15 + 0.20 * (root.reducedMotion ? 0.5 : root.breath)) * (0.3 + 0.7 * root.fxGlow) + root.fxKick
          colorization: 1
          colorizationColor: Commons.Color.accent
          blurEnabled: true
          blur: 1.0
          blurMax: 32
          blurMultiplier: 0.6
        }

        // Glitch RGB-split ghosts (only rendered during a failed attempt).
        MultiEffect {
          anchors.fill: wordmark
          source: logoSource
          visible: root.glitching && wordmark.status === Image.Ready
          opacity: 0.6
          colorization: 1
          colorizationColor: root.glitchRed
          transform: Translate { x: root.ghostAX }
        }

        MultiEffect {
          anchors.fill: wordmark
          source: logoSource
          visible: root.glitching && wordmark.status === Image.Ready
          opacity: 0.45
          colorization: 1
          colorizationColor: Commons.Color.accent
          transform: Translate { x: root.ghostBX }
        }

        // The logo itself, at the typing effect's base opacity (cells: the dim,
        // "uncharged" copy the lit cells draw over). The red glitch lifts it.
        MultiEffect {
          anchors.fill: wordmarkSource
          source: wordmarkSource
          autoPaddingEnabled: false
          visible: wordmark.status === Image.Ready
          opacity: root.fxBase + (1 - root.fxBase) * 0.6 * root.glitchMix
          Behavior on opacity { enabled: !root.glitching && root.glitchMix === 0; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
          // Untinted logos keep their own colours, but still flash red on a glitch.
          colorization: root.tintLogo ? 1 : root.glitchMix
          colorizationColor: root.mixColor(Commons.Color.lock.text, root.glitchRed, root.glitchMix)
          shadowEnabled: true
          shadowColor: Commons.Color.background
          shadowOpacity: 0.55
          shadowBlur: 0.8
          shadowVerticalOffset: 2
          shadowHorizontalOffset: 0
        }

        // Full-brightness, tinted logo in the padded box, handed to the
        // typing effect as its source (no shadow: effects add their own).
        Item {
          id: fxSource
          x: wordmarkSource.x
          y: wordmarkSource.y
          width: wordmarkSource.width
          height: wordmarkSource.height
          visible: false
          layer.enabled: true

          MultiEffect {
            anchors.fill: parent
            source: wordmarkSource
            autoPaddingEnabled: false
            colorization: root.tintLogo ? 1 : 0
            colorizationColor: Commons.Color.lock.text
          }
        }

        // The typing effect, over the plain logo and in the same box.
        Loader {
          id: fxLoader
          x: wordmarkSource.x
          y: wordmarkSource.y
          width: wordmarkSource.width
          height: wordmarkSource.height
          visible: wordmark.status === Image.Ready
          source: Qt.resolvedUrl("typing/" + root.fxName + ".qml")
          onStatusChanged: {
            if (status !== Loader.Error) return
            console.warn("hello-lock: typing effect \"" + root.fxName + "\" failed to load, using off")
            root.fxBroken = root.fxName
          }
          onLoaded: {
            var e = item
            try {
              e.source = fxSource
              e.inkRect = Qt.binding(function() {
                return wordmark.status === Image.Ready
                  ? Qt.rect(wordmarkSource.pad, wordmarkSource.pad, wordmark.width, wordmark.height)
                  : Qt.rect(0, 0, 0, 0)
              })
              e.level = Qt.binding(function() { return root.fxHolding ? 1 : Math.min(root.typedLength, root.fxFullAt) / root.fxFullAt })
              e.typedLength = Qt.binding(function() { return root.typedLength })
              e.holding = Qt.binding(function() { return root.fxHolding })
              e.reducedMotion = Qt.binding(function() { return root.reducedMotion })
              e.accent = Qt.binding(function() { return Commons.Color.accent })
              e.logoColor = Qt.binding(function() { return Commons.Color.lock.text })
              e.errorColor = Qt.binding(function() { return Commons.Color.lock.textError })
              // Optional extra: the drop shadow colour of the host's logo.
              if (e.backgroundColor !== undefined) e.backgroundColor = Qt.binding(function() { return Commons.Color.background })
            } catch (err) {
              console.warn("hello-lock typing/" + root.fxName + ": setup failed: " + err)
            }
            root.fxCall("reset")
          }
        }

        // Glitch slices: horizontal bands of the wordmark, displaced sideways.
        Repeater {
          model: 3
          Item {
            required property int index
            readonly property var slice: root.glitchSlices[index]
            visible: root.glitching && slice.on && wordmark.status === Image.Ready
            x: wordmark.x + slice.dx
            y: wordmark.y + slice.y
            width: wordmark.width
            height: slice.h
            clip: true

            MultiEffect {
              y: -parent.slice.y
              width: wordmark.width
              height: wordmark.height
              source: logoSource
              colorization: 1
              colorizationColor: root.glitchRed
            }
          }
        }

        Rectangle {
          id: inputField
          readonly property int borderTop: border.width
          readonly property int borderRight: border.width
          readonly property int borderBottom: border.width
          readonly property int borderLeft: border.width
          property real shakeOffset: 0
          width: root.fieldWidth
          height: root.fieldHeight
          // Rests in the lower part of the screen, apart from the logo.
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.horizontalCenterOffset: shakeOffset
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: parent.height * 0.22
          color: Util.alpha(Commons.Color.background, 0.45)
          border.width: root.outlineThickness
          border.color: root.inputBorderColor
          radius: height / 2
          clip: true

          Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

          SequentialAnimation {
            id: shakeAnimation
            NumberAnimation { target: inputField; property: "shakeOffset"; to: -10; duration: 50; easing.type: Easing.OutQuad }
            NumberAnimation { target: inputField; property: "shakeOffset"; to: 8; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: inputField; property: "shakeOffset"; to: -5; duration: 60; easing.type: Easing.InOutQuad }
            NumberAnimation { target: inputField; property: "shakeOffset"; to: 2; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: inputField; property: "shakeOffset"; to: 0; duration: 40; easing.type: Easing.OutQuad }
          }

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.topMargin: inputField.borderTop
            // Reserve the fingerprint icon's width on both sides so the centered
            // dots stay symmetric and never slide under the icon as they grow.
            anchors.rightMargin: inputField.borderRight + 16 + root.fingerprintReserve
            anchors.bottomMargin: inputField.borderBottom
            anchors.leftMargin: inputField.borderLeft + 16 + root.fingerprintReserve
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            activeFocusOnPress: true
            clip: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            color: Commons.Color.lock.text
            selectionColor: Commons.Color.lock.selection
            selectedTextColor: Commons.Color.lock.text
            font.family: Style.font.family
            font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
            font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
            cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
            cursorDelegate: Rectangle {
              width: 2
              color: Commons.Color.lock.text
              visible: passwordInput.cursorVisible
            }

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) {
                root.wakeRequested()
              }
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }

            onAccepted: {
              var submitted = root.passwordText
              // Fill the logo before the field clears, so the charge holds.
              if (submitted.length > 0) root.beginSubmitHold()
              root.passwordTextEdited("")
              if (submitted.length > 0) root.submitPassword(submitted)
            }

            Keys.onPressed: function(event) {
              root.wakeRequested()
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: passwordInput
            text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
            visible: passwordInput.text.length === 0
            color: root.authenticatingPassword ? Commons.Color.lock.text : (root.failureMessage.length > 0 ? Commons.Color.lock.textError : Commons.Color.lock.placeholder)
            font.family: Style.font.family
            font.pixelSize: root.fieldFontSize
            font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // Fingerprint hint pinned inside the field's right edge when a sensor is
          // enrolled, so the user knows they can touch to unlock instead of typing.
          // Matches hyprlock, which draws its fingerprint icon in the same spot.
          Text {
            id: fingerprintIcon
            objectName: "fingerprintIndicator"
            anchors.right: parent.right
            anchors.rightMargin: inputField.borderRight + 16
            anchors.verticalCenter: parent.verticalCenter
            visible: root.fingerprintConfigured
            text: "󰈷"
            color: Commons.Color.lock.placeholder
            font.family: Style.font.family
            font.pixelSize: root.fieldFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }

        // Keystroke pulse: a faint accent outline that grows out of the field
        // and fades. Sibling of the field (which clips) and purely visual.
        Rectangle {
          id: pulseRing
          property real spread: 0
          anchors.centerIn: inputField
          width: inputField.width + spread * 2
          height: inputField.height + spread * 2
          radius: height / 2
          color: "transparent"
          border.width: 1
          border.color: Commons.Color.lock.borderActive
          opacity: 0
          visible: opacity > 0

          ParallelAnimation {
            id: pulseAnimation
            NumberAnimation { target: pulseRing; property: "spread"; from: 0; to: 10; duration: 350; easing.type: Easing.OutCubic }
            NumberAnimation { target: pulseRing; property: "opacity"; from: 0.5; to: 0; duration: 350; easing.type: Easing.OutQuad }
          }
        }

        // Live Caps Lock badge beside the field, like macOS.
        Text {
          id: capsBadge
          anchors.left: inputField.right
          anchors.leftMargin: 12
          anchors.verticalCenter: inputField.verticalCenter
          textFormat: Text.PlainText
          text: "⇪ CAPS"
          color: Util.alpha(Commons.Color.lock.text, 0.8)
          font.family: "Share Tech Mono"
          font.pixelSize: root.dateFontSize
          font.letterSpacing: root.dateFontSize * 0.12
          opacity: root.capsLock && root.watchKeyboard ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        // Wrong password: a terminal-style status line under the field, typed
        // out like the unlock lines, and after a few attempts one calm hint.
        // Fixed positions, so nothing around them moves when they appear.
        Text {
          id: failureStatus
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(inputField.y + inputField.height + root.height * 0.024)
          textFormat: Text.PlainText
          text: root.statusLine.substring(0, Math.ceil(root.statusTyped))
          color: Commons.Color.lock.textError
          font.family: "Share Tech Mono"
          font.pixelSize: root.dateFontSize
          font.letterSpacing: root.dateFontSize * 0.35
          // Trailing letter spacing: pad left by the same so it stays centered.
          leftPadding: root.dateFontSize * 0.35
          opacity: root.errorState && root.failedAttempts > 0 && !root.unlocking ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        Text {
          id: failureHintText
          property string shown: ""
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(failureStatus.y + root.dateFontSize * 2.1)
          textFormat: Text.PlainText
          // Keeps its last text while fading out.
          text: shown
          color: Util.alpha(Commons.Color.lock.text, 0.75)
          font.family: Style.font.family
          font.pixelSize: Math.round(root.dateFontSize * 1.05)
          opacity: root.failureHint.length > 0 && !root.unlocking ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
          Connections {
            target: root
            function onFailureHintChanged() { if (root.failureHint.length > 0) failureHintText.shown = root.failureHint }
          }
        }
      }
    }
  }

  // Unlock handoff: tint the blurred wallpaper to the splash stage's look.
  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background
    opacity: root.unlocking ? root.unlockStageDim : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
  }

  // CRT power-down played over the desktop snapshot on lock entry. Loaded
  // only while it plays (an idle overlay in the scene was enough to shift the
  // unlock handoff frame by 1 LSB). Has no mouse or key handlers, so input
  // passes straight through to the password field underneath.
  Loader {
    id: powerDownLoader
    anchors.fill: parent
    active: false
    sourceComponent: Item {
      id: powerDownLayer
      anchors.fill: parent
      property real squashY: 1
      property real squashX: 1
      property real glow: 0
      property real tint: 0
      property real flareScale: 1
      readonly property bool running: powerDownAnimation.running || powerFadeAnimation.running

      function begin(url) {
        snapshot.source = url
        if (snapshot.status !== Image.Ready) {
          snapshot.source = ""
          return false
        }
        if (root.reducedMotion) powerFadeAnimation.start()
        else powerDownAnimation.start()
        return true
      }

      function cancel() {
        powerDownAnimation.stop()
        powerFadeAnimation.stop()
        snapshot.source = ""
      }

      Rectangle {
        id: crtBlack
        anchors.fill: parent
        color: "black"
      }

      Image {
        id: snapshot
        anchors.fill: parent
        asynchronous: false
        cache: false
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width
        sourceSize.height: height
        visible: false
      }

      MultiEffect {
        id: snapshotFx
        anchors.fill: parent
        source: snapshot
        visible: opacity > 0
        brightness: powerDownLayer.glow
        colorization: powerDownLayer.tint
        colorizationColor: Commons.Color.lock.text
        transform: Scale {
          origin.x: snapshotFx.width / 2
          origin.y: snapshotFx.height / 2
          xScale: powerDownLayer.squashX
          yScale: powerDownLayer.squashY
        }
      }

      Rectangle {
        id: flareDot
        width: Math.max(6, root.height * 0.008)
        height: width
        radius: width / 2
        anchors.centerIn: parent
        color: Commons.Color.lock.text
        opacity: 0
        visible: opacity > 0
        scale: powerDownLayer.flareScale
        layer.enabled: visible
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Commons.Color.accent
          shadowOpacity: 1
          shadowBlur: 1
          shadowScale: 2.2
        }
      }

      // Reduced motion: the desktop snapshot simply cross-fades to the lock.
      SequentialAnimation {
        id: powerFadeAnimation
        PropertyAction { target: crtBlack; property: "opacity"; value: 0 }
        ParallelAnimation {
          NumberAnimation { target: snapshotFx; property: "opacity"; to: 0; duration: 220; easing.type: Easing.OutCubic }
          NumberAnimation { target: root; property: "revealOpacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: { snapshot.source = ""; root.finishPowerDown() } }
      }

      SequentialAnimation {
        id: powerDownAnimation
        // Multi-monitor ripple: hold the frozen desktop for this screen's beat.
        PauseAnimation { duration: root.powerDownDelay }
        // Squash to a bright horizontal line.
        ParallelAnimation {
          NumberAnimation { target: powerDownLayer; property: "squashY"; to: 0.006; duration: 260; easing.type: Easing.InCubic }
          NumberAnimation { target: powerDownLayer; property: "glow"; to: 0.6; duration: 260; easing.type: Easing.InCubic }
        }
        // Line collapses to a dot.
        ParallelAnimation {
          NumberAnimation { target: powerDownLayer; property: "squashX"; to: 0.004; duration: 160; easing.type: Easing.InCubic }
          NumberAnimation { target: powerDownLayer; property: "tint"; to: 1; duration: 160; easing.type: Easing.InCubic }
          SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: flareDot; property: "opacity"; to: 1; duration: 70 }
          }
        }
        // Dot flares and fades.
        PropertyAction { target: snapshotFx; property: "opacity"; value: 0 }
        ParallelAnimation {
          NumberAnimation { target: powerDownLayer; property: "flareScale"; to: 2.4; duration: 150; easing.type: Easing.OutCubic }
          NumberAnimation { target: flareDot; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InQuad }
        }
        // Black lifts to reveal the lock screen.
        ParallelAnimation {
          NumberAnimation { target: crtBlack; property: "opacity"; to: 0; duration: 300; easing.type: Easing.OutCubic }
          NumberAnimation { target: root; property: "revealOpacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
          NumberAnimation { target: root; property: "revealScale"; to: 1; duration: 360; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: { snapshot.source = ""; root.finishPowerDown() } }
      }
    }
  }
}
