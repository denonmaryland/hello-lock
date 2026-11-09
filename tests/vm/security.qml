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
    }
  }
  Connections {
    target: test.service
    function onUnlockTransitionChanged() { if (test.service.unlockTransition) test.animatedTransitions += 1 }
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
    function quit(): string { Qt.quit(); return "ok" }
  }
  Timer { interval: 300000; running: true; onTriggered: Qt.quit() }
}
