import QtQuick
import "Presets.js" as Presets
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Hello Lock settings: every option on one page, grouped in a sidebar, with
// no steps. Each change is saved as it is made (through bin/hello-config) and
// applies on the next lock. Opened with `omarchy-shell lock settings`; never
// shown while locked, and it has no access to authentication.
Item {
  id: root

  // Supplied by Service.qml.
  property string pluginDir: ""
  property string configDir: ""
  property string suggestedName: ""
  property var currentConfig: ({})
  // True while the service shows a preview: the window steps aside.
  property bool away: false

  signal closed()
  signal setupRequested()
  signal unlockPreviewRequested(string symbol)
  signal lockPreviewRequested(string effect)

  // ---- Sections.
  readonly property var sections: [
    { id: "you", label: "You", title: "You", hint: "How Hello Lock greets you." },
    { id: "logo", label: "Logo", title: "Logo", hint: "Shown on the lock screen." },
    { id: "unlock", label: "Unlock", title: "Unlock", hint: "The animation that plays when you unlock." },
    { id: "typing", label: "Typing", title: "Typing", hint: "What your logo does while you type your password." },
    { id: "lock", label: "Lock screen", title: "Lock screen", hint: "What you see when you lock." },
    { id: "sound", label: "Sound", title: "Sound", hint: "Lock, unlock and wrong-password sounds." },
    { id: "presets", label: "Presets", title: "Brand presets", hint: "Keep several logos and symbols ready to use." },
    { id: "privacy", label: "Weather", title: "Weather", hint: "The only thing Hello Lock fetches from the internet." }
  ]
  property int sectionIndex: 0
  readonly property var section: sections[sectionIndex]
  function moveSection(delta) { sectionIndex = (sectionIndex + delta + sections.length) % sections.length }

  // ---- State, read from config.json when the window opens.
  property string name: ""
  property string birthMonth: ""
  property string birthDay: ""
  property string brand: ""
  property string logoChoice: "omarchy"   // "wordmark" | "image" | "omarchy"
  property string wordmarkText: ""
  property string wordmarkStyle: "blocks"
  property string imagePath: ""
  property bool tintLogo: true
  property string symbolChoice: "logo"    // "logo" | "custom" | a built-in name
  // A symbol set by hand in config.json ("symbol" path or "symbolParts"), kept
  // for this visit so picking a built-in and coming back is not destructive.
  property var customSymbol: null
  property bool legendary: true
  property string typingEffect: "cells"
  property bool clock: true
  property bool powerDown: true
  property string motion: "auto"
  property bool sounds: true
  property real volume: 0.5
  property bool quietHours: true
  property int quietStart: 23
  property int quietEnd: 7
  property bool weather: true

  readonly property var wordmarkStyles: [
    { value: "omarchy", label: "Omarchy" }, { value: "blocks", label: "Blocks" },
    { value: "outline", label: "Outline" }, { value: "scanline", label: "Scanline" },
    { value: "led", label: "LED" }, { value: "tiles", label: "Tiles" },
    { value: "split", label: "Split" }, { value: "italic", label: "Italic" },
    { value: "wide", label: "Wide" }, { value: "glitch", label: "Glitch" },
    { value: "shadow", label: "Shadow" }
  ]
  readonly property var symbolGroups: [
    { label: "YOURS", ids: customSymbol ? ["logo", "custom", "omarchy"] : ["logo", "omarchy"] },
    { label: "SYSTEM", ids: ["power", "prompt", "cursor", "chip", "bolt", "gear", "battery", "core"] },
    { label: "SECURITY", ids: ["shield", "key", "lock", "eye", "crosshair", "scan", "visor", "skull"] },
    { label: "SIGNAL", ids: ["radar", "antenna", "signal", "wifi", "satellite", "waveform", "link", "infinity"] },
    { label: "SPACE", ids: ["planet", "moon", "nova", "sparkle", "rocket", "comet", "ufo", "alien"] },
    { label: "RANK", ids: ["chevrons", "insignia", "medal", "crown", "star", "gem", "delta"] }
  ]
  readonly property var builtinSymbols: symbolGroups.slice(1).reduce(function(all, g) { return all.concat(g.ids) }, ["omarchy"])
  readonly property var typingEffects: [
    { id: "cells", label: "Cells", hint: "Mosaic squares pop in, one keystroke at a time." },
    { id: "scanline", label: "Scanline", hint: "A CRT beam burns your logo in, line by line." },
    { id: "liquid", label: "Liquid", hint: "Your logo fills up like a tank." },
    { id: "decrypt", label: "Decrypt", hint: "Scrambled slices snap into place." },
    { id: "equalizer", label: "Equalizer", hint: "Bars rise and fall like an audio level meter." },
    { id: "sweep", label: "Sweep", hint: "A charge meter sweeps across, left to right." },
    { id: "pulse", label: "Pulse", hint: "No fill, just a ripple with every keystroke." },
    { id: "off", label: "Off", hint: "Your logo stays still while you type." },
    { id: "shuffle", label: "Shuffle", hint: "A different one every time you lock." }
  ]

  // ---- Wordmark preview (rendered in memory; saved files are content-named).
  property string wordmarkPreview: ""
  property bool wordmarkReady: false
  property string wordmarkError: ""
  property int previewVersion: 0
  property bool picking: false

  readonly property string omarchyLogo: "/usr/share/omarchy/logo.svg"
  readonly property string logoPreview: logoChoice === "wordmark" ? (wordmarkReady ? wordmarkPreview : "")
    : logoChoice === "image" ? imagePath : omarchyLogo
  readonly property bool logoTinted: logoChoice !== "image" || tintLogo
  function symbolFile(id) {
    if (id === "logo") return logoPreview
    if (id === "custom") return customSymbol ? customSymbol.paths[0] : ""
    return pluginDir ? pluginDir + "/symbols/" + id + ".svg" : ""
  }
  function symbolLabel(id) {
    if (id === "logo") return logoChoice === "wordmark" ? "My name" : "My logo"
    if (id === "custom") return "Custom"
    return id.charAt(0).toUpperCase() + id.slice(1)
  }

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.62)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.14)

  // PanelSlider takes its colors from a bar object.
  readonly property QtObject sliderBar: QtObject {
    readonly property color foreground: root.fg
    readonly property color background: root.bg
    readonly property color urgent: Commons.Color.urgent
  }

  function fileUrl(path, version) {
    if (!path) return ""
    if (path.indexOf("data:image/svg+xml,") === 0) return path
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/") + "?v=" + (version || 0)
  }

  function expand(p) {
    if (!p) return ""
    if (p.indexOf("~/") === 0) return Quickshell.env("HOME") + p.slice(1)
    if (/^@[a-z0-9-]+$/.test(p)) return pluginDir + "/symbols/" + p.slice(1) + ".svg"
    return p.charAt(0) === "/" ? p : configDir + "/" + p
  }

  function str(v) { return typeof v === "string" ? v.trim() : "" }

  function start() {
    var c = currentConfig || {}
    brandingPresets = Presets.usable(c.brandingPresets)
    var invalidPresets = c.brandingPresets !== undefined && (!Array.isArray(c.brandingPresets) || brandingPresets.length !== c.brandingPresets.length)
    selectedPreset = brandingPresets.some(function(p) { return p.id === c.selectedPreset }) ? c.selectedPreset : ""
    presetMode = str(c.presetMode) || "manual"
    presetName = (brandingPresets.find(function(p) { return p.id === selectedPreset }) || {}).name || ""
    name = str(c.name)
    var b = str(c.birthday).split("-")
    birthMonth = b.length === 2 ? b[0] : ""
    birthDay = b.length === 2 ? b[1] : ""
    brand = str(c.brand)
    wordmarkText = str(c.wordmarkText)
    wordmarkStyle = str(c.wordmarkStyle) || "blocks"
    imagePath = ""
    if (wordmarkText) { logoChoice = "wordmark"; renderWordmark(false) }
    else if (str(c.logo)) { logoChoice = "image"; imagePath = expand(str(c.logo)) }
    else logoChoice = "omarchy"
    tintLogo = c.tintLogo !== false

    var parts = Array.isArray(c.symbolParts) ? c.symbolParts.filter(function(p) { return str(p) }) : []
    var sym = str(c.symbol)
    var builtin = /^@[a-z0-9-]+$/.test(sym) ? sym.slice(1) : ""
    customSymbol = null
    if (parts.length > 0) {
      customSymbol = { paths: parts.map(expand), update: { symbol: null, symbolParts: parts } }
      symbolChoice = "custom"
    } else if (sym && !builtin) {
      customSymbol = { paths: [expand(sym)], update: { symbol: sym, symbolParts: null } }
      symbolChoice = "custom"
    } else {
      symbolChoice = builtin && builtinSymbols.indexOf(builtin) >= 0 ? builtin : "logo"
    }

    legendary = c.legendary !== false
    var effect = str(c.typingEffect).toLowerCase()
    typingEffect = typingEffects.some(function(e) { return e.id === effect }) ? effect : "cells"
    clock = c.clock !== false
    powerDown = c.powerDown !== false
    motion = c.motion === "reduced" || c.motion === "full" ? c.motion : "auto"
    sounds = c.sounds !== false
    weather = c.weather !== false
    soundGetProc.running = true
    menuStatusProc.running = true
    savedOnce = false
    status = invalidPresets ? "Some presets are invalid and were ignored. Your other settings are loaded." : ""
    sectionIndex = 0
  }

  property var brandingPresets: []
  property string selectedPreset: ""
  property string presetMode: "manual"
  property string presetName: ""
  property bool presetFailed: false
  property string presetAction: ""
  property string presetValue: ""
  property bool confirmPresetDelete: false
  readonly property bool presetBusy: presetWait.running || presetProc.running
  function runPreset(action, value) {
    if (presetBusy) return
    confirmPresetDelete = false
    presetFailed = false
    presetAction = action
    presetValue = value
    presetWait.start()
  }
  Timer {
    id: presetWait
    interval: 40
    repeat: true
    onTriggered: {
      if (saveTimer.running || saveProc.running || Object.keys(root.pending).length
          || soundTimer.running || soundSaveProc.running || Object.keys(root.soundPending).length
          || wordmarkTimer.running || wordmarkProc.running || importProc.running || menuProc.running) return
      stop()
      if (root.saveFailed || root.wordmarkError) {
        root.presetFailed = true
        root.status = "Fix the unsaved change before using presets."
        return
      }
      presetProc.command = [root.pluginDir + "/bin/hello-config", "preset", root.presetAction, root.presetValue]
      presetProc.running = true
    }
  }
  Process {
    id: presetProc
    stdout: StdioCollector { id: presetOutput; waitForEnd: true }
    stderr: StdioCollector { id: presetError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.presetFailed = true
        root.status = String(presetError.text || "Couldn't save preset.").trim()
        return
      }
      try {
        var section = root.sectionIndex
        root.currentConfig = JSON.parse(presetOutput.text)
        root.start()
        root.sectionIndex = section
        root.saveFailed = false
        root.status = "saved"
        savedFade.restart()
      } catch (e) { root.presetFailed = true; root.status = "Couldn't reload presets: " + e }
    }
  }

  // ---- Saving. Changes are merged into one pending update and written after
  // a short pause, so typing a name is one save rather than one per letter.
  // The first write of a visit keeps a timestamped backup; later ones don't.
  // Keep the loader alive until debounced edits and helper processes settle.
  // Emitting closed/setupRequested immediately would destroy their timers.
  property string exitAction: ""
  property bool saveFailed: false
  function requestExit(action) {
    if (exitAction) return
    exitAction = action
    exitTimer.start()
  }
  Timer {
    id: exitTimer
    interval: 30
    repeat: true
    onTriggered: {
      if (presetWait.running || presetProc.running || saveTimer.running || saveProc.running || Object.keys(root.pending).length
          || soundTimer.running || soundSaveProc.running || Object.keys(root.soundPending).length
          || wordmarkTimer.running || wordmarkProc.running || importProc.running || menuProc.running) return
      stop()
      var action = root.exitAction
      root.exitAction = ""
      // A failed write must leave the window and its error visible once;
      // asking again closes, so a broken config can't trap the window.
      if (root.saveFailed || root.presetFailed) { root.saveFailed = false; root.presetFailed = false; return }
      if (action === "setup") root.setupRequested()
      else root.closed()
    }
  }

  // ---- The Omarchy menu entry (Style > Lock Screen) that opens this window.
  // "on", "off", "other" (a different entry is there) or "unreadable".
  property string menuState: ""
  Process {
    id: menuStatusProc
    command: [root.pluginDir + "/bin/hello-menu", "status"]
    stdout: StdioCollector { id: menuStatusOut; waitForEnd: true }
    onExited: root.menuState = String(menuStatusOut.text || "").trim()
  }
  function setMenu(on) {
    if (menuProc.running) return
    menuProc.command = [pluginDir + "/bin/hello-menu", on ? "add" : "remove"]
    status = "saving"
    menuProc.running = true
  }
  Process {
    id: menuProc
    stdout: StdioCollector { id: menuOut; waitForEnd: true }
    stderr: StdioCollector { id: menuErr; waitForEnd: true }
    onExited: function(code) {
      root.menuState = String(menuOut.text || "").trim()
      if (code === 0) { root.status = "saved"; savedFade.restart() }
      else root.status = String(menuErr.text || "Couldn't change the Omarchy menu.").replace(/^hello-menu: /, "").trim()
    }
  }

  property var pending: ({})
  property bool savedOnce: false
  property string status: ""        // "" | "saving" | "saved" | an error
  function save(update, delay) {
    saveFailed = false
    var merged = Object.assign({}, pending)
    for (var k in update) merged[k] = update[k]
    pending = merged
    status = "saving"
    saveTimer.interval = delay === undefined ? 120 : delay
    saveTimer.restart()
  }
  function flush() {
    if (saveProc.running) { saveTimer.restart(); return }
    if (Object.keys(pending).length === 0) return
    var update = pending
    pending = ({})
    saveProc.command = savedOnce
      ? [pluginDir + "/bin/hello-config", "save", "--no-backup", JSON.stringify(update)]
      : [pluginDir + "/bin/hello-config", "save", JSON.stringify(update)]
    saveProc.running = true
  }
  Timer { id: saveTimer; onTriggered: root.flush() }
  Timer { id: savedFade; interval: 1600; onTriggered: if (root.status === "saved") root.status = "" }

  Process {
    id: saveProc
    stderr: StdioCollector { id: saveErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        root.savedOnce = true
        if (Object.keys(root.pending).length > 0) { root.flush(); return }
        root.status = "saved"
        savedFade.restart()
      } else {
        root.saveFailed = true
        root.status = String(saveErr.text || "").replace(/^hello-config: /, "").trim() || "Couldn't save that change."
      }
    }
  }

  property var soundPending: ({})
  function saveSound(update) {
    saveFailed = false
    soundPending = Object.assign({}, soundPending, update)
    status = "saving"
    soundTimer.restart()
  }
  Timer {
    id: soundTimer
    interval: 200
    onTriggered: {
      if (soundSaveProc.running) { restart(); return }
      soundSaveProc.command = [root.pluginDir + "/bin/hello-config", "sound-save", JSON.stringify(root.soundPending)]
      root.soundPending = ({})
      soundSaveProc.running = true
    }
  }
  Process {
    id: soundSaveProc
    stderr: StdioCollector { id: soundSaveErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) { root.status = "saved"; savedFade.restart() }
      else {
        root.saveFailed = true
        root.status = String(soundSaveErr.text || "").replace(/^hello-config: /, "").trim() || "Couldn't save the sound settings."
      }
    }
  }
  Process {
    id: soundGetProc
    command: [root.pluginDir + "/bin/hello-config", "sound-get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(String(text || "{}"))
          root.volume = typeof s.volume === "number" ? s.volume : 0.5
          root.quietHours = s.quietStart !== null && s.quietEnd !== null
          root.quietStart = s.quietStart !== null ? s.quietStart : 23
          root.quietEnd = s.quietEnd !== null ? s.quietEnd : 7
        } catch (e) {}
      }
    }
  }
  Process { id: testSoundProc }
  function testSound() {
    testSoundProc.running = false
    testSoundProc.command = [pluginDir + "/bin/hello-sound", "--test", "unlock-short"]
    testSoundProc.running = true
  }

  // ---- Field helpers.
  function pad2(v) { v = String(v); return v.length === 1 ? "0" + v : v }
  readonly property bool birthdayValid: {
    if (birthMonth === "" && birthDay === "") return true
    var m = Number(birthMonth), d = Number(birthDay)
    var days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return /^\d{1,2}$/.test(birthMonth) && /^\d{1,2}$/.test(birthDay) && m >= 1 && m <= 12 && d >= 1 && d <= days[m - 1]
  }
  function saveBirthday() {
    if (!birthdayValid) {
      // Don't let a queued, half-typed date ("1" on the way to "13") land.
      if (!pending.hasOwnProperty("birthday")) return
      var rest = Object.assign({}, pending)
      delete rest.birthday
      pending = rest
      if (Object.keys(rest).length === 0 && !saveProc.running) { saveTimer.stop(); status = "" }
      return
    }
    save({ birthday: birthMonth && birthDay ? pad2(birthMonth) + "-" + pad2(birthDay) : null }, 500)
  }

  function chooseLogo(choice) {
    if (choice === "image") { pickImage(); return }
    logoChoice = choice
    if (choice === "omarchy") save({ logo: null, wordmarkText: null, wordmarkStyle: null, tintLogo: null })
    else if (choice === "wordmark") { renderWordmark(true); wordmarkFocus.restart() }
  }

  // Renders the preview; with `andSave`, saves it once it renders cleanly.
  property bool saveWordmarkWhenReady: false
  function renderWordmark(andSave) {
    var t = wordmarkText.replace(/[^A-Za-z0-9 ]/g, "")
    if (t !== wordmarkText) wordmarkText = t
    saveWordmarkWhenReady = andSave
    wordmarkReady = false
    if (t.trim().length === 0) { wordmarkError = ""; return }
    wordmarkTimer.restart()
  }
  Timer {
    id: wordmarkTimer
    interval: 260
    onTriggered: {
      if (wordmarkProc.running) { restart(); return }
      wordmarkProc.renderedText = root.wordmarkText
      wordmarkProc.renderedStyle = root.wordmarkStyle
      wordmarkProc.command = [root.pluginDir + "/bin/hello-wordmark", root.wordmarkText, "-", "--style", root.wordmarkStyle]
      wordmarkProc.running = true
    }
  }
  Process {
    id: wordmarkProc
    property string renderedText: ""
    property string renderedStyle: ""
    stdout: StdioCollector { id: wordmarkOut; waitForEnd: true }
    stderr: StdioCollector { id: wordmarkErr; waitForEnd: true }
    onExited: function(code) {
      if (renderedText !== root.wordmarkText || renderedStyle !== root.wordmarkStyle) return
      root.wordmarkReady = code === 0
      root.wordmarkPreview = code === 0 ? "data:image/svg+xml," + encodeURIComponent(wordmarkOut.text) : ""
      root.wordmarkError = code === 0 ? "" : String(wordmarkErr.text || "").replace(/^hello-wordmark: /, "").trim()
      root.previewVersion += 1
      if (code === 0 && root.saveWordmarkWhenReady && root.logoChoice === "wordmark") {
        root.saveWordmarkWhenReady = false
        root.save({ wordmarkText: root.wordmarkText.trim(), wordmarkStyle: root.wordmarkStyle, tintLogo: null })
      }
    }
  }
  Timer { id: wordmarkFocus; interval: 60; onTriggered: if (wordmarkField) wordmarkField.forceActiveFocus() }
  property Item wordmarkField: null

  // The file chooser is a normal window, so this one steps aside until it returns.
  function pickImage() {
    if (picking) return
    picking = true
    pickProc.running = true
  }
  Process {
    id: pickProc
    command: ["omarchy-file-select", "--title", "Choose your logo", "--extensions", "svg png jpg jpeg webp"]
    stdout: StdioCollector { id: pickOut; waitForEnd: true }
    onExited: function(code) {
      var chosen = String(pickOut.text || "").split("\n")[0].trim()
      if (code === 0 && chosen) {
        importProc.command = [root.pluginDir + "/bin/hello-config", "import-logo", chosen]
        importProc.running = true
      } else {
        root.picking = false
      }
    }
  }
  Process {
    id: importProc
    stdout: StdioCollector { id: importOut; waitForEnd: true }
    stderr: StdioCollector { id: importErr; waitForEnd: true }
    onExited: function(code) {
      root.picking = false
      if (code === 0) {
        root.imagePath = String(importOut.text || "").trim()
        root.logoChoice = "image"
        root.save({ logo: root.imagePath, wordmarkText: null, wordmarkStyle: null, tintLogo: root.tintLogo })
      } else {
        root.status = String(importErr.text || "").replace(/^hello-config: /, "").trim() || "Couldn't use that file."
      }
    }
  }

  function chooseSymbol(id) {
    if (id === symbolChoice) return
    symbolChoice = id
    if (id === "custom" && customSymbol) save(customSymbol.update)
    else save({ symbol: id === "logo" ? null : "@" + id, symbolParts: null })
  }

  // ---- The window: a centered card over a dimmed desktop.
  PanelWindow {
    id: win
    visible: !root.picking && !root.away
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hello-lock-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.42)
      opacity: 0
      Component.onCompleted: opacity = 1
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      MouseArea { anchors.fill: parent; onClicked: root.requestExit("close") }
    }

    FocusScope {
      id: card
      focus: true
      width: Math.min(940, win.width - 80)
      height: Math.min(660, win.height - 80)
      anchors.centerIn: parent
      opacity: 0
      scale: 0.98
      Component.onCompleted: { opacity = 1; scale = 1; forceActiveFocus() }
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.requestExit("close"); event.accepted = true }
        else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_PageDown || event.key === Qt.Key_Tab)) { root.moveSection(1); event.accepted = true }
        else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_PageUp || event.key === Qt.Key_Backtab)) { root.moveSection(-1); event.accepted = true }
      }

      // Clicks on the card never reach the scrim.
      MouseArea { anchors.fill: parent; onClicked: card.forceActiveFocus() }

      Rectangle {
        anchors.fill: parent
        radius: Math.max(Style.cornerRadius, 10)
        color: root.bg
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
        clip: true

        // Sidebar.
        Rectangle {
          id: sidebar
          width: 220
          anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
          radius: parent.radius

          Column {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
            spacing: 4

            Text {
              text: "HELLO LOCK"
              color: root.accent
              font.family: "Share Tech Mono"
              font.pixelSize: 13
              font.letterSpacing: 3.5
              bottomPadding: 2
            }
            Text {
              text: "Settings"
              color: root.fg
              font.family: "Oxanium"
              font.weight: Font.DemiBold
              font.pixelSize: 22
              bottomPadding: 14
            }

            Repeater {
              model: root.sections
              Rectangle {
                id: navItem
                required property var modelData
                required property int index
                readonly property bool current: root.sectionIndex === index
                width: parent.width
                height: 36
                radius: Math.max(Style.cornerRadius, 6)
                color: current ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                  : navMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                  anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                  text: navItem.modelData.label
                  color: navItem.current ? root.fg : root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.weight: navItem.current ? Font.DemiBold : Font.Normal
                }
                Rectangle {
                  visible: navItem.current
                  width: 3; height: 16; radius: 1.5
                  color: root.accent
                  anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                  id: navMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.sectionIndex = navItem.index; card.forceActiveFocus() }
                }
              }
            }
          }

          Column {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 18 }
            spacing: 10
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.status === "saving" ? "Saving…"
                : root.status === "saved" ? "✓ Saved. Applies on your next lock."
                : root.status ? root.status : "Changes save as you make them."
              color: root.status && root.status !== "saving" && root.status !== "saved" ? Commons.Color.urgent
                : root.status === "saved" ? root.accent : root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            LinkText { label: "Run the setup again"; onClicked: root.requestExit("setup") }
          }
        }

        // Content.
        Item {
          anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right; right: parent.right }

          Column {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 26; leftMargin: 32; rightMargin: 64 }
            spacing: 4
            Text {
              text: root.section.title
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.displayLarge
              font.weight: Font.DemiBold
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.section.hint
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
          }

          // Close button.
          Rectangle {
            width: 30; height: 30; radius: 15
            anchors { top: parent.top; right: parent.right; margins: 16 }
            color: closeMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1) : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: root.muted; font.pixelSize: 15 }
            MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.requestExit("close") }
          }

          Flickable {
            id: scroller
            anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 20; bottomMargin: 20 }
            contentHeight: page.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Connections { target: root; function onSectionIndexChanged() { scroller.contentY = 0; pageFade.restart() } }

            Column {
              id: page
              enabled: !root.presetBusy
              x: 32
              width: scroller.width - 64
              spacing: 14
              NumberAnimation { id: pageFade; target: page; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }

              // ---- Presets. All writes wait for the normal autosave queue.
              Column {
                visible: root.section.id === "presets"
                width: parent.width
                spacing: 14
                Field {
                  label: "On each lock"
                  hint: "Cycle follows saved order. Shuffle avoids the previous preset. With no presets, your current branding is used."
                  Dropdown {
                    width: 260
                    showLabel: false
                    options: [{value: "manual", label: "Keep current branding"}, {value: "cycle", label: "Cycle presets"}, {value: "shuffle", label: "Shuffle presets"}]
                    value: root.presetMode
                    onChanged: function(v) { root.runPreset("mode", v) }
                  }
                }
                Field {
                  label: "Save current branding"
                  hint: "Includes brand text, logo or wordmark, tint and unlock symbol. Change these in You, Logo and Unlock, then save a new preset or update the selected one."
                  TextField {
                    width: 320
                    text: root.presetName
                    placeholderText: "Company / Primary logo"
                    maximumLength: 60
                    onTextEdited: root.presetName = text
                  }
                }
                Flow {
                  width: parent.width
                  spacing: 10
                  Button { focusable: true; text: "Save new"; bordered: true; enabled: !!root.presetName.trim(); onClicked: root.runPreset("create", root.presetName) }
                  Button { focusable: true; text: "Update selected"; bordered: true; enabled: !!root.selectedPreset && !!root.presetName.trim(); onClicked: root.runPreset("update", root.presetName) }
                  Button { focusable: true; text: "Use next"; bordered: true; enabled: root.brandingPresets.length > 0; onClicked: root.runPreset("next", "") }
                }
                Text {
                  visible: root.brandingPresets.length === 0
                  text: "No presets yet. Save your current branding to get started."
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Repeater {
                  model: root.brandingPresets
                  delegate: Row {
                    required property var modelData
                    width: parent.width
                    spacing: 12
                    Text {
                      width: Math.max(100, page.width - 100)
                      anchors.verticalCenter: parent.verticalCenter
                      text: (modelData.id === root.selectedPreset ? "● " : "") + modelData.name
                      elide: Text.ElideRight
                      color: root.fg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                    Button { focusable: true; text: "Use"; bordered: true; onClicked: root.runPreset("apply", modelData.id) }
                  }
                }
                Flow {
                  width: parent.width
                  spacing: 10
                  visible: !!root.selectedPreset
                  Button {
                    focusable: true
                    text: root.confirmPresetDelete ? "Confirm delete" : "Delete selected"
                    bordered: true
                    onClicked: { if (root.confirmPresetDelete) root.runPreset("delete", root.selectedPreset); else root.confirmPresetDelete = true }
                  }
                  Button { focusable: true; visible: root.confirmPresetDelete; text: "Cancel"; onClicked: root.confirmPresetDelete = false }
                }
              }

              // ---- You.
              Column {
                visible: root.section.id === "you"
                width: parent.width
                spacing: 14

                Field {
                  label: "Name"
                  hint: "Used in the greetings when you unlock. Leave it empty to use your account name."
                  TextField {
                    width: 320
                    text: root.name
                    placeholderText: root.suggestedName || "Your name"
                    maximumLength: 40
                    onTextEdited: { root.name = text; root.save({ name: text.trim() || null }, 600) }
                  }
                }

                Field {
                  label: "Birthday"
                  hint: root.birthdayValid ? "Optional. On the day, your unlock says happy birthday." : "That date doesn't exist."
                  hintColor: root.birthdayValid ? root.muted : Commons.Color.urgent
                  Row {
                    spacing: 8
                    TextField {
                      id: monthField
                      width: 64
                      text: root.birthMonth
                      placeholderText: "MM"
                      maximumLength: 2
                      horizontalAlignment: TextInput.AlignHCenter
                      validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
                      onTextEdited: { root.birthMonth = text; if (text.length === 2) dayField.forceActiveFocus(); root.saveBirthday() }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "/"; color: root.muted; font.pixelSize: Style.font.title }
                    TextField {
                      id: dayField
                      width: 64
                      text: root.birthDay
                      placeholderText: "DD"
                      maximumLength: 2
                      horizontalAlignment: TextInput.AlignHCenter
                      validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
                      onTextEdited: { root.birthDay = text; root.saveBirthday() }
                    }
                    Button {
                      focusable: true
                      anchors.verticalCenter: parent.verticalCenter
                      visible: root.birthMonth !== "" || root.birthDay !== ""
                      text: "Clear"
                      onClicked: { root.birthMonth = ""; root.birthDay = ""; root.saveBirthday() }
                    }
                  }
                }

                Field {
                  label: "Status word"
                  hint: "The first line of the unlock: " + (root.brand.trim() ? root.brand.trim().toUpperCase() : "SYSTEM") + " ONLINE."
                  TextField {
                    width: 220
                    text: root.brand
                    placeholderText: "SYSTEM"
                    maximumLength: 16
                    font.capitalization: Font.AllUppercase
                    onTextEdited: { root.brand = text; root.save({ brand: text.trim() || null }, 600) }
                  }
                }
              }

              // ---- Logo.
              Column {
                visible: root.section.id === "logo"
                width: parent.width
                spacing: 14

                PreviewBox { source: root.logoPreview; tinted: root.logoTinted }

                ButtonGroup {
                  options: [{ value: "wordmark", label: "Type a wordmark" }, { value: "image", label: "Use an image" }, { value: "omarchy", label: "Omarchy logo" }]
                  value: root.logoChoice
                  onChanged: function(v) { root.chooseLogo(v) }
                }

                Field {
                  visible: root.logoChoice === "wordmark"
                  label: "Wordmark"
                  hint: root.wordmarkError ? root.wordmarkError
                    : root.wordmarkStyle === "omarchy" ? "The Omarchy logo's own font by CoSMiC cHiLD. Letters only."
                    : "Letters and numbers, up to 20."
                  hintColor: root.wordmarkError ? Commons.Color.urgent : root.muted
                  Row {
                    spacing: 10
                    TextField {
                      id: wmField
                      width: 260
                      text: root.wordmarkText
                      placeholderText: "YOUR NAME OR BRAND"
                      maximumLength: 20
                      font.capitalization: Font.AllUppercase
                      Component.onCompleted: root.wordmarkField = wmField
                      onTextEdited: { root.wordmarkText = text; root.renderWordmark(true) }
                    }
                    Dropdown {
                      anchors.verticalCenter: parent.verticalCenter
                      showLabel: false
                      width: 160
                      options: root.wordmarkStyles
                      value: root.wordmarkStyle
                      onChanged: function(v) { root.wordmarkStyle = v; root.renderWordmark(true) }
                    }
                  }
                }

                Row {
                  visible: root.logoChoice === "image"
                  spacing: 12
                  Button { focusable: true; text: "Choose a different file…"; bordered: true; onClicked: root.pickImage() }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, page.width - 230)
                    elide: Text.ElideMiddle
                    text: root.imagePath.replace(Quickshell.env("HOME"), "~")
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Toggle {
                  visible: root.logoChoice === "image"
                  width: parent.width
                  label: "Match my theme colors"
                  description: "Recolor the logo to your Omarchy theme. Turn off to keep a colored logo's own colors."
                  checked: root.tintLogo
                  onClicked: { root.tintLogo = !root.tintLogo; root.save({ tintLogo: root.tintLogo }) }
                }
              }

              // ---- Unlock.
              Column {
                visible: root.section.id === "unlock"
                width: parent.width
                spacing: 14

                Row {
                  spacing: 18
                  PreviewBox {
                    width: 150; height: 110
                    source: root.symbolFile(root.symbolChoice)
                    // A two-part custom symbol: the inner part on top.
                    source2: root.symbolChoice === "custom" && root.customSymbol && root.customSymbol.paths.length > 1 ? root.customSymbol.paths[1] : ""
                    tinted: root.symbolChoice === "logo" ? root.logoTinted : root.symbolChoice === "custom" ? root.tintLogo : true
                  }
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                      text: root.symbolLabel(symbolGrid.hovered || root.symbolChoice)
                      color: root.fg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.heading
                      font.weight: Font.DemiBold
                    }
                    Text {
                      width: page.width - 170
                      wrapMode: Text.WordWrap
                      text: root.symbolChoice === "custom" ? "Your own symbol, set in config.json."
                        : root.symbolChoice === "logo" ? "Your logo animates when you unlock."
                        : "One of Hello Lock's console insignia."
                      color: root.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                    Button { focusable: true; text: "Play unlock"; bordered: true; onClicked: root.unlockPreviewRequested(root.builtinSymbols.indexOf(root.symbolChoice) >= 0 ? root.symbolChoice : "") }
                  }
                }

                Column {
                  id: symbolGrid
                  spacing: 6
                  property string hovered: ""
                  Repeater {
                    model: root.symbolGroups
                    Row {
                      id: groupRow
                      required property var modelData
                      spacing: 6
                      Text {
                        width: 74
                        anchors.verticalCenter: parent.verticalCenter
                        text: groupRow.modelData.label
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
                        font.family: "Share Tech Mono"
                        font.pixelSize: 11
                        font.letterSpacing: 1.5
                      }
                      Repeater {
                        model: groupRow.modelData.ids
                        SymbolTile {
                          required property string modelData
                          source: root.symbolFile(modelData)
                          source2: modelData === "custom" && root.customSymbol && root.customSymbol.paths.length > 1 ? root.customSymbol.paths[1] : ""
                          tinted: modelData === "logo" ? root.logoTinted : modelData === "custom" ? root.tintLogo : true
                          selected: root.symbolChoice === modelData
                          onClicked: root.chooseSymbol(modelData)
                          onHoveredChanged: symbolGrid.hovered = hovered ? modelData : (symbolGrid.hovered === modelData ? "" : symbolGrid.hovered)
                        }
                      }
                    }
                  }
                }

                Toggle {
                  width: parent.width
                  label: "Rare gold unlock"
                  description: "About one unlock in fifty plays a gold version."
                  checked: root.legendary
                  onClicked: { root.legendary = !root.legendary; root.save({ legendary: root.legendary }) }
                }
              }

              // ---- Typing.
              Column {
                visible: root.section.id === "typing"
                width: parent.width
                spacing: 14

                Flow {
                  width: parent.width
                  spacing: 8
                  Repeater {
                    model: root.typingEffects
                    Button {
                      focusable: true
                      required property var modelData
                      text: modelData.label
                      bordered: true
                      selected: root.typingEffect === modelData.id
                      onClicked: { root.typingEffect = modelData.id; root.save({ typingEffect: modelData.id }) }
                    }
                  }
                }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.typingEffects.filter(function(e) { return e.id === root.typingEffect })[0].hint
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                }
                Button {
                  focusable: true
                  text: "Preview on the lock screen"
                  bordered: true
                  enabled: root.typingEffect !== "off"
                  onClicked: root.lockPreviewRequested(root.typingEffect)
                }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "The preview types a pretend password. Click or press Esc to come back."
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              // ---- Lock screen.
              Column {
                visible: root.section.id === "lock"
                width: parent.width
                spacing: 10

                Toggle {
                  width: parent.width
                  label: "Clock and date"
                  description: "Show the time and date on the lock screen."
                  checked: root.clock
                  onClicked: { root.clock = !root.clock; root.save({ clock: root.clock }) }
                }
                Toggle {
                  width: parent.width
                  label: "Power-down effect"
                  description: "A CRT shut-off as the screen locks. It takes a private screenshot in memory and deletes it right after."
                  checked: root.powerDown
                  onClicked: { root.powerDown = !root.powerDown; root.save({ powerDown: root.powerDown }) }
                }
                Field {
                  label: "Motion"
                  hint: root.motion === "auto" ? "Follows Hyprland: calm when animations are turned off."
                    : root.motion === "reduced" ? "Fades instead of big motion, on the lock screen and the unlock."
                    : "Always the full animations."
                  ButtonGroup {
                    options: [{ value: "auto", label: "Automatic" }, { value: "full", label: "Full" }, { value: "reduced", label: "Calm" }]
                    value: root.motion
                    onChanged: function(v) { root.motion = v; root.save({ motion: v === "auto" ? null : v }) }
                  }
                }
                Button { focusable: true; text: "Preview the lock screen"; bordered: true; onClicked: root.lockPreviewRequested("") }

                Toggle {
                  visible: root.menuState === "on" || root.menuState === "off"
                  width: parent.width
                  label: "Show in the Omarchy menu"
                  description: "Adds Lock Screen under Style in the Omarchy menu, so you can open these settings without a terminal."
                  checked: root.menuState === "on"
                  onClicked: root.setMenu(root.menuState !== "on")
                }
                Text {
                  visible: root.menuState === "other" || root.menuState === "unreadable"
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.menuState === "other"
                    ? "Your Omarchy menu already has its own Style → Lock Screen entry, so Hello Lock leaves it alone. Open these settings with  omarchy-shell lock settings ."
                    : "Hello Lock couldn't read your Omarchy menu file, so it isn't changed. Open these settings with  omarchy-shell lock settings ."
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              // ---- Sound.
              Column {
                visible: root.section.id === "sound"
                width: parent.width
                spacing: 10

                Toggle {
                  width: parent.width
                  label: "Sounds"
                  description: "Play a sound on lock, unlock and a wrong password. Always silent when your audio is muted."
                  checked: root.sounds
                  onClicked: { root.sounds = !root.sounds; root.save({ sounds: root.sounds }) }
                }
                Field {
                  visible: root.sounds
                  label: "Volume"
                  hint: Math.round(root.volume * 100) + "%"
                  Row {
                    spacing: 14
                    PanelSlider {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 260
                      height: 28
                      bar: root.sliderBar
                      minimum: 0; maximum: 1; step: 0.05
                      value: root.volume
                      onMoved: function(v) { root.volume = v }
                      onReleased: function(v) { root.volume = v; root.saveSound({ volume: v }); root.testSound() }
                    }
                    Button { focusable: true; anchors.verticalCenter: parent.verticalCenter; text: "Test"; bordered: true; onClicked: root.testSound() }
                  }
                }
                Toggle {
                  visible: root.sounds
                  width: parent.width
                  label: "Quiet hours"
                  description: "No sounds overnight."
                  checked: root.quietHours
                  onClicked: {
                    root.quietHours = !root.quietHours
                    root.saveSound(root.quietHours ? { quietStart: root.quietStart, quietEnd: root.quietEnd } : { quietStart: null, quietEnd: null })
                  }
                }
                Row {
                  visible: root.sounds && root.quietHours
                  spacing: 18
                  NumberField {
                    label: "From (hour)"
                    from: 0; to: 23
                    value: root.quietStart
                    onModified: function(v) { root.quietStart = v; root.saveSound({ quietStart: v, quietEnd: root.quietEnd }) }
                  }
                  NumberField {
                    label: "Until (hour)"
                    from: 0; to: 23
                    value: root.quietEnd
                    onModified: function(v) { root.quietEnd = v; root.saveSound({ quietStart: root.quietStart, quietEnd: v }) }
                  }
                }
              }

              // ---- Weather.
              Column {
                visible: root.section.id === "privacy"
                width: parent.width
                spacing: 10

                Toggle {
                  width: parent.width
                  label: "Weather after unlocking"
                  description: "Asks wttr.in for the temperature at most every 30 minutes, using Omarchy's weather location. wttr.in sees your IP address. Turn off and Hello Lock makes no network requests at all."
                  checked: root.weather
                  onClicked: { root.weather = !root.weather; root.save({ weather: root.weather }) }
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- Small pieces.

  component Field: Column {
    id: field
    property string label: ""
    property string hint: ""
    property color hintColor: root.muted
    default property alias content: holder.data
    width: parent ? parent.width : 0
    spacing: 6
    Text {
      text: field.label
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
    }
    Item { id: holder; width: childrenRect.width; height: childrenRect.height }
    Text {
      visible: field.hint !== ""
      width: field.width
      wrapMode: Text.WordWrap
      text: field.hint
      color: field.hintColor
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  component PreviewBox: Rectangle {
    id: box
    property string source: ""
    property string source2: ""
    property bool tinted: true
    width: Math.min(420, page.width)
    height: 120
    radius: Math.max(Style.cornerRadius, 8)
    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
    border.width: 1
    border.color: root.faint
    Image {
      id: boxImage
      anchors.fill: parent
      anchors.margins: 18
      source: box.source ? root.fileUrl(box.source, root.previewVersion) : ""
      fillMode: Image.PreserveAspectFit
      sourceSize.height: Math.round(height * 2)
      asynchronous: true
      cache: false
      visible: false
    }
    MultiEffect {
      anchors.fill: boxImage
      source: boxImage
      visible: boxImage.status === Image.Ready
      brightness: box.tinted ? 1 : 0
      colorization: box.tinted ? 1 : 0
      colorizationColor: root.fg
    }
    Image {
      id: boxImage2
      anchors.fill: boxImage
      source: box.source2 ? root.fileUrl(box.source2, root.previewVersion) : ""
      fillMode: Image.PreserveAspectFit
      sourceSize.height: Math.round(height * 2)
      asynchronous: true
      cache: false
      visible: false
    }
    MultiEffect {
      anchors.fill: boxImage2
      source: boxImage2
      visible: box.source2 !== "" && boxImage2.status === Image.Ready
      brightness: box.tinted ? 1 : 0
      colorization: box.tinted ? 1 : 0
      colorizationColor: root.fg
    }
    Text {
      anchors.centerIn: parent
      visible: !box.source || boxImage.status === Image.Error
      text: !box.source ? "Type a wordmark to see it here" : "Can't show this image"
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  component SymbolTile: Rectangle {
    id: tile
    property string source: ""
    property bool tinted: true
    property string source2: ""
    property bool selected: false
    readonly property bool hovered: tileMouse.containsMouse
    signal clicked()
    activeFocusOnTab: true
    Keys.onReturnPressed: tile.clicked()
    Keys.onEnterPressed: tile.clicked()
    Keys.onSpacePressed: tile.clicked()
    width: 42; height: 42
    radius: Math.max(Style.cornerRadius, 7)
    color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
      : tileMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"
    border.color: selected || activeFocus ? root.accent : root.faint
    border.width: activeFocus ? 2 : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Image {
      id: tileImage
      x: 5; y: 5
      width: 32; height: 32
      source: tile.source ? root.fileUrl(tile.source, root.previewVersion) : ""
      fillMode: Image.PreserveAspectFit
      sourceSize.width: 64
      asynchronous: true
      cache: false
      visible: false
    }
    MultiEffect {
      anchors.fill: tileImage
      source: tileImage
      visible: tileImage.status === Image.Ready
      brightness: tile.tinted ? 1 : 0
      colorization: tile.tinted ? 1 : 0
      colorizationColor: tile.selected ? root.accent : root.fg
    }
    // A custom symbol can be two layered parts; show both, as the preview does.
    Image {
      id: tileImage2
      anchors.fill: tileImage
      source: tile.source2 ? root.fileUrl(tile.source2, root.previewVersion) : ""
      fillMode: Image.PreserveAspectFit
      sourceSize.width: 64
      asynchronous: true
      cache: false
      visible: false
    }
    MultiEffect {
      anchors.fill: tileImage2
      source: tileImage2
      visible: tile.source2 !== "" && tileImage2.status === Image.Ready
      brightness: tile.tinted ? 1 : 0
      colorization: tile.tinted ? 1 : 0
      colorizationColor: tile.selected ? root.accent : root.fg
    }
    MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
  }

  component LinkText: Text {
    id: link
    property string label: ""
    signal clicked()
    text: label
    color: linkMouse.containsMouse ? root.fg : root.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.underline: linkMouse.containsMouse
    MouseArea { id: linkMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: link.clicked() }
  }
}
