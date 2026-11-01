import QtQuick
import "Presets.js" as Presets
import "TypingSounds.js" as TypingSounds
import "settings"
import "settings/Icons.js" as Icons
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Hello Lock settings ("Studio"): an icon rail of eight sections, the
// section's controls, and a live preview stage on the right that shows what
// those controls change (settings/Stage*.qml). Each change is saved as it is
// made (through bin/hello-config) and applies on the next lock. Opened with
// `omarchy-shell lock settings`; never shown while locked, and it has no
// access to authentication. The stages only ever draw pretend content.
Item {
  id: root

  // Supplied by Service.qml.
  property string pluginDir: ""
  property string configDir: ""
  property string suggestedName: ""
  property var currentConfig: ({})
  // True while the service shows a preview: the window steps aside.
  property bool away: false
  // Optional: Hyprland animations are off. The local motion choice takes
  // precedence, so a change can be previewed before its save completes.
  property bool reducedMotion: false
  readonly property bool calm: motion === "reduced" || (motion !== "full" && reducedMotion)

  // Motion tokens. The card enters in 200 ms easing out and leaves in 150 ms
  // easing in; controls use settings/Theme.qml's 120–260 ms tokens and press
  // in slightly (not with reduced motion, which keeps plain fades).
  readonly property int enterMs: 200
  readonly property int exitMs: 150
  readonly property int hoverMs: 150
  // The card is up (false before it enters, while hidden and while leaving).
  property bool presented: false
  property bool leaving: false

  signal closed()
  signal setupRequested()
  signal unlockPreviewRequested(string symbol, string handoff)
  signal lockPreviewRequested(string effect)

  // ---- Sections.
  readonly property var sections: [
    { id: "you", label: "You", title: "You", hint: "How Hello Lock greets you." },
    { id: "logo", label: "Logo", title: "Logo", hint: "Shown on the lock screen." },
    { id: "unlock", label: "Unlock", title: "Unlock", hint: "The animation that plays when you unlock." },
    { id: "typing", label: "Typing", title: "Typing", hint: "What your logo does while you type your password." },
    { id: "lock", label: "Lock screen", title: "Lock screen", hint: "What you see when you lock." },
    { id: "sound", label: "Sound", title: "Sound", hint: "Lock, typing, unlock and wrong-password sounds." },
    { id: "presets", label: "Presets", title: "Presets", hint: "Keep several logos and symbols ready to use." },
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
  property bool greeting: true
  property bool unlockBackdrop: true
  property string typingEffect: "cells"
  property string handoff: "shuffle"
  property bool clock: true
  property bool powerDown: true
  property string motion: "auto"
  property bool sounds: true
  property string typingSound: "shuffle"
  readonly property var typingSounds: [
    { id: "off", label: "Off" }, { id: "shuffle", label: "Shuffle" },
    { id: "pulse", label: "Pulse" }, { id: "phase", label: "Phase" },
    { id: "flux", label: "Flux" }, { id: "grain", label: "Grain" },
    { id: "drift", label: "Drift" }, { id: "circuit", label: "Circuit" }
  ]
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
    { label: "YOURS", ids: customSymbol ? ["logo", "custom", "omarchy", "shuffle"] : ["logo", "omarchy", "shuffle"] },
    { label: "SYSTEM", ids: ["power", "prompt", "cursor", "chip", "bolt", "gear", "battery", "core"] },
    { label: "SECURITY", ids: ["shield", "key", "lock", "eye", "crosshair", "scan", "visor", "skull"] },
    { label: "SIGNAL", ids: ["radar", "antenna", "signal", "wifi", "satellite", "waveform", "link", "infinity"] },
    { label: "SPACE", ids: ["planet", "moon", "nova", "sparkle", "rocket", "comet", "ufo", "alien"] },
    { label: "RANK", ids: ["chevrons", "insignia", "medal", "crown", "star", "gem", "delta"] }
  ]
  readonly property var builtinSymbols: symbolGroups.slice(1).reduce(function(all, g) { return all.concat(g.ids) }, ["omarchy"])
  // "Shuffle" ("symbol": "@shuffle"): a different built-in every unlock. Its
  // tile and preview cycle through them while the Unlock page is open.
  property int shuffleIndex: 0
  readonly property string shuffleFace: builtinSymbols[shuffleIndex % builtinSymbols.length]
  Timer {
    interval: 900
    repeat: true
    running: root.section.id === "unlock" && win.visible
    onTriggered: root.shuffleIndex = (root.shuffleIndex + 1) % root.builtinSymbols.length
  }
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
  // How the lock screen's logo hands over to the symbol (handoff/<id>.qml).
  readonly property var handoffs: [
    { id: "shuffle", label: "Shuffle", hint: "A different one every unlock." },
    { id: "fallback", label: "Fall back", hint: "Your logo shrinks back as the symbol grows up from behind it." },
    { id: "liftoff", label: "Lift off", hint: "Your logo rises away; the symbol rises in from below." },
    { id: "slide", label: "Slide", hint: "Your logo slides out left; the symbol slides in from the right." },
    { id: "flip", label: "Flip", hint: "Your logo turns like a card and the symbol is on the other side." },
    { id: "dissolve", label: "Dissolve", hint: "Your logo blurs away into the symbol." },
    { id: "split", label: "Split", hint: "Your logo splits in half and the symbol grows out of the gap." },
    { id: "blinds", label: "Blinds", hint: "Your logo slides away in strips, left and right." },
    { id: "scatter", label: "Scatter", hint: "Your logo breaks into tiles that drift apart." },
    { id: "wipe", label: "Wipe", hint: "A scan line sweeps your logo away." },
    { id: "glitch", label: "Glitch out", hint: "Your logo glitches, tears and cuts out." },
    { id: "poweroff", label: "Power off", hint: "Your logo collapses to a dot like an old TV." },
    { id: "flythrough", label: "Fly through", hint: "Your logo rushes past you; the symbol comes from far away." },
    { id: "fold", label: "Fold in", hint: "Your logo folds into the middle and the symbol unfolds out of it." },
    { id: "drop", label: "Drop", hint: "Your logo falls away; the symbol drops in from above." },
    { id: "pixelate", label: "Pixelate", hint: "Your logo breaks up into big pixels." }
  ]
  readonly property string previewSymbol: symbolChoice === "shuffle" ? shuffleFace : builtinSymbols.indexOf(symbolChoice) >= 0 ? symbolChoice : ""
  readonly property string previewHandoff: handoff === "shuffle" ? "" : handoff

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
    if (id === "shuffle") id = shuffleFace
    return pluginDir ? pluginDir + "/symbols/" + id + ".svg" : ""
  }
  function symbolLabel(id) {
    if (id === "logo") return logoChoice === "wordmark" ? "My name" : "My logo"
    if (id === "custom") return "Custom"
    if (id === "shuffle") return "Shuffle"
    return id.charAt(0).toUpperCase() + id.slice(1)
  }

  // ---- Stage state shared by a section's controls and its preview.
  // The typing effect on the stage (Shuffle keeps showing the last one).
  property string typingPreview: "cells"
  property bool previewBirthday: false
  property bool greetingRowHovered: false
  property string presetDeleteId: ""
  // Reduced motion for every Studio control and stage.
  Binding { target: Theme; property: "calm"; value: root.calm }

  // Bundled fonts (SIL OFL 1.1). The service registers them too; loading
  // them here keeps the window right when it is opened on its own.
  FontLoader { source: Qt.resolvedUrl("fonts/Oxanium-Variable.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/ShareTechMono-Regular.ttf") }

  // The plugin version for the rail's foot.
  property string version: ""
  FileView {
    path: root.pluginDir ? root.pluginDir + "/manifest.json" : ""
    printErrors: false
    onLoaded: { try { root.version = String(JSON.parse(text()).version || "") } catch (e) {} }
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
      symbolChoice = builtin === "shuffle" || (builtin && builtinSymbols.indexOf(builtin) >= 0) ? builtin : "logo"
    }

    legendary = c.legendary !== false
    greeting = c.greeting !== false
    unlockBackdrop = c.unlockBackdrop !== false
    var effect = str(c.typingEffect).toLowerCase()
    typingEffect = typingEffects.some(function(e) { return e.id === effect }) ? effect : "cells"
    if (typingEffect !== "shuffle") typingPreview = typingEffect
    var handoffId = str(c.handoff).toLowerCase()
    handoff = handoffs.some(function(h) { return h.id === handoffId }) ? handoffId : "shuffle"
    clock = c.clock !== false
    powerDown = c.powerDown !== false
    motion = c.motion === "reduced" || c.motion === "full" ? c.motion : "auto"
    sounds = c.sounds !== false
    typingSound = TypingSounds.normalize(c.typingSound)
    weather = c.weather !== false
    soundGetProc.running = true
    menuStatusProc.running = true
    savedOnce = false
    confirmPresetDelete = false
    presetDeleteId = ""
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
    if (exitAction || leaving) return
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
      // Everything is written: fade the card out (input off), then report.
      // A Timer, not the animation, emits, so a hidden window still closes.
      root.leaving = true
      root.presented = false
      leaveTimer.action = action
      leaveTimer.start()
    }
  }
  Timer {
    id: leaveTimer
    property string action: ""
    interval: root.exitMs
    onTriggered: {
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
  function testSound() { playCue("unlock-short") }
  // Plays one bundled cue through the sound helper (ignores quiet hours, still
  // respects mute and the off switch): one process per click, never per key.
  function playCue(name) {
    if (!/^[a-z0-9-]+$/.test(String(name))) return
    testSoundProc.running = false
    testSoundProc.command = [pluginDir + "/bin/hello-sound", "--test", String(name)]
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

  // ---- The window: a centered card over a dimmed desktop. The card is laid
  // out at the design's 1320×820 and scaled down (keeping proportions) to fit
  // smaller screens; the control columns scroll when a section is taller.
  readonly property var stageFiles: ({
    you: "StageYou.qml", logo: "StageLogo.qml", unlock: "StageUnlock.qml", typing: "StageTyping.qml",
    lock: "StageLock.qml", sound: "StageSound.qml", presets: "StagePresets.qml", privacy: "StageWeather.qml"
  })
  readonly property var stageTitles: ({
    you: "The greeting when you unlock", logo: "Your lock screen", unlock: "The moment you unlock",
    typing: "Your logo while you type", lock: "The moment you lock", sound: "Every cue, on one desk",
    presets: "What each preset looks like", privacy: "Weather in the unlock line"
  })
  // An open dropdown menu (Esc and clicks elsewhere close it first).
  property Item openMenu: null
  // The current section's preview (the preview harness drives its actions).
  property Item currentStage: null

  PanelWindow {
    id: win
    visible: !root.picking && !root.away
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hello-lock-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Enter on open and again on coming back from a preview or the file
    // chooser; drop to the closed pose while hidden, so that is instant.
    onVisibleChanged: {
      if (!visible) root.presented = false
      else if (!root.leaving) Qt.callLater(function() { if (win.visible && !root.leaving) root.presented = true })
    }
    Component.onCompleted: Qt.callLater(function() { if (win.visible && !root.leaving) root.presented = true })

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.42)
      opacity: root.presented ? 1 : 0
      Presence on opacity {}
      MouseArea { anchors.fill: parent; enabled: !root.leaving; onClicked: root.requestExit("close") }
    }

    FocusScope {
      id: card
      focus: true
      enabled: !root.leaving
      width: 1320
      height: 820
      anchors.centerIn: parent
      readonly property real fit: Math.min(1, (win.width - 40) / width, (win.height - 40) / height)
      opacity: root.presented ? 1 : 0
      // Rides the opacity animation (one driver, same curve): 0.98 -> 1 on
      // the way in, back on the way out. Reduced motion: fade only.
      scale: fit * (root.calm ? 1 : 0.98 + 0.02 * opacity)
      Component.onCompleted: forceActiveFocus()
      Presence on opacity {}

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.openMenu) root.openMenu.open = false
          else root.requestExit("close")
          event.accepted = true
        }
        else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_PageDown || event.key === Qt.Key_Tab)) { root.moveSection(1); event.accepted = true }
        else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_PageUp || event.key === Qt.Key_Backtab)) { root.moveSection(-1); event.accepted = true }
      }

      // Clicks on the card never reach the scrim.
      MouseArea { anchors.fill: parent; onClicked: card.forceActiveFocus() }

      RectangularShadow {
        anchors.fill: frame
        offset.y: 40
        blur: 120
        radius: frame.radius
        color: Qt.rgba(0, 0, 0, 0.6)
      }

      Rectangle {
        id: frame
        anchors.fill: parent
        radius: 14
        color: Theme.deep

        Rail {
          id: rail
          height: parent.height
          topLeftRadius: frame.radius
          bottomLeftRadius: frame.radius
          sections: root.sections
          current: root.sectionIndex
          mark: root.pluginDir ? root.pluginDir + "/symbols/lock.svg" : ""
          version: root.version
          onPicked: function(index) { root.sectionIndex = index; card.forceActiveFocus() }
        }

        // ---- Controls: the section's title and settings, then the footer.
        Item {
          id: controls
          x: rail.width
          width: 428
          height: parent.height

          Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 1
            color: Theme.a(Theme.line, 0.55)
          }

          Item {
            id: pages
            anchors { top: parent.top; left: parent.left; right: parent.right; bottom: footer.top; rightMargin: 1 }
            Repeater {
              model: root.sections
              Page {
                body: [youPage, logoPage, unlockPage, typingPage, lockPage, soundPage, presetsPage, weatherPage][index]
              }
            }
          }

          // Status, and a way back into setup.
          Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; rightMargin: 1 }
            height: Math.max(46, statusText.implicitHeight + 28)
            Rectangle { width: parent.width; height: 1; color: Theme.a(Theme.line, 0.55) }
            readonly property bool failed: root.status !== "" && root.status !== "saving" && root.status !== "saved"
            Glyph {
              id: statusIcon
              x: 28
              y: 16
              width: 13
              height: 13
              path: footer.failed ? Icons.close : Icons.check
              strokeWidth: 2
              color: statusText.color
            }
            UiText {
              id: statusText
              anchors { left: statusIcon.right; leftMargin: 8; right: setupLink.left; rightMargin: 16 }
              y: 14
              wrapMode: Text.WordWrap
              text: root.status === "saving" ? "Saving…"
                : root.status === "saved" ? "Saved. Applies on your next lock."
                : root.status ? root.status : "Changes save as you make them."
              color: footer.failed ? Theme.alert : root.status === "saved" ? Theme.accent : Theme.muted
              font.pixelSize: 11
              Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
            }
            LinkText {
              id: setupLink
              anchors { right: parent.right; rightMargin: 28 }
              y: 15
              label: "Run the setup again"
              onClicked: root.requestExit("setup")
            }
          }
        }

        // ---- Stage: a live preview of the section.
        Rectangle {
          id: stage
          x: controls.x + controls.width
          width: parent.width - x
          height: parent.height
          topRightRadius: frame.radius
          bottomRightRadius: frame.radius
          color: Theme.deepest
          Glow {
            x: parent.width * 0.2
            y: parent.height * 0.13
            width: parent.width * 0.6
            height: parent.height * 0.5
            strength: 0.05
            midStrength: 0.02
            mid: 0.5
            reach: 0.7
          }

          Row {
            x: 28
            y: 20
            height: 32
            spacing: 10
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 6
              height: 6
              radius: 3
              color: Theme.accent
              RectangularShadow { anchors.fill: parent; radius: 3; blur: 8; color: Theme.a(Theme.accent, 0.8); z: -1 }
            }
            MonoText {
              anchors.verticalCenter: parent.verticalCenter
              text: "LIVE PREVIEW"
              tracking: 0.2
              color: Theme.fg
            }
            UiText {
              anchors.verticalCenter: parent.verticalCenter
              text: root.stageTitles[root.section.id] || ""
              color: Theme.muted
              font.pixelSize: 12
            }
          }
          ActionButton {
            anchors { top: parent.top; right: parent.right; topMargin: 20; rightMargin: 20 }
            implicitWidth: 32
            implicitHeight: 32
            iconOnly: true
            icon: Icons.close
            color: Theme.a(Theme.ground, closeHover.hovered ? 1 : 0.8)
            HoverHandler { id: closeHover }
            onClicked: root.requestExit("close")
          }

          Repeater {
            model: root.sections
            Item {
              id: stagePage
              required property int index
              required property var modelData
              readonly property bool current: root.sectionIndex === index
              anchors { fill: parent; topMargin: 52 }
              opacity: current ? 1 : 0
              visible: opacity > 0
              enabled: current
              Behavior on opacity {
                NumberAnimation { duration: Theme.uiMs; easing.type: stagePage.current ? Easing.OutCubic : Easing.InCubic }
              }
              // Loaded only while shown, so an idle stage runs nothing.
              Loader {
                id: stageLoader
                anchors.fill: parent
                readonly property bool wanted: stagePage.visible && win.visible
                function sync() {
                  if (wanted && !item) setSource(Qt.resolvedUrl("settings/" + root.stageFiles[stagePage.modelData.id]), { s: root })
                  else if (!wanted && item) setSource("")
                }
                onWantedChanged: sync()
                Component.onCompleted: sync()
                onItemChanged: if (stagePage.current) root.currentStage = item
                Connections {
                  target: stagePage
                  function onCurrentChanged() { if (stagePage.current) root.currentStage = stageLoader.item }
                }
                onStatusChanged: if (status === Loader.Error) console.warn("hello-lock settings: the " + stagePage.modelData.id + " preview failed to load")
              }
            }
          }
        }

        // Dropdown menus open in here, above everything else in the card.
        Item {
          id: menuLayer
          anchors.fill: parent
          z: 10
          MouseArea {
            anchors.fill: parent
            enabled: root.openMenu !== null
            onPressed: function(mouse) { root.openMenu.open = false; mouse.accepted = true }
          }
        }

        Rectangle {
          anchors.fill: parent
          radius: frame.radius
          color: "transparent"
          border.width: 1
          border.color: Theme.a(Theme.line, 0.75)
          z: 11
        }
      }
    }
  }

  // ---- Section pages. Each fades with the section (out easing in, in easing
  // out) and is built only while visible.
  component Page: Item {
    id: page
    required property int index
    required property var modelData
    property Component body
    readonly property bool current: root.sectionIndex === index
    anchors.fill: parent
    opacity: current ? 1 : 0
    visible: opacity > 0
    enabled: current
    Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: page.current ? Easing.OutCubic : Easing.InCubic } }
    onCurrentChanged: if (current) flick.contentY = 0

    Flickable {
      id: flick
      anchors.fill: parent
      contentHeight: pageColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: pageColumn
        x: 28
        width: flick.width - 56
        topPadding: 26
        bottomPadding: 24
        MonoText {
          text: (page.index < 9 ? "0" : "") + (page.index + 1) + " · " + page.modelData.label.toUpperCase()
          color: Theme.accent
          tracking: 0.22
          size: 11
        }
        Item { width: 1; height: 6 }
        Text {
          text: page.modelData.title
          color: Theme.fg
          font.family: Theme.display
          font.pixelSize: 30
          font.weight: Font.DemiBold
          font.letterSpacing: -0.3
          textFormat: Text.PlainText
        }
        Item { width: 1; height: 6 }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: page.modelData.hint
          color: Theme.muted
          font.pixelSize: 14
        }
        Item { width: 1; height: 22 }
        Loader {
          width: parent.width
          sourceComponent: page.visible ? page.body : null
        }
      }
    }
    // A thin scroll position mark when the section is taller than the window.
    Rectangle {
      visible: flick.contentHeight > flick.height + 1
      x: parent.width - 5
      y: flick.visibleArea.yPosition * flick.height + 4
      width: 3
      height: Math.max(24, flick.visibleArea.heightRatio * flick.height - 8)
      radius: 2
      color: Theme.a(Theme.line, flick.moving ? 1 : 0.6)
    }
  }

  // ---- 01 · You.
  Component {
    id: youPage
    Column {
      spacing: 30

      Column {
        width: parent.width
        spacing: 10
        GroupLabel {
          text: "NAME"
          MonoText { anchors.verticalCenter: parent.verticalCenter; text: "IN THE GREETING"; tracking: 0.08; size: 11 }
          Badge { letter: "A" }
        }
        InputField {
          width: parent.width
          text: root.name
          placeholderText: root.suggestedName || "Your name"
          maximumLength: 40
          onTextEdited: { root.name = text; root.save({ name: text.trim() || null }, 600) }
        }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Used in the greetings when you unlock. Leave it empty to use your account name."
          color: Theme.muted
        }
      }

      Column {
        width: parent.width
        spacing: 10
        GroupLabel {
          text: "BIRTHDAY"
          MonoText { anchors.verticalCenter: parent.verticalCenter; text: "ONCE A YEAR"; tracking: 0.08; size: 11 }
          Badge { letter: "B"; lit: root.previewBirthday }
        }
        Item {
          width: parent.width
          height: 42
          Row {
            spacing: 10
            InputField {
              id: monthField
              width: 76
              mono: true
              tracking: 0.08
              text: root.birthMonth
              placeholderText: "MM"
              maximumLength: 2
              inputMethodHints: Qt.ImhDigitsOnly
              validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
              onTextEdited: { root.birthMonth = text; if (text.length === 2) dayField.forceActiveFocus(); root.saveBirthday() }
            }
            UiText {
              anchors.verticalCenter: parent.verticalCenter
              text: "/"
              color: Theme.line
              font.pixelSize: 20
              font.weight: Font.Light
            }
            InputField {
              id: dayField
              width: 76
              mono: true
              tracking: 0.08
              text: root.birthDay
              placeholderText: "DD"
              maximumLength: 2
              inputMethodHints: Qt.ImhDigitsOnly
              validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
              onTextEdited: { root.birthDay = text; root.saveBirthday() }
            }
          }
          ActionButton {
            visible: root.birthMonth !== "" || root.birthDay !== ""
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "Clear"
            fontSize: 12
            onClicked: { root.birthMonth = ""; root.birthDay = ""; monthField.text = ""; dayField.text = ""; root.previewBirthday = false; root.saveBirthday() }
          }
        }
        Row {
          spacing: 10
          MonoText { width: 76; leftPadding: 2; text: "MONTH"; tracking: 0.2; size: 10; color: Theme.a(Theme.muted, 0.75) }
          Item { width: 7; height: 1 }
          MonoText { width: 76; leftPadding: 2; text: "DAY"; tracking: 0.2; size: 10; color: Theme.a(Theme.muted, 0.75) }
        }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.birthdayValid ? "Optional. On the day, your unlock says happy birthday." : "That date doesn't exist."
          color: root.birthdayValid ? Theme.muted : Theme.alert
        }
      }

      Column {
        width: parent.width
        spacing: 10
        GroupLabel {
          text: "STATUS WORD"
          MonoText { anchors.verticalCenter: parent.verticalCenter; text: "FIRST LINE"; tracking: 0.08; size: 11 }
          Badge { letter: "C" }
        }
        InputField {
          width: parent.width
          mono: true
          tracking: 0.32
          suffix: "+ ONLINE"
          text: root.brand
          placeholderText: "SYSTEM"
          maximumLength: 16
          font.capitalization: Font.AllUppercase
          onTextEdited: { root.brand = text; root.save({ brand: text.trim() || null }, 600) }
        }
        Flow {
          width: parent.width
          UiText { text: "The first line of the unlock: "; color: Theme.muted }
          MonoText { text: (root.brand.trim() ? root.brand.trim().toUpperCase() : "SYSTEM") + " ONLINE"; color: Theme.fg; tracking: 0.12; size: 13 }
          UiText { text: "."; color: Theme.muted }
        }
      }
    }
  }

  // ---- 02 · Logo.
  Component {
    id: logoPage
    Column {
      id: logoColumn
      spacing: 24
      readonly property var choices: [{ value: "wordmark", label: "Type a wordmark" }, { value: "image", label: "Use an image" }, { value: "omarchy", label: "Omarchy logo" }]

      Column {
        width: parent.width
        spacing: 10
        GroupLabel {
          text: "SOURCE"
          value: root.logoChoice === "wordmark" ? "Wordmark" : root.logoChoice === "image" ? "Image" : "Omarchy logo"
        }
        Segmented {
          options: logoColumn.choices
          value: root.logoChoice
          onPicked: function(v) { root.chooseLogo(v) }
        }
        // The image in use (or the last one chosen), and the file chooser.
        Rectangle {
          width: parent.width
          height: imageColumn.implicitHeight + 24
          radius: 10
          color: Theme.a(Theme.ground, 0.7)
          border.width: 1
          border.color: Theme.a(Theme.line, 0.6)
          opacity: root.logoChoice === "image" ? 1 : 0.55
          Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
          Column {
            id: imageColumn
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 12
            Row {
              spacing: 14
              Rectangle {
                width: 112
                height: 56
                radius: 7
                color: Theme.deepest
                border.width: 1
                border.color: Theme.a(Theme.line, 0.45)
                LogoImage {
                  anchors { fill: parent; margins: 12 }
                  visible: root.imagePath !== ""
                  source: root.imagePath
                  tinted: root.tintLogo
                  color: Theme.fg
                  version: root.previewVersion
                }
                Glyph {
                  visible: root.imagePath === ""
                  anchors.centerIn: parent
                  width: 18; height: 18
                  path: Icons.folder
                  color: Theme.muted
                }
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: imageColumn.width - 126
                spacing: 4
                UiText {
                  width: parent.width
                  elide: Text.ElideMiddle
                  text: root.imagePath ? root.imagePath.split("/").pop() : "No image chosen yet"
                  font.pixelSize: 14
                  font.weight: Font.Medium
                }
                MonoText {
                  width: parent.width
                  elide: Text.ElideMiddle
                  text: root.imagePath ? root.imagePath.replace(Quickshell.env("HOME"), "~").replace(/[^\/]*$/, "") : "SVG, PNG, JPG OR WEBP"
                  size: 10
                }
              }
            }
            ActionButton {
              width: parent.width
              icon: Icons.folder
              text: root.imagePath ? "Choose a different file…" : "Choose a file…"
              onClicked: root.pickImage()
            }
          }
        }
      }

      Column {
        id: wordmarkSection
        width: parent.width
        spacing: 10
        readonly property bool active: root.logoChoice === "wordmark"
        GroupLabel {
          text: "WORDMARK"
          value: wordmarkSection.active ? "In use" : "Used with Type a wordmark"
          valueColor: wordmarkSection.active ? Theme.accent : Theme.muted
        }
        Item {
          width: parent.width
          height: wordmarkColumn.implicitHeight + 24
          opacity: wordmarkSection.active ? 1 : 0.55
          Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
          Rectangle {
            visible: wordmarkSection.active
            anchors.fill: parent
            radius: 10
            color: "transparent"
            border.width: 1
            border.color: Theme.a(Theme.line, 0.7)
          }
          DashedBox {
            visible: !wordmarkSection.active
            anchors.fill: parent
            radius: 10
            color: Theme.a(Theme.line, 0.9)
          }
          Column {
            id: wordmarkColumn
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 10
            InputField {
              id: wmField
              width: parent.width
              boxHeight: 38
              mono: true
              tracking: 0.2
              enabled: root.logoChoice === "wordmark"
              text: root.wordmarkText
              placeholderText: "YOUR NAME OR BRAND"
              maximumLength: 20
              size: 14
              font.capitalization: Font.AllUppercase
              Component.onCompleted: root.wordmarkField = wmField
              onTextEdited: { root.wordmarkText = text; root.renderWordmark(true) }
            }
            Flow {
              width: parent.width
              spacing: 4
              enabled: root.logoChoice === "wordmark"
              Repeater {
                model: root.wordmarkStyles
                Chip {
                  required property var modelData
                  width: Math.max(54, implicitWidth)
                  implicitHeight: 26
                  neutral: true
                  fontSize: 11
                  text: modelData.label
                  selected: root.wordmarkStyle === modelData.value
                  onClicked: { root.wordmarkStyle = modelData.value; root.renderWordmark(true) }
                }
              }
            }
          }
        }
        UiText {
          visible: wordmarkSection.active
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.wordmarkError ? root.wordmarkError
            : root.wordmarkStyle === "omarchy" ? "The Omarchy logo's own font by CoSMiC cHiLD. Letters only."
            : "Letters and numbers, up to 20."
          color: root.wordmarkError ? Theme.alert : Theme.muted
        }
      }

      Column {
        visible: root.logoChoice === "image"
        width: parent.width
        spacing: 4
        GroupLabel { text: "COLOR" }
        ToggleRow {
          title: "Match my theme colors"
          description: "Recolor the logo to your Omarchy theme. Turn off to keep a colored logo's own colors."
          checked: root.tintLogo
          onToggled: { root.tintLogo = !root.tintLogo; root.save({ tintLogo: root.tintLogo }) }
        }
      }
    }
  }

  // ---- 03 · Unlock.
  Component {
    id: unlockPage
    Column {
      id: unlockColumn
      spacing: 24
      property string hovered: ""

      Column {
        width: parent.width
        spacing: 10
        GroupLabel { text: "SYMBOL"; value: root.symbolLabel(unlockColumn.hovered || root.symbolChoice) }
        // Jump to a group; follows the list as it scrolls.
        Segmented {
          itemPadding: 5
          proportional: true
          options: root.symbolGroups.map(function(g) { return { value: g.label, label: g.label.charAt(0) + g.label.slice(1).toLowerCase() } })
          value: root.symbolGroups[symbolList.groupIndex].label
          onPicked: function(v) {
            for (var i = 0; i < root.symbolGroups.length; i++) if (root.symbolGroups[i].label === v) symbolList.showGroup(i, true)
          }
        }
        Item {
          width: parent.width
          height: 136
          Flickable {
            id: symbolList
            anchors.fill: parent
            contentHeight: symbolGroupsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property real tileGap: (width - 8 * 41) / 7
            readonly property int groupIndex: {
              var y = contentY + 20, found = 0
              for (var i = 0; i < symbolGroupsRepeater.count; i++) {
                var g = symbolGroupsRepeater.itemAt(i)
                if (g && g.y <= y) found = i
              }
              return found
            }
            function showGroup(i, animate) {
              var g = symbolGroupsRepeater.itemAt(i)
              if (!g) return
              var target = Math.max(0, Math.min(g.y, contentHeight - height))
              if (animate && !Theme.calm) { scrollAnim.to = target; scrollAnim.restart() }
              else contentY = target
            }
            NumberAnimation { id: scrollAnim; target: symbolList; property: "contentY"; duration: Theme.slowMs; easing.type: Easing.OutCubic }
            // Open at the chosen symbol's group, once the list is laid out.
            property bool placed: false
            onContentHeightChanged: if (!placed && contentHeight > height) {
              placed = true
              Qt.callLater(function() {
                for (var i = 0; i < root.symbolGroups.length; i++) if (root.symbolGroups[i].ids.indexOf(root.symbolChoice) >= 0) symbolList.showGroup(i, false)
              })
            }

            Column {
              id: symbolGroupsColumn
              width: symbolList.width
              spacing: 8
              Repeater {
                id: symbolGroupsRepeater
                model: root.symbolGroups
                Column {
                  id: groupColumn
                  required property var modelData
                  required property int index
                  width: symbolGroupsColumn.width
                  spacing: 8
                  topPadding: 4
                  MonoText {
                    text: groupColumn.modelData.label
                    tracking: 0.2
                    size: 10
                    color: Theme.a(Theme.muted, 0.75)
                  }
                  Row {
                    spacing: symbolList.tileGap
                    Repeater {
                      model: groupColumn.modelData.ids
                      SymbolTile {
                        required property string modelData
                        symbol: modelData
                        selected: root.symbolChoice === modelData
                        onClicked: root.chooseSymbol(modelData)
                        onHoveredChanged: unlockColumn.hovered = hovered ? modelData : (unlockColumn.hovered === modelData ? "" : unlockColumn.hovered)
                      }
                    }
                  }
                }
              }
              // Room for the last group to reach the top of the list.
              Item { width: 1; height: Math.max(0, symbolList.height - 49 - 20 - 8) }
            }
          }
          // The list fades out at its foot.
          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 34
            gradient: Gradient {
              GradientStop { position: 0; color: Theme.a(Theme.deep, 0) }
              GradientStop { position: 0.7; color: Theme.a(Theme.deep, 0.85) }
              GradientStop { position: 1; color: Theme.deep }
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: 2
        GroupLabel { text: "WHAT PLAYS"; implicitHeight: 22 }
        ToggleRow {
          title: "Rare gold unlock"
          description: "About one unlock in fifty plays a gold version."
          checked: root.legendary
          onToggled: { root.legendary = !root.legendary; root.save({ legendary: root.legendary }) }
        }
        ToggleRow {
          id: greetingRow
          title: "Greeting"
          tag: hovered && root.greeting ? "SHOWN IN PREVIEW" : ""
          description: "The hello line, status and weather text after you unlock. Turn it off to play just the symbol."
          checked: root.greeting
          onToggled: { root.greeting = !root.greeting; root.save({ greeting: root.greeting }) }
          onHoveredChanged: root.greetingRowHovered = hovered
          Component.onDestruction: root.greetingRowHovered = false
        }
        ToggleRow {
          title: "Background"
          description: "The blurred backdrop behind the unlock. Turn it off and the symbol plays over your desktop and the windows you had open."
          checked: root.unlockBackdrop
          onToggled: { root.unlockBackdrop = !root.unlockBackdrop; root.save({ unlockBackdrop: root.unlockBackdrop }) }
        }
      }

      // How the lock screen's logo hands over to the symbol. Not in setup on
      // purpose: it shuffles unless someone picks one here.
      Column {
        id: transitionSection
        width: parent.width
        spacing: 10
        readonly property var current: root.handoffs.filter(function(h) { return h.id === root.handoff })[0]
        GroupLabel {
          text: "TRANSITION"
          Row {
            anchors.verticalCenter: parent.verticalCenter
            UiText { id: handoffName; text: transitionSection.current.label; font.weight: Font.Medium }
            UiText {
              width: Math.min(implicitWidth, transitionSection.width - 104 - handoffName.implicitWidth)
              elide: Text.ElideRight
              text: " · " + transitionSection.current.hint
              color: Theme.muted
              font.pixelSize: 12
            }
          }
        }
        Grid {
          columns: 4
          spacing: 4
          Repeater {
            model: root.handoffs
            Chip {
              required property var modelData
              width: (transitionSection.width - 12) / 4
              text: modelData.label
              icon: modelData.id === "shuffle" ? Icons.shuffle : ""
              selected: root.handoff === modelData.id
              onClicked: { root.handoff = modelData.id; root.save({ handoff: modelData.id }) }
            }
          }
        }
      }
    }
  }

  // ---- 04 · Typing.
  Component {
    id: typingPage
    Column {
      spacing: 22
      Column {
        width: parent.width
        spacing: 6
        GroupLabel {
          text: "EFFECT"
          implicitHeight: 26
          value: root.typingEffects.filter(function(e) { return e.id === root.typingEffect })[0].label
        }
        Column {
          width: parent.width
          spacing: 2
          Repeater {
            // Shuffle first, as in the design; then the effects, then Off.
            model: root.typingEffects.filter(function(e) { return e.id === "shuffle" }).concat(root.typingEffects.filter(function(e) { return e.id !== "shuffle" }))
            EffectRow {
              required property var modelData
              effect: modelData
              selected: root.typingEffect === modelData.id
              previewing: root.typingPreview === modelData.id && root.typingEffect !== modelData.id
              onClicked: {
                root.typingEffect = modelData.id
                if (modelData.id !== "shuffle") root.typingPreview = modelData.id
                root.save({ typingEffect: modelData.id })
              }
            }
          }
        }
      }
      Column {
        width: parent.width
        spacing: 16
        ActionButton {
          width: parent.width
          implicitHeight: 36
          icon: Icons.monitor
          text: "Preview on the lock screen"
          enabled: root.typingEffect !== "off"
          onClicked: root.lockPreviewRequested(root.typingEffect)
        }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "The preview types a pretend password. Click or press Esc to come back."
          color: Theme.muted
          font.pixelSize: 12
        }
      }
    }
  }

  // ---- 05 · Lock screen.
  Component {
    id: lockPage
    Column {
      spacing: 22
      Column {
        width: parent.width
        spacing: 2
        GroupLabel { text: "ON THE LOCK SCREEN"; implicitHeight: 24 }
        ToggleRow {
          title: "Clock and date"
          description: "Show the time and date on the lock screen."
          checked: root.clock
          onToggled: { root.clock = !root.clock; root.save({ clock: root.clock }) }
        }
        ToggleRow {
          title: "Power-down effect"
          tag: root.powerDown ? "STORYBOARD BELOW" : ""
          description: "A CRT shut-off as the screen locks. It takes a private screenshot in memory and deletes it right after."
          checked: root.powerDown
          onToggled: { root.powerDown = !root.powerDown; root.save({ powerDown: root.powerDown }) }
        }
      }
      Column {
        width: parent.width
        spacing: 10
        GroupLabel { text: "MOTION" }
        Segmented {
          options: [{ value: "auto", label: "Automatic" }, { value: "full", label: "Full" }, { value: "reduced", label: "Calm" }]
          value: root.motion
          onPicked: function(v) { root.motion = v; root.save({ motion: v === "auto" ? null : v }) }
        }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.motion === "auto" ? "Follows Hyprland: calm when animations are turned off."
            : root.motion === "reduced" ? "Fades instead of big motion, on the lock screen and the unlock."
            : "Always the full animations."
          color: Theme.muted
        }
      }
      ActionButton {
        width: parent.width
        implicitHeight: 36
        icon: Icons.monitor
        text: "Preview the lock screen"
        onClicked: root.lockPreviewRequested("")
      }
      Column {
        visible: root.menuState !== ""
        width: parent.width
        spacing: 2
        GroupLabel { text: "SHORTCUT"; implicitHeight: 24 }
        ToggleRow {
          visible: root.menuState === "on" || root.menuState === "off"
          title: "Show in the Omarchy menu"
          description: "Adds Lock Screen under Style in the Omarchy menu, so you can open these settings without a terminal."
          checked: root.menuState === "on"
          onToggled: root.setMenu(root.menuState !== "on")
        }
        UiText {
          visible: root.menuState === "other" || root.menuState === "unreadable"
          width: parent.width
          topPadding: 6
          wrapMode: Text.WordWrap
          text: root.menuState === "other"
            ? "Your Omarchy menu already has its own Style → Lock Screen entry, so Hello Lock leaves it alone. Open these settings with  omarchy-shell lock settings ."
            : "Hello Lock couldn't read your Omarchy menu file, so it isn't changed. Open these settings with  omarchy-shell lock settings ."
          color: Theme.muted
          font.pixelSize: 12
        }
      }
    }
  }

  // ---- 06 · Sound.
  Component {
    id: soundPage
    Column {
      spacing: 22
      ToggleRow {
        title: "Sounds"
        description: "Play sounds on lock, typing, unlock and a wrong password. Always silent when your audio is muted."
        checked: root.sounds
        onToggled: { root.sounds = !root.sounds; root.save({ sounds: root.sounds }) }
      }
      // Everything below dims (and rests) while sounds are off.
      Column {
        width: parent.width
        spacing: 24
        enabled: root.sounds
        opacity: root.sounds ? 1 : 0.42
        Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }

        Column {
          width: parent.width
          spacing: 10
          GroupLabel {
            text: "TYPING SOUND"
            value: root.typingSounds.filter(function(t) { return t.id === root.typingSound })[0].label
          }
          Grid {
            columns: 4
            spacing: 4
            Repeater {
              model: root.typingSounds
              Chip {
                required property var modelData
                width: (371 - 12) / 4
                text: modelData.label
                icon: modelData.id === "shuffle" ? Icons.shuffle : ""
                selected: root.typingSound === modelData.id
                onClicked: { root.typingSound = modelData.id; root.save({ typingSound: modelData.id }) }
              }
            }
          }
          UiText {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Dark synth pulses. Shuffle changes the sound each lock. Silent with reduced motion."
            color: Theme.muted
          }
        }

        Column {
          width: parent.width
          spacing: 12
          GroupLabel {
            text: "VOLUME"
            MonoText { anchors.verticalCenter: parent.verticalCenter; text: Math.round(root.volume * 100) + "%"; color: Theme.fg; tracking: 0.04 }
          }
          Item {
            width: parent.width
            height: 32
            LineSlider {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - testButton.width - 16
              value: root.volume
              onMoved: function(v) { root.volume = v }
              onReleased: function(v) { root.volume = v; root.saveSound({ volume: v }); root.testSound() }
              onStepped: function(v) { root.volume = v; root.saveSound({ volume: v }) }
            }
            ActionButton {
              id: testButton
              anchors.right: parent.right
              icon: Icons.play
              iconFilled: true
              text: "Test"
              onClicked: root.testSound()
            }
          }
        }

        Column {
          width: parent.width
          spacing: 6
          ToggleRow {
            title: "Quiet hours"
            description: "No sounds overnight."
            checked: root.quietHours
            onToggled: {
              root.quietHours = !root.quietHours
              root.saveSound(root.quietHours ? { quietStart: root.quietStart, quietEnd: root.quietEnd } : { quietStart: null, quietEnd: null })
            }
          }
          Row {
            spacing: 12
            enabled: root.quietHours
            opacity: root.quietHours ? 1 : 0.42
            Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
            HourField {
              label: "FROM (HOUR)"
              value: root.quietStart
              onModified: function(v) { root.quietStart = v; root.saveSound({ quietStart: v, quietEnd: root.quietEnd }) }
            }
            HourField {
              label: "UNTIL (HOUR)"
              value: root.quietEnd
              onModified: function(v) { root.quietEnd = v; root.saveSound({ quietStart: root.quietStart, quietEnd: v }) }
            }
          }
        }
      }
    }
  }

  // ---- 07 · Presets. All writes wait for the normal autosave queue.
  Component {
    id: presetsPage
    Column {
      spacing: 22
      enabled: !root.presetBusy
      Column {
        width: parent.width
        spacing: 10
        GroupLabel { text: "ON EACH LOCK" }
        Dropdown {
          width: parent.width
          overlay: menuLayer
          options: [{ value: "manual", label: "Keep current branding" }, { value: "cycle", label: "Cycle presets" }, { value: "shuffle", label: "Shuffle presets" }]
          value: root.presetMode
          onPicked: function(v) { root.runPreset("mode", v) }
          onOpenChanged: root.openMenu = open ? this : (root.openMenu === this ? null : root.openMenu)
          Component.onDestruction: if (root.openMenu === this) root.openMenu = null
        }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Cycle follows saved order. Shuffle avoids the previous preset. With no presets, your current branding is used."
          color: Theme.muted
        }
      }
      Column {
        width: parent.width
        spacing: 10
        GroupLabel { text: "SAVE CURRENT BRANDING" }
        InputField {
          width: parent.width
          boxHeight: 38
          size: 14
          text: root.presetName
          placeholderText: "Name this preset"
          maximumLength: 60
          onTextEdited: root.presetName = text
          onAccepted: if (root.presetName.trim()) root.runPreset("create", root.presetName)
        }
        Row {
          spacing: 6
          ActionButton {
            width: (371 - 12) / 3
            kind: "solid"
            icon: Icons.plus
            text: "Save new"
            enabled: !!root.presetName.trim()
            onClicked: root.runPreset("create", root.presetName)
          }
          ActionButton {
            width: (371 - 12) / 3
            text: "Update selected"
            enabled: !!root.selectedPreset && !!root.presetName.trim()
            onClicked: root.runPreset("update", root.presetName)
          }
          ActionButton {
            width: (371 - 12) / 3
            text: "Use next"
            enabled: root.brandingPresets.length > 0
            onClicked: root.runPreset("next", "")
          }
        }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Includes brand text, logo or wordmark, tint and unlock symbol. Change these in You, Logo and Unlock, then save a new preset or update the selected one."
          color: Theme.muted
        }
      }
      Column {
        width: parent.width
        spacing: 4
        GroupLabel {
          text: "SAVED PRESETS"
          implicitHeight: 24
          value: root.brandingPresets.length ? String(root.brandingPresets.length) : ""
        }
        UiText {
          visible: root.brandingPresets.length === 0
          width: parent.width
          topPadding: 4
          wrapMode: Text.WordWrap
          text: "No presets yet. Save your current branding to get started."
          color: Theme.muted
        }
        Repeater {
          model: root.brandingPresets
          PresetRow {
            required property var modelData
            preset: modelData
          }
        }
      }
    }
  }

  // ---- 08 · Weather.
  Component {
    id: weatherPage
    Column {
      spacing: 22
      Column {
        width: parent.width
        spacing: 2
        GroupLabel { text: "NETWORK"; implicitHeight: 22 }
        ToggleRow {
          title: "Weather after unlocking"
          description: "Asks wttr.in for the temperature at most every 30 minutes, using Omarchy's weather location. wttr.in sees your IP address. Turn off and Hello Lock makes no network requests at all."
          checked: root.weather
          onToggled: { root.weather = !root.weather; root.save({ weather: root.weather }) }
        }
      }
      // What the setting means for privacy, stated plainly (read-only).
      Column {
        width: parent.width
        spacing: 10
        GroupLabel {
          text: "WHAT LEAVES THIS MACHINE"
          Glyph { anchors.verticalCenter: parent.verticalCenter; width: 11; height: 11; path: Icons.lock; strokeWidth: 2; color: Theme.muted }
          UiText { anchors.verticalCenter: parent.verticalCenter; text: "Read-only"; color: Theme.muted; font.pixelSize: 12 }
        }
        Rectangle {
          width: parent.width
          height: factColumn.implicitHeight
          radius: 10
          color: Theme.deepest
          border.width: 1
          border.color: Theme.a(Theme.line, 0.6)
          Column {
            id: factColumn
            x: 14
            width: parent.width - 28
            Repeater {
              model: root.weather ? [
                { key: "SENT", value: "Your weather location and unit" },
                { key: "SEEN", value: "Your IP address, by wttr.in" },
                { key: "CACHED", value: "For 30 minutes, on this machine", note: "~/.cache/hello-lock/weather.json" },
                { key: "OTHER", value: "Nothing else in Hello Lock connects." }
              ] : [
                { key: "SENT", value: "Nothing. Weather is off." },
                { key: "SEEN", value: "Nothing. No requests are made." },
                { key: "CACHED", value: "Only an earlier forecast, if any", note: "~/.cache/hello-lock/weather.json" },
                { key: "OTHER", value: "Nothing else in Hello Lock connects." }
              ]
              Item {
                required property var modelData
                required property int index
                width: factColumn.width
                height: factValue.implicitHeight + 22
                MonoText {
                  y: 13
                  width: 84
                  text: modelData.key
                  tracking: 0.16
                  size: 11
                }
                Column {
                  id: factValue
                  x: 96
                  y: 11
                  width: parent.width - 96
                  spacing: 3
                  UiText { width: parent.width; wrapMode: Text.WordWrap; text: modelData.value }
                  MonoText { visible: !!modelData.note; text: modelData.note || ""; size: 11 }
                }
                Rectangle {
                  visible: index < 3
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: 1
                  color: Theme.a(Theme.line, 0.4)
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- Small pieces.

  // A symbol in the Unlock grid: dim until chosen, then accent with a glow.
  component SymbolTile: Rectangle {
    id: tile
    property string symbol: ""
    property bool selected: false
    readonly property bool hovered: tileMouse.containsMouse
    signal clicked()
    width: 41
    height: 41
    radius: 8
    color: selected ? Theme.a(Theme.accent, 0.12) : tileMouse.containsMouse ? Theme.a(Theme.line, 0.45) : Theme.a(Theme.ground, 0.7)
    border.width: activeFocus ? 2 : 1
    border.color: selected || activeFocus ? Theme.accent : Theme.a(Theme.line, 0.45)
    scale: tileMouse.pressed ? Theme.pressScale : 1
    activeFocusOnTab: true
    Keys.onReturnPressed: tile.clicked()
    Keys.onEnterPressed: tile.clicked()
    Keys.onSpacePressed: tile.clicked()
    Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
    RectangularShadow {
      visible: tile.selected
      anchors.fill: parent
      radius: tile.radius
      blur: 16
      color: Theme.a(Theme.accent, 0.18)
      z: -1
    }
    Glyph {
      visible: tile.symbol === "shuffle"
      anchors.centerIn: parent
      width: 18; height: 18
      path: Icons.shuffle
      strokeWidth: 2
      color: tile.selected ? Theme.accent : Theme.a(Theme.fg, 0.62)
    }
    // A custom symbol can be two layered parts; both are shown.
    LogoImage {
      visible: tile.symbol !== "shuffle"
      anchors.centerIn: parent
      width: tile.symbol === "logo" ? 30 : 22
      height: 22
      opacity: tile.selected ? 1 : 0.62
      source: root.symbolFile(tile.symbol)
      source2: tile.symbol === "custom" && root.customSymbol && root.customSymbol.paths.length > 1 ? root.customSymbol.paths[1] : ""
      tinted: tile.symbol === "logo" ? root.logoTinted : tile.symbol === "custom" ? root.tintLogo : true
      color: tile.selected ? Theme.accent : Theme.fg
      version: root.previewVersion
    }
    MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
  }

  // A typing effect in the list: a thumbnail, its name (tagged when it is the
  // one the stage shows) and a radio.
  component EffectRow: Rectangle {
    id: effectRow
    property var effect: ({})
    property bool selected: false
    property bool previewing: false
    signal clicked()
    x: -12
    width: parent ? parent.width + 24 : 0
    height: 47
    radius: 10
    color: selected ? Theme.a(Theme.accent, 0.07) : previewing ? Theme.a(Theme.line, 0.34)
      : rowMouse.containsMouse ? Theme.a(Theme.line, 0.22) : "transparent"
    border.width: selected || activeFocus ? 1 : 0
    border.color: activeFocus && !selected ? Theme.a(Theme.accent, 0.5) : Theme.a(Theme.accent, 0.7)
    activeFocusOnTab: true
    Keys.onSpacePressed: effectRow.clicked()
    Keys.onReturnPressed: effectRow.clicked()
    Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }

    Rectangle {
      x: 12
      anchors.verticalCenter: parent.verticalCenter
      width: 32
      height: 32
      radius: 7
      color: effectRow.selected ? Theme.a(Theme.accent, 0.12) : Theme.deepest
      border.width: 1
      border.color: effectRow.selected ? Theme.a(Theme.accent, 0.4) : Theme.a(Theme.line, 0.6)
      Glyph {
        anchors.centerIn: parent
        width: 15; height: 15
        path: Icons.effects[effectRow.effect.id] || ""
        strokeWidth: 2
        color: effectRow.selected ? Theme.accent : Theme.fg
      }
    }
    Column {
      x: 56
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 56 - 40
      spacing: 1
      Row {
        spacing: 8
        UiText {
          anchors.verticalCenter: parent.verticalCenter
          text: effectRow.effect.label || ""
          font.weight: effectRow.selected ? Font.DemiBold : Font.Medium
          color: effectRow.selected ? Theme.accent : Theme.fg
        }
        Tag {
          visible: effectRow.previewing
          anchors.verticalCenter: parent.verticalCenter
          text: "IN PREVIEW"
          eye: true
          neutral: true
          size: 10
        }
      }
      UiText {
        width: parent.width
        elide: Text.ElideRight
        text: effectRow.effect.hint || ""
        color: Theme.muted
        font.pixelSize: 12
      }
    }
    Rectangle {
      x: parent.width - 12 - width
      anchors.verticalCenter: parent.verticalCenter
      width: 16
      height: 16
      radius: 8
      color: "transparent"
      border.width: 1.5
      border.color: effectRow.selected ? Theme.accent : Theme.line
      Rectangle {
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: 4
        color: Theme.accent
        opacity: effectRow.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: effectRow.clicked() }
  }

  // A saved preset: its unlock symbol, name and what it contains; Use and
  // Delete (which asks first).
  component PresetRow: Rectangle {
    id: presetRow
    property var preset: ({})
    readonly property var branding: preset.branding || {}
    readonly property bool inUse: preset.id === root.selectedPreset
    readonly property bool confirming: root.confirmPresetDelete && root.presetDeleteId === preset.id
    readonly property bool shuffles: branding.symbol === "@shuffle"
    readonly property string symbolPath: {
      var parts = Array.isArray(branding.symbolParts) ? branding.symbolParts : []
      if (parts.length) return root.expand(parts[0])
      if (shuffles) return ""
      if (typeof branding.symbol === "string" && branding.symbol) return root.expand(branding.symbol)
      return typeof branding.logo === "string" && branding.logo ? root.expand(branding.logo) : root.omarchyLogo
    }
    x: -12
    width: parent ? parent.width + 24 : 0
    height: 60
    radius: 10
    color: inUse ? Theme.a(Theme.line, 0.34) : rowHover.hovered ? Theme.a(Theme.line, 0.18) : "transparent"
    border.width: inUse ? 1 : 0
    border.color: Theme.a(Theme.accent, 0.22)
    HoverHandler { id: rowHover }

    Rectangle {
      x: 12
      anchors.verticalCenter: parent.verticalCenter
      width: 38
      height: 38
      radius: 8
      color: presetRow.inUse ? Theme.a(Theme.accent, 0.12) : Theme.deepest
      border.width: 1
      border.color: presetRow.inUse ? Theme.accent : Theme.a(Theme.line, 0.6)
      Glyph {
        visible: presetRow.shuffles
        anchors.centerIn: parent
        width: 18; height: 18
        path: Icons.shuffle
        strokeWidth: 2
        color: presetRow.inUse ? Theme.accent : Theme.fg
      }
      LogoImage {
        visible: !presetRow.shuffles
        anchors.centerIn: parent
        width: 26
        height: 22
        source: presetRow.symbolPath
        tinted: presetRow.branding.tintLogo !== false || /^@/.test(presetRow.branding.symbol || "")
        color: presetRow.inUse ? Theme.accent : Theme.fg
      }
    }
    Column {
      x: 62
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 62 - actions.width - 20
      spacing: 3
      Row {
        spacing: 8
        width: parent.width
        UiText {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width - (presetRow.inUse ? 60 : 0))
          elide: Text.ElideRight
          text: presetRow.preset.name || ""
          font.pixelSize: 14
          font.weight: Font.Medium
        }
        Tag { visible: presetRow.inUse; anchors.verticalCenter: parent.verticalCenter; text: "IN USE" }
      }
      UiText {
        width: parent.width
        elide: Text.ElideRight
        text: (presetRow.branding.wordmarkText ? "Wordmark · " + (presetRow.branding.wordmarkStyle || "blocks") + " style"
          : presetRow.branding.logo ? "Image logo" : "Omarchy logo")
          + (presetRow.branding.wordmarkText ? "" : presetRow.branding.tintLogo === false ? " · own colors" : " · theme colors")
        color: Theme.muted
        font.pixelSize: 12
      }
    }
    Row {
      id: actions
      anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
      spacing: 4
      ActionButton {
        visible: !presetRow.confirming
        implicitHeight: 28
        width: 52
        radius: 6
        fontSize: 12
        text: "Use"
        enabled: !presetRow.inUse
        onClicked: root.runPreset("apply", presetRow.preset.id)
      }
      ActionButton {
        visible: !presetRow.confirming
        implicitHeight: 28
        width: 60
        radius: 6
        kind: "ghost"
        fontSize: 12
        text: "Delete"
        onClicked: { root.presetDeleteId = presetRow.preset.id; root.confirmPresetDelete = true }
      }
      ActionButton {
        visible: presetRow.confirming
        implicitHeight: 28
        radius: 6
        padding: 10
        alertTone: true
        active: true
        fontSize: 12
        text: "Delete"
        onClicked: root.runPreset("delete", presetRow.preset.id)
      }
      ActionButton {
        visible: presetRow.confirming
        implicitHeight: 28
        radius: 6
        padding: 10
        kind: "ghost"
        fontSize: 12
        text: "Cancel"
        onClicked: { root.confirmPresetDelete = false; root.presetDeleteId = "" }
      }
    }
  }

  // Card and scrim presence: toward 1 is the entrance (enterMs, easing out),
  // toward 0 / 0.98 the exit (exitMs, easing in). Instant while hidden.
  component Presence: Behavior {
    id: presence
    enabled: win.visible
    NumberAnimation {
      duration: presence.targetValue >= 1 ? root.enterMs : root.exitMs
      easing.type: presence.targetValue >= 1 ? Easing.OutCubic : Easing.InCubic
    }
  }

  component LinkText: UiText {
    id: link
    property string label: ""
    signal clicked()
    text: label
    color: linkMouse.containsMouse ? Theme.accent : Theme.fg
    font.pixelSize: 11
    font.weight: Font.Medium
    font.underline: true
    Behavior on color { ColorAnimation { duration: root.hoverMs; easing.type: Easing.OutCubic } }
    MouseArea { id: linkMouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: link.clicked() }
  }
}
