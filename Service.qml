import QtQuick
import "Presets.js" as Presets
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false
  // Hello Lock: true while the lock view dims before release into the splash.
  property bool unlockTransition: false
  property bool unlockGateDone: false
  // Hello Lock extras: lock time (for "time away"), telemetry from bin/hello-status
  // taken at lock, and a desktop snapshot for the power-down effect.
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  property string snapshotDir: ""
  property var snapshotFiles: ({})
  property var snapshotPending: []
  property var snapshotCleanupQueue: []
  property int snapshotEpoch: 0
  property real lockStartedAt: 0
  property var helloStatus: null

  // ---- Configuration: ~/.config/hello-lock/config.json (optional, live-reloaded).
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/hello-lock"
  readonly property var configDefaults: ({
    name: "", brand: "", logo: "", symbol: "", symbolParts: [], tintLogo: true,
    birthday: "", sounds: true, weather: true, powerDown: true, legendary: true, clock: true,
    motion: "auto", typingEffect: "cells", handoff: "shuffle", brandingPresets: [], presetMode: "manual", selectedPreset: ""
  })
  property var userConfig: ({})
  property string accountName: ""
  property var lockBranding: ({})
  property string lastBrandingPreset: ""
  property string brandingRotationKey: ""
  property bool realUnlockSplash: false
  readonly property bool brandingFrozen: lockRequested || unlockTransition || sessionLock.locked
    || (realUnlockSplash && unlockSplashLoader.item !== null && unlockSplashLoader.item.shown)
  readonly property var config: Object.assign({}, configDefaults, userConfig, brandingFrozen ? lockBranding : {})

  function playUnlockPreview(index, context) {
    realUnlockSplash = false
    unlockSplashLoader.item.play(index, context)
  }

  // Select once per lock. Previewing and repeated lock requests never advance it.
  function selectLockBranding() {
    var keys = ["brand", "logo", "symbol", "symbolParts", "tintLogo", "wordmarkText", "wordmarkStyle"]
    var defaults = {brand: "", logo: "", symbol: "", symbolParts: [], tintLogo: true, wordmarkText: "", wordmarkStyle: "blocks"}
    var chosen = userConfig || {}
    var pool = Presets.usable(chosen.brandingPresets)
    if (pool.length && (chosen.presetMode === "cycle" || chosen.presetMode === "shuffle")) {
      var rotationKey = JSON.stringify([chosen.presetMode, chosen.selectedPreset, pool.map(function(p) { return p.id })])
      var previous = (brandingRotationKey === rotationKey ? lastBrandingPreset : "") || chosen.selectedPreset || ""
      brandingRotationKey = rotationKey
      var index = pool.findIndex(function(p) { return p.id === previous })
      if (chosen.presetMode === "cycle") index = (index + 1) % pool.length
      else {
        var candidates = pool.filter(function(p) { return pool.length === 1 || p.id !== previous })
        var pick = candidates[Math.floor(Math.random() * candidates.length)]
        index = pool.indexOf(pick)
      }
      lastBrandingPreset = pool[index].id
      chosen = pool[index].branding
    }
    var snapshot = {}
    keys.forEach(function(k) { snapshot[k] = chosen[k] === undefined || chosen[k] === null ? defaults[k] : chosen[k] })
    lockBranding = snapshot
  }
  // Greeting name: config, else the account's full name, else the login name.
  readonly property string displayName: cleanConfigText(config.name) || accountName
    || (userName ? userName.charAt(0).toUpperCase() + userName.slice(1) : "friend")
  readonly property string defaultLogo: (omarchyPath || "/usr/share/omarchy") + "/logo.svg"
  readonly property string logoPath: expandPath(config.logo) || defaultLogo
  // Unlock symbol: explicit parts, else the symbol image, else the logo.
  readonly property var symbolPaths: {
    var parts = Array.isArray(config.symbolParts) ? config.symbolParts.map(expandPath).filter(function(x) { return x }) : []
    if (parts.length > 0) return parts.slice(0, 2)
    return [expandPath(effectiveSymbol) || logoPath]
  }

  // "symbol": "@shuffle" draws a different built-in symbol each lock (every
  // one before any repeats), kept through that unlock. Previews and repeated
  // lock requests never advance it.
  readonly property bool symbolShuffle: !(Array.isArray(config.symbolParts) && config.symbolParts.length > 0)
    && cleanConfigText(config.symbol) === "@shuffle"
  property var builtinSymbolNames: []
  property var symbolBag: []
  property string lockSymbol: ""
  readonly property string effectiveSymbol: symbolShuffle ? (lockSymbol ? "@" + lockSymbol : "") : cleanConfigText(config.symbol)

  function drawSymbol() {
    var pool = builtinSymbolNames
    if (pool.length === 0) return ""
    var bag = symbolBag.filter(function(n) { return pool.indexOf(n) >= 0 })
    if (bag.length === 0) {
      bag = pool.slice()
      for (var i = bag.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1))
        var t = bag[i]; bag[i] = bag[j]; bag[j] = t
      }
      // No back-to-back repeat across a refill.
      if (bag.length > 1 && bag[0] === lockSymbol) { var f = bag[0]; bag[0] = bag[bag.length - 1]; bag[bag.length - 1] = f }
    }
    var next = bag.shift()
    symbolBag = bag
    return next
  }

  Process {
    id: symbolListProc
    running: true
    command: ["bash", "-c", "cd \"$1\"/symbols 2>/dev/null && ls -1 -- *.svg", "symbol-list", root.pluginDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.builtinSymbolNames = String(text || "").split("\n").map(function(l) { return l.trim().replace(/\.svg$/, "") })
          .filter(function(n) { return /^[a-z0-9-]+$/.test(n) })
        // Something to show before the first lock (previews).
        if (!root.lockSymbol) root.lockSymbol = root.drawSymbol()
      }
    }
  }

  // Built-in symbol name ("@radar" -> "radar") when the unlock symbol is one of
  // symbols/, else "". Pixel animations use symbols/grids.json for these.
  readonly property string symbolName: {
    var parts = Array.isArray(config.symbolParts) ? config.symbolParts : []
    var v = parts.length === 0 ? effectiveSymbol : ""
    return /^@[a-z0-9-]+$/.test(v) ? v.slice(1) : ""
  }

  // Reduced motion: config "motion": "reduced" | "full" | "auto" (default).
  // auto follows Hyprland: animations:enabled = false means reduced.
  property bool hyprAnimations: true
  readonly property bool reducedMotion: config.motion === "reduced" || (config.motion !== "full" && !hyprAnimations)
  function refreshMotion() { if (!motionProc.running) motionProc.running = true }
  Process {
    id: motionProc
    running: true
    command: ["hyprctl", "-j", "getoption", "animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          // Bool options answer {"bool": true}; older Hyprland used {"int": 1}.
          var d = JSON.parse(String(text || "{}"))
          root.hyprAnimations = ("bool" in d) ? d.bool !== false : d.int !== 0
        } catch (e) { root.hyprAnimations = true }
      }
    }
  }

  // ---- Typing effect (typing/<name>.qml, see typing/README.md). Config
  // "typingEffect": an effect name, "shuffle" (a new one each lock, every
  // effect before any repeats; never "off") or "off". Unknown names: cells.
  readonly property var typingEffectsKnown: ["cells", "scanline", "liquid", "decrypt", "equalizer", "sweep", "pulse"]
  // Effects actually on disk (minus "off"); empty until listed.
  property var typingEffectsOnDisk: []
  readonly property var typingEffectPool: typingEffectsOnDisk.length > 0 ? typingEffectsOnDisk : typingEffectsKnown
  readonly property string typingEffect: {
    var v = String(config.typingEffect || "").toLowerCase()
    return v === "shuffle" || v === "off" || typingEffectPool.indexOf(v) >= 0 ? v : "cells"
  }
  property var typingBag: []
  property string lastShuffled: ""
  // Drawn when the session locks; the same on every monitor for that lock.
  property string lockTypingEffect: ""
  readonly property string lockViewTypingEffect: typingEffect === "shuffle" ? (lockTypingEffect || "cells") : typingEffect
  // Preview-only override (IPC previewTypingEffect); "" follows the config.
  property string previewTypingOverride: ""
  property string previewShuffled: ""
  readonly property string previewTypingEffect: {
    var v = previewTypingOverride || typingEffect
    return v === "shuffle" ? (previewShuffled || "cells") : v
  }

  function drawShuffle() {
    var pool = typingEffectPool
    if (pool.length === 0) return "cells"
    var bag = typingBag.filter(function(n) { return pool.indexOf(n) >= 0 })
    if (bag.length === 0) {
      bag = pool.slice()
      for (var i = bag.length - 1; i > 0; i--) {
        var j = Math.floor(Math.random() * (i + 1))
        var t = bag[i]; bag[i] = bag[j]; bag[j] = t
      }
      // No back-to-back repeat across a refill.
      if (bag.length > 1 && bag[0] === lastShuffled) { var f = bag[0]; bag[0] = bag[bag.length - 1]; bag[bag.length - 1] = f }
    }
    var pick = bag.shift()
    typingBag = bag
    lastShuffled = pick
    return pick
  }

  Process {
    id: typingListProc
    running: true
    command: ["bash", "-c", "cd \"$1\"/typing 2>/dev/null && ls -1 -- *.qml", "typing-list", root.pluginDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var names = String(text || "").split("\n").map(function(l) { return l.trim().replace(/\.qml$/, "") })
          .filter(function(n) { return /^[a-z0-9-]+$/.test(n) && n !== "off" })
        root.typingEffectsOnDisk = names
      }
    }
  }

  function screenIndexOf(screen) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) if (screens[i] === screen) return i
    return 0
  }

  function cleanConfigText(value) {
    return (typeof value === "string") ? value.trim() : ""
  }

  function expandPath(value) {
    var v = cleanConfigText(value)
    if (!v) return ""
    if (v.indexOf("~/") === 0) v = home + v.slice(1)
    // "@name" is a built-in symbol shipped in symbols/.
    if (/^@[a-z0-9-]+$/.test(v)) return pluginDir + "/symbols/" + v.slice(1) + ".svg"
    return v.charAt(0) === "/" ? v : configDir + "/" + v
  }

  function loadConfig(text) {
    var parsed = {}
    try {
      var t = String(text || "").trim()
      if (t) parsed = JSON.parse(t)
    } catch (e) {
      console.warn("hello-lock: ignoring invalid config.json: " + e)
      parsed = {}
    }
    userConfig = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
  }
  property bool snapshotReady: false
  property int snapshotVersion: 0
  property int powerDownToken: 0
  // Preview-only counter for simulating a wrong password on the preview window.
  property int previewFailures: 0
  // Preview-only typing simulation (IPC previewType/previewSubmit): a dummy
  // character count and a fake "checking" state. Never reaches PAM.
  property int previewTyped: 0
  property bool previewAuthenticating: false
  property bool previewFailureShown: false
  // Preview-only Caps Lock override (IPC previewCaps): -1 reads the real LED.
  property int previewCaps: -1
  // Preview-only motion override and power-down replay (IPC previewMotion /
  // previewPowerDown) so these paths can be checked without locking.
  property string previewMotion: ""
  property string previewSnapshot: ""
  property int previewPowerDownToken: 0

  function snapshotUrlFor(screen) {
    if (!snapshotReady || !screen || !screen.name) return ""
    var path = snapshotFiles[screen.name]
    return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") + "?v=" + snapshotVersion : ""
  }

  function splashContext() {
    return {
      awaySeconds: lockStartedAt > 0 ? (Date.now() - lockStartedAt) / 1000 : 0,
      status: helloStatus
    }
  }

  function playSound(name) {
    if (config.sounds === false) return
    soundProc.command = [pluginDir + "/bin/hello-sound", String(name)]
    soundProc.running = false
    soundProc.running = true
  }

  function clearSnapshots() {
    snapshotEpoch += 1
    snapshotExpiry.stop()
    snapshotReady = false
    snapshotFiles = ({})
    snapshotPending = []
    queueSnapshotCleanup(snapshotDir)
    snapshotDir = ""
  }

  function queueSnapshotCleanup(directory) {
    if (directory) snapshotCleanupQueue = snapshotCleanupQueue.concat([directory])
    if (cleanSnapshotProc.running || snapshotCleanupQueue.length === 0) return
    cleanSnapshotProc.command = [pluginDir + "/bin/hello-snapshot", "clean"].concat(snapshotCleanupQueue)
    snapshotCleanupQueue = []
    cleanSnapshotProc.running = true
  }

  function snapshotFinished(screen) {
    if (!screen) return
    snapshotPending = snapshotPending.filter(function(name) { return name !== screen.name })
    if (snapshotPending.length === 0) clearSnapshots()
  }

  function maybeStartPowerDown() {
    if (snapshotReady && sessionLock.locked) powerDownToken += 1
  }

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure

  // Decisions read the lock state afresh. A property binding that missed a change
  // notification once reported locked after an unlock, and a lock request before
  // suspend then took that for done and never locked the session.
  function currentlyLocked() {
    return lockRequested || sessionLock.locked || sessionLock.secure
  }
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early may be an orphan behind Hyprland's failsafe. It
  // may also be another shell's live lock, which Hyprland would let this one
  // take over and then strand on exit, so the helper answers undetermined while
  // another locker runs. Outputs are often still absent here, so ask until the
  // answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (currentlyLocked()) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || currentlyLocked() || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    unlockGate.stop()
    unlockGateDone = false
    unlockTransition = false
    if (!root.currentlyLocked()) {
      try { selectLockBranding() } catch (e) { lockBranding = {}; console.warn("hello-lock preset selection failed: " + e) }
      lockStartedAt = Date.now()
      root.refreshMotion()
      if (typingEffect === "shuffle") lockTypingEffect = drawShuffle()
      // Drawn every lock (cheap); used only when the branding says @shuffle.
      lockSymbol = drawSymbol() || lockSymbol
      if (!typingListProc.running) typingListProc.running = true
      clearSnapshots()
      try {
        if (config.powerDown === false || snapshotProc.running) throw "skip-snapshot"
        var names = []
        var screens = Quickshell.screens || []
        for (var si = 0; si < screens.length; si++) if (screens[si] && screens[si].name) names.push(screens[si].name)
        snapshotProc.epoch = snapshotEpoch
        snapshotProc.command = [pluginDir + "/bin/hello-snapshot", "capture"].concat(names)
        snapshotProc.running = true
      } catch (e) { if (e !== "skip-snapshot") console.warn("hello-lock snapshot failed: " + e) }
      try {
        refreshStatus()
        playSound("lock")
      } catch (e2) { console.warn("hello-lock lock extras failed: " + e2) }
    }
    try { if (unlockSplashLoader.item) unlockSplashLoader.item.finish() } catch (e3) { console.warn("unlock splash finish failed: " + e3) }
    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.currentlyLocked()) return

    // Hello Lock: only reached after PAM success. Dim the lock view and map the
    // splash under the lock first, so release reveals the splash rather than
    // the desktop. The gate is a fixed timer: it delays release, never blocks it.
    if (!unlockGateDone) {
      if (unlockGate.running) return
      unlockTransition = true
      realUnlockSplash = true
      try { if (unlockSplashLoader.item) unlockSplashLoader.item.prime() } catch (e) { console.warn("unlock splash prime failed: " + e) }
      unlockGate.start()
      return
    }
    unlockGateDone = false

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
    unlockTransition = false
    try { if (unlockSplashLoader.item) unlockSplashLoader.item.play(-1, root.splashContext()) } catch (e) { console.warn("unlock splash play failed: " + e) }
    clearSnapshots()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    if (!blankProcess.running) blankProcess.running = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    playSound("error")
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.maybeStartPowerDown()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Commons.Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested && !root.unlockTransition
        unlocking: root.unlockTransition
        snapshotSource: root.snapshotUrlFor(lockSurface.screen)
        powerDownToken: root.powerDownToken
        onPowerDownFinished: root.snapshotFinished(lockSurface.screen)
        logoPath: root.logoPath
        tintLogo: root.config.tintLogo !== false
        showClock: root.config.clock !== false
        reducedMotion: root.reducedMotion
        typingEffect: root.lockViewTypingEffect
        screenIndex: root.screenIndexOf(lockSurface.screen)
        screenCount: (Quickshell.screens || []).length
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: root.previewAuthenticating
      failureMessage: root.previewFailures > 0 && root.previewFailureShown ? "Authentication failed (" + root.previewFailures + ")" : ""
      failedAttempts: root.previewFailures
      inputEnabled: false
      logoPath: root.logoPath
      tintLogo: root.config.tintLogo !== false
      showClock: root.config.clock !== false
      reducedMotion: root.previewMotion === "reduced" || (root.previewMotion !== "full" && root.reducedMotion)
      loadBackground: root.previewVisible
      passwordText: "x".repeat(root.previewTyped)
      typingEffect: root.previewTypingEffect
      capsOverride: root.previewCaps
      snapshotSource: root.previewSnapshot
      powerDownToken: root.previewPowerDownToken
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.closePreview()
    }

    Item {
      anchors.fill: parent
      focus: root.previewVisible
      Keys.onEscapePressed: root.closePreview()
    }
  }

  function closePreview() {
    if (previewDemo.running) {
      previewDemo.stop()
      previewFailures = 0
      previewTyped = 0
      previewAuthenticating = false
      previewFailureShown = false
      previewTypingOverride = ""
    }
    previewVisible = false
  }

  // Settings "Preview": type a pretend password (dummy characters, never PAM),
  // check, fail, repeat until the preview is closed.
  Timer {
    id: previewDemo
    interval: 140
    repeat: true
    property int tick: 0
    onTriggered: {
      tick += 1
      if (tick <= 12) { root.previewFailureShown = false; root.previewAuthenticating = false; root.previewTyped = tick }
      else if (tick === 18) { root.previewAuthenticating = true; root.previewTyped = 0 }
      else if (tick === 25) { root.previewAuthenticating = false; root.previewFailureShown = true; root.previewFailures += 1 }
      else if (tick >= 40) tick = 0
    }
  }

  // Loaded indirectly so a broken splash can never stop the lock service loading.
  Loader {
    id: unlockSplashLoader
    source: "UnlockSplash.qml"
  }

  Binding {
    target: unlockSplashLoader.item
    property: "backgroundPath"
    value: root.backgroundPath
    when: unlockSplashLoader.status === Loader.Ready
  }

  Connections {
    target: unlockSplashLoader.item
    ignoreUnknownSignals: true
    function onSoundRequested(name) { root.playSound(name) }
  }

  Process {
    id: snapshotProc
    property int epoch: 0
    stdout: StdioCollector { id: snapshotOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.logEvent("hello-lock snapshot failed: " + exitCode); return }
      var capture
      try { capture = JSON.parse(snapshotOutput.text) } catch (e) { return }
      if (epoch !== root.snapshotEpoch || !root.lockRequested) {
        root.queueSnapshotCleanup(capture.directory)
        return
      }
      root.snapshotDir = capture.directory
      root.snapshotFiles = capture.files
      root.snapshotPending = Object.keys(capture.files)
      root.snapshotVersion += 1
      root.snapshotReady = true
      snapshotExpiry.restart()
      root.maybeStartPowerDown()
    }
  }

  Process {
    id: cleanSnapshotProc
    onExited: root.queueSnapshotCleanup("")
  }

  // Hot-unplugged screens or a failed visual must not retain a screenshot.
  Timer { id: snapshotExpiry; interval: 3000; onTriggered: root.clearSnapshots() }

  Process {
    id: soundProc
  }

  function refreshStatus() {
    var args = ["timeout", "3", pluginDir + "/bin/hello-status", "--name", displayName]
    var birthday = cleanConfigText(config.birthday)
    if (birthday) args.push("--birthday", birthday)
    if (config.weather === false) args.push("--no-weather")
    statusProc.command = args
    statusProc.running = false
    statusProc.running = true
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.helloStatus = JSON.parse(String(text || "").trim()) } catch (e) { root.helloStatus = null }
      }
    }
  }

  FileView {
    id: configFile
    path: root.configDir + "/config.json"
    watchChanges: true
    printErrors: false
    // text() is stale inside fileChanged; reload and parse in onLoaded.
    onFileChanged: reload()
    onLoaded: { root.configSeen = String(text() || "").trim().length > 0; root.loadConfig(text()) }
    onLoadFailed: root.loadConfig("")
  }

  // Full name from the account (GECOS field), used when config.name is empty.
  Process {
    id: accountNameProc
    running: true
    command: ["getent", "passwd", root.userName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var fields = String(text || "").trim().split(":")
        root.accountName = fields.length > 4 ? fields[4].split(",")[0].trim() : ""
      }
    }
  }

  Binding { target: unlockSplashLoader.item; property: "userName"; value: root.displayName; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "brand"; value: root.cleanConfigText(root.config.brand); when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "symbolPaths"; value: root.symbolPaths; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "tintSymbol"; value: root.config.tintLogo !== false; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "logoPath"; value: root.logoPath; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "handoff"; value: String(root.config.handoff || "shuffle"); when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "legendaryEnabled"; value: root.config.legendary !== false; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "symbolName"; value: root.symbolName; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "pluginDir"; value: root.pluginDir; when: unlockSplashLoader.status === Loader.Ready }
  Binding { target: unlockSplashLoader.item; property: "reducedMotion"; value: root.reducedMotion; when: unlockSplashLoader.status === Loader.Ready }

  Binding {
    target: unlockSplashLoader.item
    property: "preload"
    value: root.lockRequested
    when: unlockSplashLoader.status === Loader.Ready
  }

  Binding {
    target: unlockSplashLoader.item
    property: "backgroundVersion"
    value: root.backgroundVersion
    when: unlockSplashLoader.status === Loader.Ready
  }

  Timer {
    id: unlockGate
    interval: 360
    repeat: false
    onTriggered: {
      root.unlockGateDone = true
      root.finishUnlock()
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    // $PPID is this shell: a crash re-execs in place, so its pid is the one to skip.
    command: ["bash", "-c", "omarchy-hyprland-session-lock-stranded \"$PPID\""]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.currentlyLocked()
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  // ---- Onboarding (Onboarding.qml): first run, or `omarchy-shell lock onboarding`.
  // Loaded indirectly like the splash, never while a lock is requested, and it
  // has no access to authentication.
  property bool onboardingOpen: false
  property bool configSeen: false

  function openOnboarding() {
    if (lockRequested || currentlyLocked()) return false
    onboardingOpen = true
    return true
  }

  Loader {
    id: onboardingLoader
    active: root.onboardingOpen && !root.lockRequested
    source: "Onboarding.qml"
    onLoaded: {
      item.pluginDir = root.pluginDir
      item.configDir = root.configDir
      item.suggestedName = root.accountName
        || (root.userName ? root.userName.charAt(0).toUpperCase() + root.userName.slice(1) : "")
      item.currentConfig = root.userConfig
      item.backgroundPath = root.backgroundPath
      item.backgroundVersion = root.backgroundVersion
      item.reducedMotion = root.reducedMotion
      item.start()
    }
    onStatusChanged: if (status === Loader.Error) { console.warn("hello-lock: onboarding failed to load"); root.onboardingOpen = false }
  }

  Connections {
    target: onboardingLoader.item
    ignoreUnknownSignals: true
    function onClosed() { root.onboardingOpen = false }
    function onDismissed() { onboardingDoneProc.running = true }
    function onTryUnlockRequested() { tryUnlockTimer.restart() }
  }

  Process {
    id: onboardingDoneProc
    command: [root.pluginDir + "/bin/hello-config", "done"]
  }

  // Once per load: make menu backups left readable by 0.5.0 and older private,
  // even if Settings is never opened. Never touches the menu itself.
  Process {
    id: menuBackupsProc
    running: true
    command: [root.pluginDir + "/bin/hello-menu", "secure"]
  }

  // After saving, wait for config.json to reload, then play the unlock as a demo.
  Timer {
    id: tryUnlockTimer
    interval: 700
    onTriggered: {
      if (root.currentlyLocked() || !unlockSplashLoader.item) return
      root.refreshBackground()
      root.playUnlockPreview(-1, { awaySeconds: 0, status: root.helloStatus })
    }
  }

  // ---- Settings (Settings.qml): `omarchy-shell lock settings`. Same rules as
  // onboarding: loaded indirectly, never while a lock is requested, no access
  // to authentication.
  property bool settingsOpen: false
  property bool settingsAway: false

  function openSettings() {
    if (lockRequested || currentlyLocked()) return false
    onboardingOpen = false
    settingsAway = false
    settingsOpen = true
    return true
  }

  onLockRequestedChanged: if (lockRequested) { settingsOpen = false; settingsAway = false }

  Loader {
    id: settingsLoader
    active: root.settingsOpen && !root.lockRequested
    source: "Settings.qml"
    onLoaded: {
      item.pluginDir = root.pluginDir
      item.configDir = root.configDir
      item.suggestedName = root.accountName
        || (root.userName ? root.userName.charAt(0).toUpperCase() + root.userName.slice(1) : "")
      item.currentConfig = root.userConfig
      item.start()
    }
    onStatusChanged: if (status === Loader.Error) { console.warn("hello-lock: settings failed to load"); root.settingsOpen = false }
  }
  Binding { target: settingsLoader.item; property: "away"; value: root.settingsAway; when: settingsLoader.status === Loader.Ready }

  Connections {
    target: settingsLoader.item
    ignoreUnknownSignals: true
    function onClosed() { root.settingsOpen = false }
    function onSetupRequested() { root.settingsOpen = false; root.openOnboarding() }
    function onUnlockPreviewRequested(symbol, handoff) {
      if (root.currentlyLocked() || !unlockSplashLoader.item) return
      root.settingsAway = true
      settingsReturn.armed = false
      // Let the config.json write land first, as after setup.
      settingsUnlockTimer.symbol = symbol
      settingsUnlockTimer.handoff = handoff || ""
      settingsUnlockTimer.restart()
    }
    function onLockPreviewRequested(effect) {
      root.settingsAway = true
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewTypingOverride = effect === "shuffle" ? "" : effect
      root.previewShuffled = root.drawShuffle()
      root.previewFailures = 0
      previewDemo.tick = 0
      previewDemo.start()
      root.previewVisible = true
    }
  }

  Timer {
    id: settingsUnlockTimer
    interval: 450
    property string symbol: ""
    property string handoff: ""
    onTriggered: {
      if (root.currentlyLocked() || !unlockSplashLoader.item) { root.settingsAway = false; return }
      root.refreshBackground()
      if (symbol && !unlockSplashLoader.item.knowsSymbol(symbol)) symbol = ""
      root.playUnlockPreview(-1, { awaySeconds: 3600, status: root.helloStatus, symbol: symbol, handoff: handoff })
      settingsReturn.armed = true
      settingsReturnFallback.restart()
    }
  }

  // A splash that never shows must not leave settings hidden.
  Timer {
    id: settingsReturnFallback
    interval: 15000
    onTriggered: if (settingsReturn.armed) { settingsReturn.armed = false; root.settingsAway = false }
  }

  // Bring settings back once a preview it started is over.
  Connections {
    target: unlockSplashLoader.item
    ignoreUnknownSignals: true
    function onShownChanged() {
      if (!unlockSplashLoader.item.shown) root.realUnlockSplash = false
      if (settingsReturn.armed && !unlockSplashLoader.item.shown) { settingsReturn.armed = false; root.settingsAway = false }
    }
  }
  QtObject { id: settingsReturn; property bool armed: false }
  onPreviewVisibleChanged: if (!previewVisible && settingsAway && !settingsReturn.armed) settingsAway = false

  // First run: no config.json and onboarding never finished.
  Process {
    id: onboardingPendingProc
    command: [root.pluginDir + "/bin/hello-config", "pending"]
    onExited: function(code) {
      if (code === 0 && !root.configSeen) root.openOnboarding()
    }
  }

  Timer {
    id: onboardingStartTimer
    interval: 3000
    onTriggered: onboardingPendingProc.running = true
  }

  // Bundled fonts (SIL OFL 1.1), registered app-wide so every view can use the
  // "Oxanium" and "Share Tech Mono" families without a system install.
  FontLoader { source: Qt.resolvedUrl("fonts/Oxanium-Variable.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/ShareTechMono-Regular.ttf") }

  // First telemetry read waits for config.json and the account name to load.
  Timer { id: statusStartTimer; interval: 1500; onTriggered: root.refreshStatus() }

  Component.onCompleted: {
    refreshBackground()
    statusStartTimer.start()
    onboardingStartTimer.start()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.currentlyLocked() && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.currentlyLocked() ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.currentlyLocked(),
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      // Shuffle: a fresh draw each time the preview opens, like a new lock.
      if (!root.previewVisible) root.previewShuffled = root.drawShuffle()
      root.previewVisible = true
      return "ok"
    }

    // Typing effect for this preview only: a name, "shuffle" (draws the next
    // one) or "" (follow the config). Answers the effect now shown.
    function previewTypingEffect(name: string): string {
      var v = String(name || "").trim().toLowerCase()
      if (v && v !== "shuffle" && v !== "off" && root.typingEffectPool.indexOf(v) < 0) v = "cells"
      if (v === "shuffle" || (!v && root.typingEffect === "shuffle")) root.previewShuffled = root.drawShuffle()
      root.previewTypingOverride = v
      return root.previewTypingEffect
    }

    function previewFailure(): string {
      if (!root.previewVisible) return "preview-hidden"
      root.previewAuthenticating = false
      root.previewTyped = 0
      root.previewFailureShown = true
      root.previewFailures += 1
      return "ok"
    }

    // Preview-only: pretend `count` characters are typed (dummy text in the
    // preview LockView; no keyboard, no PAM, never the real lock).
    function previewType(count: int): string {
      if (!root.previewVisible) return "preview-hidden"
      root.previewAuthenticating = false
      root.previewTyped = Math.max(0, Math.min(64, count))
      if (root.previewTyped > 0) root.previewFailureShown = false
      return "ok"
    }

    // Preview-only: show the "checking" state as after Enter; follow with
    // previewFailure (wrong password) or previewType (back to typing).
    // Preview-only: force the Caps Lock indicator (1 on, 0 off, -1 real LED).
    function previewCaps(state: int): string {
      root.previewCaps = state < 0 ? -1 : (state > 0 ? 1 : 0)
      return "ok"
    }

    // Preview-only: "reduced", "full" or "" (follow config / Hyprland).
    function previewMotion(mode: string): string {
      root.previewMotion = (mode === "reduced" || mode === "full") ? mode : ""
      return "ok"
    }

    // Preview-only: replay the lock-entry power-down over an image file
    // (e.g. a grim screenshot taken just before opening the preview).
    function previewPowerDown(path: string): string {
      if (!root.previewVisible) return "preview-hidden"
      root.previewSnapshot = "file://" + encodeURI(String(path)) + "?v=" + Date.now()
      root.previewPowerDownToken += 1
      return "ok"
    }

    function previewSubmit(): string {
      if (!root.previewVisible) return "preview-hidden"
      root.previewAuthenticating = true
      root.previewTyped = 0
      return "ok"
    }

    function hidePreview(): string {
      root.previewFailures = 0
      root.previewTyped = 0
      root.previewAuthenticating = false
      root.previewFailureShown = false
      root.previewCaps = -1
      root.previewMotion = ""
      root.previewSnapshot = ""
      root.previewTypingOverride = ""
      root.previewVisible = false
      return "ok"
    }

    function splashPreview(): string {
      if (root.currentlyLocked()) return "locked"
      if (!unlockSplashLoader.item) return "unavailable"
      root.refreshBackground()
      root.refreshStatus()
      root.playUnlockPreview(-1, { awaySeconds: 3600, status: root.helloStatus })
      return "ok"
    }

    function splashPreviewVariant(index: int): string {
      if (root.currentlyLocked()) return "locked"
      if (!unlockSplashLoader.item) return "unavailable"
      root.refreshBackground()
      root.playUnlockPreview(index, { awaySeconds: 3600, status: root.helloStatus })
      return "ok"
    }

    // kind: "short", "away", "special" or "" (preview helpers for the extras).
    function splashPreviewMode(index: int, kind: string): string {
      if (root.currentlyLocked()) return "locked"
      if (!unlockSplashLoader.item) return "unavailable"
      root.refreshBackground()
      var status = root.helloStatus
      if (kind === "special") status = Object.assign({}, status || {}, { special: { status: "BIRTHDAY PROTOCOL", text: "Happy birthday, " + root.displayName + "." } })
      root.playUnlockPreview(index, {
        awaySeconds: kind === "short" ? 30 : 8040,
        status: status,
        forceShort: kind === "short",
        forceGreeting: (kind === "away" || kind === "special") ? kind : ""
      })
      return "ok"
    }

    // Variant `index` (0-10, 11 = legendary, -1 = random) with built-in symbol
    // `name` ("radar"), or the configured symbol if "", for this one play only.
    function splashPreviewSymbol(name: string, index: int): string {
      if (root.currentlyLocked()) return "locked"
      if (!unlockSplashLoader.item) return "unavailable"
      if (name !== "" && !unlockSplashLoader.item.knowsSymbol(name)) return "unknown-symbol"
      root.refreshBackground()
      root.playUnlockPreview(index, { awaySeconds: 3600, status: root.helloStatus, symbol: name })
      return "ok"
    }

    // Preview-only motion override for one play. motion: "reduced" (calm
    // fade), "full", or "secondary" (the unfocused-monitor version).
    // A named logo handoff transition (handoff/<name>.qml), with motion on.
    function splashPreviewHandoff(name: string): string {
      if (root.currentlyLocked()) return "locked"
      if (!unlockSplashLoader.item) return "unavailable"
      if (!unlockSplashLoader.item.knowsHandoff(String(name).toLowerCase())) return "unknown-handoff"
      root.refreshBackground()
      root.playUnlockPreview(-1, { awaySeconds: 3600, status: root.helloStatus, motion: "full", handoff: String(name) })
      return "ok"
    }
    function splashPreviewMotion(index: int, motion: string): string {
      if (root.currentlyLocked()) return "locked"
      if (!unlockSplashLoader.item) return "unavailable"
      root.refreshBackground()
      root.playUnlockPreview(index, { awaySeconds: 3600, status: root.helloStatus,
        motion: motion === "secondary" ? "full" : motion, secondary: motion === "secondary" })
      return "ok"
    }

    function refreshStatus(): string {
      root.refreshStatus()
      return "ok"
    }

    function statusJson(): string {
      return JSON.stringify(root.helloStatus)
    }

    // Open the first-run setup screen (name, birthday, logo).
    function onboarding(): string {
      root.settingsOpen = false
      return root.openOnboarding() ? "ok" : "locked"
    }

    // Open the settings window (every option on one page).
    function settings(): string {
      return root.openSettings() ? "ok" : "locked"
    }

    // Effective Hello Lock settings, for checking a config.json edit.
    function configJson(): string {
      return JSON.stringify({ name: root.displayName, logo: root.logoPath, symbol: root.symbolPaths,
        config: root.config, pluginDir: root.pluginDir })
    }
  }
}
