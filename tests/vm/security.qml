import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Hello

// Guest-only fault injection. Never loaded by the plugin or visual previews.
ShellRoot {
  id: test
  readonly property bool permitted: Quickshell.env("USER") === "hellotest"
    && Quickshell.env("HELLO_LOCK_DISPOSABLE_GUEST") === "1"
  property var service: null
  property var lock: null
  property real lostAt: 0
  property var recoveries: []
  property int lossEvents: 0
  property int animatedTransitions: 0
  property bool watcherDisabled: false
  // Guest-only: while holding, every relock is released again as soon as it
  // is secure, so recovery stays open as long as the test needs.
  property bool holding: false
  property int holdDrops: 0
  property int reclaims: 0
  property var events: []

  Loader {
    id: loader
    active: test.permitted
    sourceComponent: Component { Hello.Service {} }
    onLoaded: {
      test.service = item
      for (var i = 0; i < item.data.length; i++) {
        var child = item.data[i]
        if (child.hasOwnProperty("secure") && child.hasOwnProperty("surface")) test.lock = child
      }
      if (!test.lock) throw new Error("Missing session lock")
    }
  }
  Connections {
    target: test.lock
    function onSecureStateChanged() {
      if (!test.lock.secure && test.service.lockRequested) {
        test.lostAt = Date.now()
        test.lossEvents += 1
      } else if (test.lock.secure && test.lostAt) {
        test.recoveries = test.recoveries.concat([Date.now() - test.lostAt])
        test.lostAt = 0
      }
      if (test.holding && test.lock.secure) Qt.callLater(test.dropHeld)
    }
  }
  function dropHeld() {
    if (!test.permitted || !test.holding || !test.lock.secure || !test.service.lockRequested) return
    test.lock.locked = false
    test.holdDrops += 1
  }
  Connections {
    target: test.service
    function onUnlockTransitionChanged() { if (test.service.unlockTransition) test.animatedTransitions += 1 }
    function onLastEventChanged() {
      if (test.service.lastEvent === "cover-keyboard: reclaiming") test.reclaims += 1
      // Service event names only (no input); kept for a failure report.
      test.events = test.events.concat([test.service.lastEvent]).slice(-300)
    }
  }
  function splashShown() {
    if (!test.service) return false
    for (var i = 0; i < test.service.data.length; i++) {
      var child = test.service.data[i]
      if (child.item && child.item.hasOwnProperty("shown") && child.item.hasOwnProperty("playToken")) return child.item.shown
    }
    return false
  }
  IpcHandler {
    target: "qa"
    function status(): string {
      return JSON.stringify({ready: !!test.lock && test.service.passwordPamConfigured,
        requested: test.service ? test.service.lockRequested : false,
        secure: test.lock ? test.lock.secure : false,
        attempts: test.service ? test.service.failedAttempts : 0,
        authenticating: test.service ? test.service.authenticatingPassword : false,
        lossEvents: test.lossEvents, recoveryMs: test.recoveries,
        animatedTransitions: test.animatedTransitions, watcherDisabled: test.watcherDisabled,
        animationEnabled: test.service ? test.service.config.unlockAnimation !== false : true,
        savedName: test.service ? test.service.userConfig.name : "",
        splashShown: test.splashShown(),
        covered: test.service ? test.service.lockCoverShown : false,
        coverKeyboard: test.service ? test.service.coverKeyboardHeld() : false,
        shortcutsInhibited: test.service ? test.service.coverShortcutsInhibited() : false,
        holding: test.holding, holdDrops: test.holdDrops, reclaims: test.reclaims,
        barrier: test.service ? test.service.compositorBarrier : false,
        fingerprintConfigured: test.service ? test.service.fingerprintConfigured : false})
    }
    function saveTiming(animated: bool): string {
      if (!test.permitted || test.service.currentlyLocked()) return "refused"
      for (var i = 0; i < test.service.data.length; i++) {
        var child = test.service.data[i]
        if (child.hasOwnProperty("watchChanges") && String(child.path).endsWith("/hello-lock/config.json")) {
          child.watchChanges = false
          test.watcherDisabled = true
        }
      }
      test.service.openSettings()
      Qt.callLater(function() {
        for (var i = 0; i < test.service.data.length; i++) {
          var child = test.service.data[i]
          if (child.item && child.item.hasOwnProperty("unlockAnimation")) {
            child.item.save({unlockAnimation: animated, unlockDuration: 600, name: "Guest saved settings"})
            child.item.requestExit("close")
            return
          }
        }
        throw new Error("Settings not ready")
      })
      return "saving"
    }
    function drop(): string {
      if (!test.permitted || !test.lock || !test.lock.secure || !test.service.lockRequested) return "refused"
      // Release the real Wayland lock without authenticating; production
      // handlers must notice this and reacquire it. No fake signal/success.
      test.lock.locked = false
      return "dropped"
    }
    function hold(): string {
      if (!test.permitted || !test.lock || !test.lock.secure || !test.service.lockRequested) return "refused"
      test.holding = true
      test.dropHeld()
      return "holding"
    }
    function release(): string {
      test.holding = false
      return "released"
    }
    // Anything typed while a relock flickered past must not prefix the password.
    function clearEntry(): string {
      if (!test.permitted) return "refused"
      test.service.enteredPassword = ""
      return "cleared"
    }
    function events(): string { return JSON.stringify(test.events) }
    function quit(): string { Qt.quit(); return "ok" }
  }
  Timer { interval: 400000; running: true; onTriggered: Qt.quit() }
}
