import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "plugin/platform" as Platform

// Security core is independent of optional graphics and contains no unlock IPC.
ShellRoot {
  id: root
  readonly property string sourceDir: Quickshell.env("HELLO_LOCK_SOURCE")
  readonly property string configDir: Quickshell.env("HELLO_LOCK_CONFIG_DIR")
  readonly property string generation: Quickshell.env("HELLO_LOCK_GENERATION")
  property var config: ({})
  property var appearance: ({})
  property var lockPlan: ({})
  property bool statusReady: false
  readonly property real lockStartedAt: Number(Quickshell.env("HELLO_LOCK_STARTED")) || Date.now()
  property bool started: false
  property bool busy: false
  property bool answered: false
  property bool granted: false
  property bool released: false
  property bool releasing: false
  property bool everSecure: false
  property string entered: ""
  property string pending: ""
  property string failure: ""
  property int attempts: 0
  property string phase: "starting"
  readonly property string logo: expand(setting("logo") || (sourceDir + "/symbols/prompt.svg"))
  readonly property bool calm: config.motion === "reduced" || (config.motion !== "full" && (!desktopMotion.item || desktopMotion.item.calm))
  Loader {
    id: desktopMotion
    asynchronous: true
    active: root.config.motion !== "full" && root.config.motion !== "reduced"
    source: "plugin/platform/Motion.qml"
  }

  property bool cosmeticFinishRequested: false
  FileView {
    path: Quickshell.env("HELLO_LOCK_FINISH")
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var value = JSON.parse(text())
        if (value.generation !== root.generation || value.finish !== true) return
        root.cosmeticFinishRequested = true
        root.finishCosmetic()
      } catch (e) {}
    }
  }
  function finishCosmetic() {
    // A relock request may shorten a decoration only AFTER real PAM release.
    if (!root.released || !root.cosmeticFinishRequested) return
    try { if (splash.item) splash.item.finish() } catch (e) {}
    quickExit.start()
  }
  property int captureCompleted: 0
  property bool captureObserved: false
  property var snapshotFiles: ({})
  property var snapshotFinished: []
  property int powerDownToken: 0
  FileView {
    path: Quickshell.env("HELLO_LOCK_CAPTURE")
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var value = JSON.parse(text())
        if (value.generation !== root.generation || !value.files || typeof value.files !== "object") return
        root.snapshotFiles = !root.granted ? value.files : ({})
        root.snapshotFinished = []
        if (Object.keys(root.snapshotFiles).length) { root.captureObserved = true; root.powerDownToken += 1 }
        root.publish()
      } catch (e) {}
    }
  }
  FileView { id: captureAck; path: Quickshell.env("HELLO_LOCK_CAPTURE_ACK"); printErrors: false; atomicWrites: true }
  function snapshotUrlFor(screen) {
    var path = screen ? snapshotFiles[screen.name] : ""
    return typeof path === "string" && path.charAt(0) === "/" ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""
  }
  function snapshotDone(screen) {
    if (!screen || snapshotFinished.indexOf(screen.name) >= 0) return
    snapshotFinished = snapshotFinished.concat([screen.name])
    captureCompleted = snapshotFinished.length
    captureAck.setText(JSON.stringify({generation: generation, finished: snapshotFinished}))
    root.publish()
  }

  onCalmChanged: { if (root.started) root.publish() }

  function setting(name) {
    var branding = lockPlan.branding || {}
    return Object.prototype.hasOwnProperty.call(branding, name) ? branding[name] : config[name]
  }
  function cue(name) {
    try { if (extras.item) extras.item.cue(name) } catch (e) {}
  }
  Loader {
    id: extras
    asynchronous: true
    active: root.everSecure
    source: "Extras.qml"
    onLoaded: {
      item.pluginDir = root.sourceDir
      item.sessionId = Quickshell.env("HELLO_LOCK_SESSION")
      item.config = root.config
      item.calm = root.calm
      item.engaged = Qt.binding(function() { return session.secure && !root.granted && !root.busy })
      item.start()
    }
  }
  Connections {
    target: extras.item
    function onSelected(choice) { if (!root.granted) { root.lockPlan = choice; root.publish() } }
    function onStatusChanged() { root.statusReady = extras.item.status !== null; root.publish() }
  }

  function expand(value) {
    var path = String(value || "")
    if (path.indexOf("~/") === 0) return Quickshell.env("HOME") + path.slice(1)
    if (/^@[a-z0-9-]+$/.test(path)) return sourceDir + "/symbols/" + path.slice(1) + ".svg"
    return path.charAt(0) === "/" ? path : configDir + "/" + path
  }
  function color(name, fallback) {
    var value = appearance[name]
    return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value) ? value : fallback
  }
  Binding { target: Platform.Color; property: "baseBackground"; value: root.color("background", "#1a1b26") }
  Binding { target: Platform.Color; property: "baseForeground"; value: root.color("foreground", "#c0caf5") }
  Binding { target: Platform.Color; property: "baseAccent"; value: root.color("accent", "#7aa2f7") }
  Binding { target: Platform.Color; property: "baseUrgent"; value: root.color("urgent", "#f7768e") }
  FontLoader { source: "plugin/fonts/Oxanium-Variable.ttf" }
  FontLoader { source: "plugin/fonts/ShareTechMono-Regular.ttf" }
  FileView {
    path: root.configDir + "/config.json"
    blockLoading: true
    printErrors: false
    onLoaded: {
      try { var data = JSON.parse(text()); if (data && typeof data === "object" && !Array.isArray(data)) root.config = data } catch (e) {}
    }
  }
  FileView {
    path: root.configDir + "/appearance.json"
    printErrors: false
    onLoaded: {
      try { var data = JSON.parse(text()); if (data && typeof data === "object" && !Array.isArray(data)) root.appearance = data } catch (e) {}
    }
  }
  FileView { id: stateFile; path: Quickshell.env("HELLO_LOCK_STATE"); printErrors: false; atomicWrites: true }
  Connections {
    target: Quickshell
    function onScreensChanged() { root.publish() }
  }
  function publish() {
    // Never includes input, its length, PAM messages or responses.
    stateFile.setText(JSON.stringify({generation: generation, phase: phase, secure: session.secure, everSecure: root.everSecure,
      released: released, authenticating: busy, attempts: attempts,
      outputs: Quickshell.screens.length, calm: root.calm, captureObserved: root.captureObserved, captureFinished: root.captureCompleted, extrasReady: lockPlan.branding !== undefined,
      preset: typeof lockPlan.preset === "string" ? lockPlan.preset : "", statusReady: statusReady}))
  }
  function lockLost() {
    if (!root.everSecure || root.released || root.releasing || root.phase === "lock-lost") return
    // Never treat a compositor-forced loss as authenticated release. Clear all
    // pending grants before the supervisor creates a fresh lock/PAM context.
    root.busy = false
    root.granted = false
    root.pending = ""
    root.entered = ""
    root.answered = false
    authTimeout.stop()
    releaseGate.stop()
    if (pam.active) pam.abort()
    root.phase = "lock-lost"
    root.publish()
    Qt.exit(3)
  }
  function fail(message) {
    if (!busy) return
    busy = false
    pending = ""
    entered = ""
    authTimeout.stop()
    if (pam.active) pam.abort()
    attempts += 1
    failure = message || "Authentication failed"
    phase = "locked"
    publish()
    cue("error")
  }
  function submit(value) {
    if (!session.secure || busy || granted || released || pam.active || !value.length) return
    busy = true
    answered = false
    pending = value
    entered = ""
    failure = ""
    phase = "authenticating"
    publish()
    authTimeout.restart()
    if (!pam.start()) { fail("Password authentication is unavailable"); return }
  }
  function answerPrompt() {
    if (!busy || !pam.active || !pam.responseRequired) return
    // A password must never be sent to an echo-on or additional-factor prompt.
    if (pam.responseVisible || answered) { fail("Additional authentication step required"); return }
    answered = true
    var response = pending
    pending = ""
    pam.respond(response)
    response = ""
  }
  function completeAuthentication(result) {
    if (!root.busy || !session.secure || root.released) return
    if (result !== PamResult.Success || !root.answered) { root.fail("Authentication failed"); return }
    root.busy = false
    root.pending = ""
    root.entered = ""
    authTimeout.stop()
    root.granted = true
    root.phase = "authenticated"
    root.publish()
    if (root.config.unlockAnimation === false) {
      root.releaseAuthenticated()
    } else {
      releaseGate.start()
      try { if (Quickshell.env("HELLO_LOCK_PLAIN") !== "1") splash.active = true } catch (e) {}
    }
  }
  PamContext {
    id: pam
    config: "hello-lock"
    configDirectory: "/etc/pam.d"
    // Unset user resolves the process's real UID in Quickshell, not $USER.
    onPamMessage: root.answerPrompt()
    onCompleted: function(result) { root.completeAuthentication(result) }
    onError: root.fail("Password authentication is unavailable")
  }
  Timer { id: authTimeout; interval: 30000; onTriggered: root.fail("Authentication timed out") }
  function releaseAuthenticated() {
    if (!root.granted || !session.secure || root.released) return
    // Only this authenticated gate releases the compositor lock.
    root.releasing = true
    session.locked = false
    root.released = true
    root.phase = "released"
    root.publish()
    try {
      if (root.cosmeticFinishRequested) root.finishCosmetic()
      else if (root.config.unlockAnimation === false) { cue("unlock-short"); quickExit.start() }
      else if (splash.item) playSplash()
      else if (!splash.active || splash.status === Loader.Error) { cue("unlock-short"); quickExit.start() }
    } catch (e) { quickExit.start() }
    exitDelay.start()
  }
  Timer {
    id: releaseGate
    interval: 360
    onTriggered: root.releaseAuthenticated()
  }
  // Bounded post-authentication visual only; never releases a live lock on timeout.
  Timer { id: exitDelay; interval: 8500; onTriggered: Qt.quit() }
  Timer { id: quickExit; interval: 500; onTriggered: Qt.quit() }
  function playSplash() {
    splash.item.play(-1, {motion: root.calm ? "reduced" : "full",
      awaySeconds: Math.max(0, (Date.now() - root.lockStartedAt) / 1000),
      status: extras.item ? extras.item.status : null,
      greeting: root.config.greeting !== false, backdrop: root.config.unlockBackdrop !== false,
      maxDuration: typeof root.config.unlockDuration === "number" ? root.config.unlockDuration : 0})
  }
  Connections {
    target: splash.item
    function onShownChanged() { if (root.released && !splash.item.shown) quickExit.start() }
    function onSoundRequested(name) { root.cue(name) }
  }
  Loader {
    id: splash
    asynchronous: true
    active: false
    source: "plugin/UnlockSplash.qml"
    onStatusChanged: { if (status === Loader.Error && root.released) quickExit.start() }
    onLoaded: {
      item.pluginDir = root.sourceDir
      item.logoPath = root.logo
      var chosen = String(root.lockPlan.symbol !== undefined ? root.lockPlan.symbol : (root.setting("symbol") || ""))
      if (chosen === "@shuffle" || chosen === "shuffle") {
        var names = Object.keys(item.grids)
        chosen = names.length ? names[Math.floor(Math.random() * names.length)] : ""
      }
      item.symbolName = /^@[a-z0-9-]+$/.test(chosen) ? chosen.slice(1) : ""
      item.symbolPaths = chosen ? [root.expand(chosen)] : [root.logo]
      var parts = root.setting("symbolParts")
      if (Array.isArray(parts) && parts.length > 0) {
        item.symbolName = ""
        item.symbolPaths = parts.slice(0, 2).filter(function(path) { return typeof path === "string" && path.length > 0 }).map(root.expand)
      }
      item.tintSymbol = root.setting("tintLogo") !== false
      item.brand = root.setting("brand") || ""
      item.legendaryEnabled = root.config.legendary !== false
      item.backgroundPath = typeof root.appearance.wallpaper === "string" ? root.expand(root.appearance.wallpaper) : ""
      item.handoff = root.config.handoff || "shuffle"
      item.maxDuration = typeof root.config.unlockDuration === "number" ? root.config.unlockDuration : 0
      item.userName = root.config.name || Quickshell.env("USER") || "friend"
      item.reducedMotion = root.calm
      item.greetingEnabled = root.config.greeting !== false
      if (root.granted && !root.released) item.prime()
      else if (root.released) root.playSplash()
    }
  }
  WlSessionLock {
    id: session
    locked: false
    onSecureStateChanged: {
      if (secure) { root.everSecure = true; root.phase = "locked"; acquireTimeout.stop(); root.publish() }
      else root.lockLost()
    }
    onLockStateChanged: {
      if (!locked && root.everSecure && !root.releasing && !root.released) root.lockLost()
      else if (!locked && root.started && !root.granted) {
        root.phase = "denied"
        root.publish()
        Qt.exit(3)
      }
    }
    WlSessionLockSurface {
      id: surface
      color: Platform.Color.background
      function focusPassword() {
        if (!session.secure || root.busy || root.granted) return
        if (rich.item) rich.item.forcePasswordFocus()
        else plainInput.forceActiveFocus()
      }
      Connections {
        target: surface.contentItem.Window.window
        function onActiveChanged() {
          if (surface.contentItem.Window.active) Qt.callLater(surface.focusPassword)
        }
      }
      // A plain, independent fallback remains available if any graphic fails to load.
      Rectangle {
        anchors.fill: parent
        color: Platform.Color.background
        Column {
          anchors.centerIn: parent
          spacing: 16
          Text { text: "Hello Lock"; color: Platform.Color.foreground; font.pixelSize: 28 }
          TextInput {
            id: plainInput
            width: 288; height: 40
            color: Platform.Color.foreground
            echoMode: TextInput.Password
            passwordMaskDelay: 0
            enabled: !rich.item && session.secure && !root.busy && !root.granted
            focus: enabled
            onEnabledChanged: { if (enabled) Qt.callLater(surface.focusPassword) }
            onTextEdited: root.entered = text
            onAccepted: { var value = text; text = ""; root.submit(value); value = "" }
            Keys.onEscapePressed: { text = ""; root.entered = "" }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                text = ""
                root.entered = ""
                event.accepted = true
              }
            }
            Connections { target: root; function onEnteredChanged() { if (plainInput.text !== root.entered) plainInput.text = root.entered } }
          }
          Text { text: root.failure; color: Platform.Color.urgent; textFormat: Text.PlainText }
        }
      }
      Loader {
        id: rich
        asynchronous: true
        active: root.everSecure
        anchors.fill: parent
        source: Quickshell.env("HELLO_LOCK_PLAIN") === "1" ? "" : "plugin/LockView.qml"
        onLoaded: {
          item.queryHyprland = false
          item.snapshotSource = Qt.binding(function() { return root.snapshotUrlFor(surface.screen) })
          item.powerDownToken = Qt.binding(function() { return root.powerDownToken })
          item.screenIndex = Qt.binding(function() { return Quickshell.screens.indexOf(surface.screen) })
          item.logoPath = Qt.binding(function() { return root.logo })
          item.tintLogo = Qt.binding(function() { return root.setting("tintLogo") !== false })
          item.showClock = root.config.clock !== false
          item.reducedMotion = Qt.binding(function() { return root.calm })
          item.typingEffect = Qt.binding(function() { return root.lockPlan.effect || (root.config.typingEffect === "shuffle" ? "cells" : (root.config.typingEffect || "cells")) })
          item.screenCount = Qt.binding(function() { return Quickshell.screens.length })
          item.authenticatingPassword = Qt.binding(function() { return root.busy })
          item.failureMessage = Qt.binding(function() { return root.failure })
          item.failedAttempts = Qt.binding(function() { return root.attempts })
          item.inputEnabled = Qt.binding(function() { return session.secure && !root.busy && !root.granted })
          item.unlocking = Qt.binding(function() { return root.granted })
          item.passwordText = Qt.binding(function() { return root.entered })
        }
      }
      Connections {
        target: rich.item
        function onPowerDownFinished() { root.snapshotDone(surface.screen) }
        function onPasswordTextEdited(value) { root.entered = value }
        function onSubmitPassword(value) { root.submit(value) }
        function onClearFailureRequested() { root.failure = "" }
        function onTypingSoundRequested() {
          try { if (extras.item) extras.item.edited() } catch (e) {}
        }
      }
    }
  }
  Timer {
    id: acquireTimeout
    interval: 7000
    onTriggered: {
      if (session.secure) return
      root.phase = "unconfirmed"
      root.publish()
      // Exiting cannot unlock a compositor-held session. No locked=false fallback.
      Qt.exit(3)
    }
  }
  Component.onCompleted: {
    if (Number(Quickshell.env("HELLO_LOCK_RECOVERY")) > 0) root.failure = "Lock screen restored. Please enter your password."
    root.started = true
    root.publish()
    acquireTimeout.start()
    session.locked = true
  }
}
