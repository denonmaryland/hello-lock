import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "plugin" as Hello
import "plugin/platform" as Platform

// No Service.qml, PAM, session-lock object, compositor API or Omarchy module.
ShellRoot {
  id: root
  readonly property string sourceDir: Quickshell.env("HELLO_LOCK_SOURCE")
  readonly property string configDir: Quickshell.env("HELLO_LOCK_CONFIG_DIR")
  property var config: ({})
  property var appearance: ({})
  Platform.Motion { id: desktopMotion; watch: settings.item !== null && !root.previewing && !splash.shown }
  readonly property bool calm: config.motion === "reduced" || (config.motion !== "full" && desktopMotion.calm)
  property bool ready: false
  property bool previewing: false
  property bool returning: false
  property bool closingPreview: false
  property string previewEffect: "cells"
  property int typed: 0
  readonly property string defaultLogo: sourceDir + "/symbols/prompt.svg"
  readonly property string logo: expand(config.logo || defaultLogo)
  readonly property string wallpaper: typeof appearance.wallpaper === "string" ? expand(appearance.wallpaper) : ""
  function expand(path) {
    path = String(path || "")
    if (path.indexOf("~/") === 0) return Quickshell.env("HOME") + path.slice(1)
    if (/^@[a-z0-9-]+$/.test(path)) return sourceDir + "/symbols/" + path.slice(1) + ".svg"
    return path.charAt(0) === "/" ? path : configDir + "/" + path
  }
  function color(key, fallback) {
    var value = appearance[key]
    return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value) ? value : fallback
  }
  Binding { target: Platform.Color; property: "baseBackground"; value: root.color("background", "#1a1b26") }
  Binding { target: Platform.Color; property: "baseForeground"; value: root.color("foreground", "#c0caf5") }
  Binding { target: Platform.Color; property: "baseAccent"; value: root.color("accent", "#7aa2f7") }
  Binding { target: Platform.Color; property: "baseUrgent"; value: root.color("urgent", "#f7768e") }
  FontLoader { source: "plugin/fonts/Oxanium-Variable.ttf" }
  FontLoader { source: "plugin/fonts/ShareTechMono-Regular.ttf" }
  FileView {
    id: configFile
    path: root.configDir + "/config.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (!data || typeof data !== "object" || Array.isArray(data)) throw "invalid"
        root.config = data
      } catch (error) { console.warn("hello-lock: settings are not a valid JSON object") }
    }
  }
  FileView {
    path: root.configDir + "/appearance.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (data && typeof data === "object" && !Array.isArray(data)) root.appearance = data
      } catch (error) { console.warn("hello-lock: appearance is not a valid JSON object") }
    }
  }
  Timer {
    interval: 100
    running: true
    onTriggered: {
      root.ready = true
      var action = Quickshell.env("HELLO_LOCK_ACTION")
      if (action === "preview") root.showLock("")
      else if (action === "splash") root.showSplash("", "")
      else settings.active = true
    }
  }
  Loader {
    id: settings
    active: false
    source: "plugin/Settings.qml"
    onLoaded: {
      item.pluginDir = root.sourceDir
      item.configDir = root.configDir
      item.omarchyIntegration = false
      item.standaloneFeatures = true
      item.reducedMotion = Qt.binding(function() { return desktopMotion.calm })
      item.defaultLogo = root.defaultLogo
      item.suggestedName = Quickshell.env("USER") || "friend"
      item.currentConfig = root.config
      item.start()
    }
  }
  Connections {
    target: settings.item
    function onClosed() { Qt.quit() }
    function onConfigSaved() { configFile.reload() }
    function onLockPreviewRequested(effect) { root.showLock(effect) }
    function onUnlockPreviewRequested(symbol, handoff) { root.showSplash(symbol, handoff) }
  }
  function stepAside() {
    returning = settings.active
    if (settings.item) settings.item.away = true
  }
  function showLock(effect) {
    stepAside()
    typed = 0
    previewEffect = effect || config.typingEffect || "cells"
    // Shuffle is resolved for the preview without advancing real-lock bags.
    if (previewEffect === "shuffle") previewEffect = "cells"
    previewing = true
    demo.restart()
  }
  function showSplash(symbol, handoff) {
    stepAside()
    var chosen = symbol || String(config.symbol || "")
    if (chosen === "@shuffle" || chosen === "shuffle") {
      var names = Object.keys(splash.grids)
      chosen = names.length ? names[Math.floor(Math.random() * names.length)] : ""
    }
    splash.symbolName = /^@[a-z]+$/.test(chosen) ? chosen.slice(1) : chosen
    splash.symbolPaths = chosen ? [expand(chosen.charAt(0) === "@" || !splash.knowsSymbol(chosen) ? chosen : "@" + chosen)] : [root.logo]
    if (!symbol && Array.isArray(config.symbolParts) && config.symbolParts.length > 0)
      splash.symbolPaths = config.symbolParts.slice(0, 2).filter(function(path) { return typeof path === "string" && path.length > 0 }).map(expand)
    splash.logoPath = root.logo
    splash.handoff = handoff || config.handoff || "shuffle"
    splash.play(-1, {awaySeconds: 3600, motion: root.calm ? "reduced" : "full",
                    greeting: config.greeting !== false, backdrop: config.unlockBackdrop !== false,
                    maxDuration: typeof config.unlockDuration === "number" ? config.unlockDuration : 0})
  }
  function returnToSettings() {
    if (closingPreview) return
    closingPreview = true
    splash.finish()
    previewing = false
    demo.stop()
    if (returning && settings.item) {
      returning = false
      settings.item.away = false
    } else Qt.quit()
    closingPreview = false
  }
  Timer {
    id: demo
    interval: 140
    repeat: true
    onTriggered: root.typed = (root.typed + 1) % 18
  }
  PanelWindow {
    visible: root.previewing
    anchors { top: true; bottom: true; left: true; right: true }
    color: Platform.Color.background
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    Hello.LockView {
      anchors.fill: parent
      inputEnabled: false
      queryHyprland: false
      loadBackground: root.previewing
      backgroundPath: root.wallpaper
      logoPath: root.logo
      tintLogo: root.config.tintLogo !== false
      showClock: root.config.clock !== false
      reducedMotion: root.calm
      typingEffect: root.previewEffect
      passwordText: "x".repeat(root.typed)
    }
    MouseArea { anchors.fill: parent; onClicked: root.returnToSettings() }
    Text {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: 28
      text: "PREVIEW ONLY · Click to close"
      color: Platform.Color.foreground
    }
  }
  Hello.UnlockSplash {
    id: splash
    pluginDir: root.sourceDir
    userName: root.config.name || Quickshell.env("USER") || "friend"
    brand: root.config.brand || ""
    tintSymbol: root.config.tintLogo !== false
    legendaryEnabled: root.config.legendary !== false
    backgroundPath: root.wallpaper
    onSoundRequested: function(name) {
      if (root.config.sounds === false) return
      sound.command = [root.sourceDir + "/bin/hello-sound", name]
      sound.running = false
      sound.running = true
    }
    onShownChanged: if (!shown && root.ready && !root.previewing && !root.closingPreview) root.returnToSettings()
  }
  Process { id: sound }
  // A bounded visual preview never leaves the user's desktop covered indefinitely.
  Timer { interval: 30000; running: root.previewing; onTriggered: root.returnToSettings() }
  IpcHandler {
    target: "standalone"
    function status(): string {
      return JSON.stringify({ready: root.ready, settings: settings.active, preview: root.previewing,
                             splash: splash.shown, locking: false, configDir: root.configDir})
    }
    function section(index: int): string {
      if (!settings.item || index < 0 || index > 7) return "unavailable"
      settings.item.sectionIndex = index
      return "ok"
    }
    function closePreview(): string { root.returnToSettings(); return "ok" }
    function quit(): string {
      if (settings.item) settings.item.requestExit("close")
      else Qt.quit()
      return "ok"
    }
  }
}
