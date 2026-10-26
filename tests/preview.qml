import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "plugin" as Hello

// Launched by run-preview.py in a disposable config root. Only visual types
// are instantiated. Service.qml is compiled, never created (no PAM/locking).
ShellRoot {
  id: root
  property var serviceComponent
  Component.onCompleted: {
    serviceComponent = Qt.createComponent("plugin/Service.qml")
    console.log("review service compile: " + serviceComponent.status + " " + serviceComponent.errorString())
  }
  PanelWindow {
    id: preview
    visible: false
    implicitWidth: 1000
    implicitHeight: 650
    color: "#101315"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hello-lock-review"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Hello.LockView {
      id: view
      anchors.fill: parent
      inputEnabled: false
      loadBackground: preview.visible
      logoPath: Qt.resolvedUrl("plugin/symbols/radar.svg").toString().replace("file://", "")
    }
  }
  Hello.UnlockSplash {
    id: splash
    pluginDir: Quickshell.env("HELLO_LOCK_SOURCE")
    symbolPaths: [pluginDir + "/symbols/radar.svg"]
    symbolName: "radar"
    userName: "Ada"
  }
  Loader {
    id: setup
    active: false
    source: "plugin/Onboarding.qml"
    onLoaded: {
      item.pluginDir = Quickshell.env("HELLO_LOCK_SOURCE")
      item.configDir = Quickshell.env("XDG_CONFIG_HOME") + "/hello-lock"
      item.suggestedName = "Ada"
      item.currentConfig = {weather: false}
      item.start()
    }
  }
  Connections {
    target: setup.item
    function onClosed() { setup.active = false }
  }
  Timer { id: timeout; running: true; interval: 120000; onTriggered: Qt.quit() }
  IpcHandler {
    target: "review"
    function status(): string {
      return JSON.stringify({serviceCompiled: root.serviceComponent.status === Component.Ready,
        preview: preview.visible, effect: view.typingEffect,
        setup: setup.status, wordmarkReady: setup.item ? setup.item.wordmarkReady : false,
        wordmarkError: setup.item ? setup.item.wordmarkError : "",
        wordmarkPreview: setup.item ? setup.item.wordmarkPreview.slice(0, 30) : "",
        splash: splash.shown, calm: splash.calm})
    }
    function effect(name: string, count: int, reduced: bool): string {
      timeout.restart()
      setup.active = false
      splash.finish()
      view.reducedMotion = reduced
      view.typingEffect = name
      view.authenticatingPassword = false
      view.failureMessage = ""
      view.passwordText = "x".repeat(Math.max(0, Math.min(64, count)))
      preview.visible = true
      return "ok"
    }
    function submit(): string { view.authenticatingPassword = true; view.passwordText = ""; return "ok" }
    function failure(): string {
      view.authenticatingPassword = false
      view.passwordText = ""
      view.failureMessage = "Authentication failed"
      view.failedAttempts += 1
      return "ok"
    }
    function onboarding(): string {
      timeout.restart(); preview.visible = false; splash.finish(); setup.active = true
      return "ok"
    }
    function wordmark(text: string, style: string): string {
      if (!setup.item) return "unavailable"
      setup.item.logoChoice = "wordmark"
      setup.item.wordmarkText = text
      setup.item.wordmarkStyle = style
      setup.item.renderWordmark()
      setup.item.step = 3
      return "ok"
    }
    function saveSetup(): string {
      if (!setup.item || !setup.item.wordmarkReady) return "unavailable"
      setup.item.save()
      return "ok"
    }
    function unlock(index: int, reduced: bool): string {
      timeout.restart(); preview.visible = false; setup.active = false
      splash.play(index, {awaySeconds: 3600, motion: reduced ? "reduced" : "full"})
      return "ok"
    }
    function hide(): string { preview.visible = false; setup.active = false; splash.finish(); return "ok" }
    function quit(): string { Qt.quit(); return "ok" }
  }
}
