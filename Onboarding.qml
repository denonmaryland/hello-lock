import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons

// First-run setup for Hello Lock: name, birthday, a logo (a typed wordmark in
// the Omarchy logo's style, an image, or the Omarchy logo), the unlock symbol
// (that logo, the Omarchy symbol or a built-in pixel symbol) and the typing
// effect (what the logo does as the password is typed). Shown by the lock
// service on the first shell start after install, and on demand with
// `omarchy-shell lock onboarding`. Never shown while locked; it does not touch
// authentication. Saves through bin/hello-config.
Item {
  id: root

  // Supplied by Service.qml.
  property string pluginDir: ""
  property string configDir: ""
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string suggestedName: ""
  property var currentConfig: ({})
  // The typing-effect preview honours this (plain fades only). Set by the
  // service when it knows; start() also reads "motion": "reduced" from config.
  property bool reducedMotion: false

  signal closed()
  // "Not now": the service records it (this item is destroyed as soon as it closes).
  signal dismissed()
  signal tryUnlockRequested()

  readonly property int stepCount: 7
  property int step: 0
  property int direction: 1

  // Answers.
  property string name: ""
  property string birthMonth: ""
  property string birthDay: ""
  property string logoChoice: "omarchy"   // "wordmark" | "image" | "omarchy"
  property string wordmarkText: ""
  property string wordmarkStyle: "blocks"
  readonly property var wordmarkStyles: [
    { id: "omarchy", label: "Omarchy" },
    { id: "blocks", label: "Blocks" }, { id: "outline", label: "Outline" },
    { id: "scanline", label: "Scanline" }, { id: "led", label: "LED" },
    { id: "tiles", label: "Tiles" }, { id: "split", label: "Split" },
    { id: "italic", label: "Italic" }, { id: "wide", label: "Wide" },
    { id: "glitch", label: "Glitch" }, { id: "shadow", label: "Shadow" }
  ]
  function cycleStyle(delta) {
    var ids = wordmarkStyles.map(function(s) { return s.id })
    var i = (ids.indexOf(wordmarkStyle) + delta + ids.length) % ids.length
    wordmarkStyle = ids[i]
    renderWordmark()
  }
  // Unlock symbol: "logo" (whatever logo was picked) or a built-in from symbols/.
  property string symbolChoice: "logo"
  // One family of "command console" insignia, in rows; the first row is the
  // logo from step 3 and the Omarchy symbol.
  readonly property var symbolGroups: [
    { label: "YOURS", ids: ["logo", "omarchy"] },
    { label: "SYSTEM", ids: ["power", "prompt", "cursor", "chip", "bolt", "gear", "battery", "core"] },
    { label: "SECURITY", ids: ["shield", "key", "lock", "eye", "crosshair", "scan", "visor", "skull"] },
    { label: "SIGNAL", ids: ["radar", "antenna", "signal", "wifi", "satellite", "waveform", "link", "infinity"] },
    { label: "SPACE", ids: ["planet", "moon", "nova", "sparkle", "rocket", "comet", "ufo", "alien"] },
    { label: "RANK", ids: ["chevrons", "insignia", "medal", "crown", "star", "gem", "delta"] }
  ]
  readonly property var symbolChoices: symbolGroups.reduce(function(all, g) { return all.concat(g.ids) }, [])
  function symbolLabel(id) {
    if (id === "logo") return logoChoice === "wordmark" ? "My name" : "My logo"
    return id.charAt(0).toUpperCase() + id.slice(1)
  }
  function symbolFile(id) { return id === "logo" ? previewLogo : pluginDir ? pluginDir + "/symbols/" + id + ".svg" : "" }
  function cycleSymbol(delta) {
    var i = (symbolChoices.indexOf(symbolChoice) + delta + symbolChoices.length) % symbolChoices.length
    symbolChoice = symbolChoices[i]
  }
  // Up/Down: the same column in the row above or below (clamped to its length).
  function moveSymbolRow(delta) {
    for (var r = 0; r < symbolGroups.length; r++) {
      var c = symbolGroups[r].ids.indexOf(symbolChoice)
      if (c < 0) continue
      var ids = symbolGroups[(r + delta + symbolGroups.length) % symbolGroups.length].ids
      symbolChoice = ids[Math.min(c, ids.length - 1)]
      return
    }
  }
  // Typing effect: one of typing/<name>.qml, "shuffle" or "off" (see typing/README.md).
  property string typingEffect: "cells"
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
  readonly property var typingEffectIds: typingEffects.map(function(e) { return e.id })
  // Effect files actually installed (typing/*.qml); rescanned on the step.
  property var installedEffects: []
  // Shuffle's preview walks through the installed effects, one per loop.
  property int shuffleIndex: 0
  readonly property var shufflePool: typingEffectIds.filter(function(id) {
    return id !== "off" && id !== "shuffle" && installedEffects.indexOf(id) >= 0
  })
  readonly property string previewEffect: typingEffect !== "shuffle" ? typingEffect
    : shufflePool.length ? shufflePool[shuffleIndex % shufflePool.length] : ""
  function effectLabel(id) {
    var i = typingEffectIds.indexOf(id)
    return i >= 0 ? typingEffects[i].label : id
  }
  function cycleEffect(delta) {
    var ids = typingEffectIds
    typingEffect = ids[(ids.indexOf(typingEffect) + delta + ids.length) % ids.length]
  }
  function scanEffects() {
    if (!pluginDir) return
    effectScan.running = false
    effectScan.command = ["find", pluginDir + "/typing", "-maxdepth", "1", "-name", "*.qml", "-printf", "%f\\n"]
    effectScan.running = true
  }

  property int wordmarkVersion: 0
  property bool wordmarkReady: false
  property string wordmarkError: ""
  property string imagePath: ""
  property bool tintImage: true
  property bool picking: false
  property string saveError: ""
  property bool saving: false

  property string wordmarkPreview: ""
  readonly property string omarchyLogo: "/usr/share/omarchy/logo.svg"
  readonly property string previewLogo: logoChoice === "wordmark" ? (wordmarkReady ? wordmarkPreview : "")
    : logoChoice === "image" ? imagePath : omarchyLogo
  readonly property bool previewTinted: logoChoice !== "image" || tintImage
  // The big preview shows the logo on step 3, the unlock symbol on step 4, the
  // logo again (running the typing effect) on step 5 and the symbol at the end.
  readonly property bool symbolOnTop: step === 4 || step === 6
  readonly property string previewTop: symbolOnTop ? symbolFile(symbolChoice) : previewLogo
  readonly property bool previewTopTinted: symbolOnTop && symbolChoice !== "logo" ? true : previewTinted
  readonly property color accent: Commons.Color.accent
  readonly property color text: Commons.Color.lock.text

  function fileUrl(path, version) {
    if (!path) return ""
    if (path.indexOf("data:image/svg+xml,") === 0) return path
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/") + "?v=" + (version || 0)
  }

  function start() {
    var c = currentConfig || {}
    name = (typeof c.name === "string" && c.name.trim()) ? c.name.trim() : suggestedName
    var b = typeof c.birthday === "string" ? c.birthday.split("-") : []
    birthMonth = b.length === 2 ? b[0] : ""
    birthDay = b.length === 2 ? b[1] : ""
    wordmarkText = typeof c.wordmarkText === "string" ? c.wordmarkText : ""
    wordmarkStyle = typeof c.wordmarkStyle === "string" && c.wordmarkStyle ? c.wordmarkStyle : "blocks"
    if (wordmarkText) { logoChoice = "wordmark"; renderWordmark() }
    else if (typeof c.logo === "string" && c.logo) { logoChoice = "image"; imagePath = expand(c.logo) }
    else logoChoice = "omarchy"
    tintImage = c.tintLogo !== false
    var sym = typeof c.symbol === "string" ? c.symbol.replace(/^@/, "") : ""
    symbolChoice = symbolChoices.indexOf(sym) > 0 ? sym : "logo"
    typingEffect = typeof c.typingEffect === "string" && typingEffectIds.indexOf(c.typingEffect) >= 0 ? c.typingEffect : "cells"
    if (c.motion === "reduced") reducedMotion = true
    scanEffects()
    step = 0
  }

  function expand(p) {
    if (p.indexOf("~/") === 0) return Quickshell.env("HOME") + p.slice(1)
    return p.charAt(0) === "/" ? p : configDir + "/" + p
  }

  readonly property bool birthdayValid: {
    if (birthMonth === "" && birthDay === "") return true
    var m = Number(birthMonth), d = Number(birthDay)
    var days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return /^\d{1,2}$/.test(birthMonth) && /^\d{1,2}$/.test(birthDay) && m >= 1 && m <= 12 && d >= 1 && d <= days[m - 1]
  }
  readonly property bool canContinue: step === 1 ? name.trim().length > 0
    : step === 2 ? birthdayValid
    : step === 3 ? (logoChoice !== "wordmark" || wordmarkReady) && (logoChoice !== "image" || imagePath !== "")
    : true

  function next() {
    if (!canContinue || saving) return
    if (step === stepCount - 1) { save(); return }
    direction = 1
    step += 1
  }

  function back() {
    if (saving) return
    if (step === 0) { skip(); return }
    direction = -1
    step -= 1
  }

  function skip() {
    dismissed()
    closed()
  }

  function pad2(v) { v = String(v); return v.length === 1 ? "0" + v : v }

  function save() {
    var update = {
      name: name.trim(),
      birthday: (birthMonth && birthDay) ? pad2(birthMonth) + "-" + pad2(birthDay) : null,
      wordmarkText: logoChoice === "wordmark" ? wordmarkText.trim() : null,
      wordmarkStyle: logoChoice === "wordmark" ? wordmarkStyle : null,
      logo: logoChoice === "wordmark" ? "wordmark.svg" : logoChoice === "image" ? imagePath : null,
      tintLogo: logoChoice === "image" ? tintImage : null,
      // The unlock symbol: a built-in, or none to reuse the logo. Older custom
      // symbol settings are cleared so the choice made here is what plays.
      symbol: symbolChoice === "logo" ? null : "@" + symbolChoice,
      symbolParts: null,
      typingEffect: typingEffect
    }
    saving = true
    saveError = ""
    saveProc.command = ["sh", "-c", '"$0" save "$1" && "$0" done', pluginDir + "/bin/hello-config", JSON.stringify(update)]
    saveProc.running = true
  }

  function renderWordmark() {
    wordmarkReady = false
    var t = wordmarkText.replace(/[^A-Za-z0-9 ]/g, "")
    if (t !== wordmarkText) { wordmarkText = t; return }
    if (t.trim().length === 0) { wordmarkReady = false; wordmarkError = ""; return }
    wordmarkTimer.restart()
  }

  // Up/Down cycle the logo options on step 3, even while typing a wordmark.
  readonly property var logoChoices: ["wordmark", "image", "omarchy"]
  function cycleLogo(delta) {
    var i = (logoChoices.indexOf(logoChoice) + delta + logoChoices.length) % logoChoices.length
    logoChoice = logoChoices[i]
    if (logoChoice === "image" && !imagePath) pickImage()
    focusTimer.restart()
  }

  function pickImage() {
    if (picking) return
    picking = true
    pickProc.running = true
  }

  Timer {
    id: wordmarkTimer
    interval: 220
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
      root.wordmarkVersion += 1
    }
  }

  // The desktop file chooser opens as a normal window, so the setup screen
  // steps aside (picking hides the window) until it returns.
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
        root.saveError = ""
      } else {
        root.saveError = String(importErr.text || "").replace(/^hello-config: /, "").trim() || "Couldn't use that file."
      }
    }
  }

  Process {
    id: effectScan
    stdout: StdioCollector { id: effectScanOut; waitForEnd: true }
    onExited: function(code) {
      root.installedEffects = code === 0
        ? String(effectScanOut.text || "").split("\n").filter(function(f) { return /^[a-z]+\.qml$/.test(f) })
            .map(function(f) { return f.slice(0, -4) })
        : []
    }
  }

  Process {
    id: saveProc
    stderr: StdioCollector { id: saveErr; waitForEnd: true }
    onExited: function(code) {
      root.saving = false
      if (code === 0) {
        root.tryUnlockRequested()
        root.closed()
      } else {
        root.saveError = String(saveErr.text || "").trim() || "Couldn't save your settings."
      }
    }
  }


  PanelWindow {
    id: win
    visible: !root.picking
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hello-lock-onboarding"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
      id: stage
      anchors.fill: parent
      focus: true
      opacity: 0
      Component.onCompleted: opacity = 1
      Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.next(); event.accepted = true }
        else if (root.step === 5 && (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                                     || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
          root.cycleEffect(event.key === Qt.Key_Left || event.key === Qt.Key_Backtab ? -1 : 1); event.accepted = true
        }
        else if (root.step === 4 && (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                                     || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
          root.cycleSymbol(event.key === Qt.Key_Left || event.key === Qt.Key_Backtab ? -1 : 1); event.accepted = true
        }
        else if (root.step === 4 && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
          root.moveSymbolRow(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true
        }
        else if (root.step === 3 && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
          root.cycleLogo(event.key === Qt.Key_Down ? 1 : -1); event.accepted = true
        }
        else if (root.step === 3 && !wordmarkInput.activeFocus) {
          if (event.key === Qt.Key_1) { root.logoChoice = "wordmark"; focusTimer.restart(); event.accepted = true }
          else if (event.key === Qt.Key_2) { root.logoChoice = "image"; if (!root.imagePath) root.pickImage(); event.accepted = true }
          else if (event.key === Qt.Key_3) { root.logoChoice = "omarchy"; event.accepted = true }
        }
      }

      Rectangle { anchors.fill: parent; color: Commons.Color.background }

      Image {
        id: wallpaper
        anchors.fill: parent
        source: root.fileUrl(root.backgroundPath, root.backgroundVersion)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: width
        sourceSize.height: height
        visible: false
      }

      MultiEffect {
        anchors.fill: wallpaper
        source: wallpaper
        autoPaddingEnabled: false
        visible: wallpaper.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 128
        blurMultiplier: 1.25
        contrast: -0.08
      }

      Rectangle { anchors.fill: parent; color: Commons.Color.background; opacity: 0.62 }

      // Logo preview: the chosen logo as it will look on the lock screen.
      Item {
        id: logoPreview
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * (root.symbolOnTop ? 0.05 : 0.12)
        width: parent.width * 0.42
        height: parent.height * (root.symbolOnTop ? 0.15 : 0.17)
        opacity: root.step >= 3 && root.previewTop ? 1 : 0
        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Image {
          id: previewImage
          anchors.fill: parent
          source: root.previewTop ? root.fileUrl(root.previewTop, root.wordmarkVersion) : ""
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(width * 1.5)
          cache: false
          visible: false
          layer.enabled: true
        }

        Item {
          id: previewSilhouette
          anchors.fill: parent
          visible: false
          layer.enabled: true
          MultiEffect { anchors.fill: parent; source: previewImage; brightness: root.previewTopTinted ? 1 : 0 }
        }

        // The logo at full brightness and final colour, handed to the typing
        // effect as its source (typing/README.md). Only rendered on step 5.
        Item {
          id: previewFull
          anchors.fill: parent
          visible: false
          layer.enabled: typingDemo.active
          MultiEffect {
            anchors.fill: parent
            source: previewSilhouette
            autoPaddingEnabled: false
            colorization: root.previewTopTinted ? 1 : 0
            colorizationColor: root.text
          }
        }

        // The silhouette in an explicitly padded texture, so the shadow and
        // glow have room without a MultiEffect auto-padding a layered source
        // (that stretches it, and would no longer line up with the typing
        // effect drawn on top). Same approach as LockView.
        ShaderEffectSource {
          id: previewPadded
          readonly property real pad: Math.round(logoPreview.height * 0.3)
          x: -pad; y: -pad
          width: parent.width + pad * 2
          height: parent.height + pad * 2
          sourceItem: previewSilhouette
          sourceRect: Qt.rect(-pad, -pad, width, height)
          visible: false
        }

        // Host glow behind the logo; the effect drives it with its charge.
        MultiEffect {
          anchors.fill: previewPadded
          source: previewPadded
          autoPaddingEnabled: false
          visible: typingDemo.active && previewImage.status === Image.Ready
          opacity: typingFx.item ? typingFx.item.glowLevel * 0.9 : 0
          blurEnabled: true; blur: 1; blurMax: 48
          colorization: 1; colorizationColor: root.accent
        }

        // The plain logo; on step 5 drawn at the effect's base opacity.
        MultiEffect {
          anchors.fill: previewPadded
          source: previewPadded
          autoPaddingEnabled: false
          visible: previewImage.status === Image.Ready
          opacity: typingDemo.active && typingFx.item ? typingFx.item.baseOpacity : 1
          colorization: root.previewTopTinted ? 1 : 0
          colorizationColor: root.text
          shadowEnabled: true
          shadowColor: root.accent
          shadowOpacity: 0.35
          shadowBlur: 1
        }

        // Step 5: the chosen typing effect on a loop of pretend keystrokes. A
        // missing or broken effect file just leaves the plain logo above.
        Loader {
          id: typingFx
          anchors.fill: parent
          active: typingDemo.active && root.installedEffects.indexOf(root.previewEffect) >= 0
          source: active ? "file://" + root.pluginDir + "/typing/" + root.previewEffect + ".qml" : ""
          onLoaded: {
            item.source = previewFull
            item.inkRect = Qt.binding(function() {
              return Qt.rect((previewImage.width - previewImage.paintedWidth) / 2, (previewImage.height - previewImage.paintedHeight) / 2,
                             previewImage.paintedWidth, previewImage.paintedHeight)
            })
            item.level = Qt.binding(function() { return typingDemo.holding ? 1 : Math.min(typingDemo.typed, 12) / 12 })
            item.typedLength = Qt.binding(function() { return typingDemo.typed })
            item.holding = Qt.binding(function() { return typingDemo.holding })
            item.reducedMotion = Qt.binding(function() { return root.reducedMotion })
            item.accent = Qt.binding(function() { return root.accent })
            item.logoColor = Qt.binding(function() { return root.text })
            item.errorColor = Qt.binding(function() { return Commons.Color.urgent })
            item.reset()
            typingDemo.restart()
          }
          onStatusChanged: if (status === Loader.Error) typingDemo.restart()
        }
      }

      // Pretend password dots under the step 5 preview, so the loop reads as
      // typing. Accent while checking; on a failure they turn red and fade out.
      Row {
        id: demoDots
        anchors.horizontalCenter: logoPreview.horizontalCenter
        y: logoPreview.y + logoPreview.height + parent.height * 0.026
        spacing: 8
        readonly property int shown: typingDemo.failed ? 12 : typingDemo.holding ? 12 : typingDemo.typed
        readonly property color dotColor: typingDemo.failed ? Commons.Color.urgent
          : typingDemo.holding ? root.accent : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.7)
        opacity: typingDemo.active && (typingDemo.typed > 0 || typingDemo.holding) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: typingDemo.failed ? 700 : 160; easing.type: Easing.OutCubic } }
        // The wrong-password shake, as the lock's field does it (not with reduced motion).
        property real shakeX: 0
        transform: Translate { x: demoDots.shakeX }
        SequentialAnimation {
          id: previewShake
          NumberAnimation { target: demoDots; property: "shakeX"; to: -10; duration: 50; easing.type: Easing.OutQuad }
          NumberAnimation { target: demoDots; property: "shakeX"; to: 8; duration: 70; easing.type: Easing.InOutQuad }
          NumberAnimation { target: demoDots; property: "shakeX"; to: -5; duration: 60; easing.type: Easing.InOutQuad }
          NumberAnimation { target: demoDots; property: "shakeX"; to: 2; duration: 50; easing.type: Easing.InOutQuad }
          NumberAnimation { target: demoDots; property: "shakeX"; to: 0; duration: 40; easing.type: Easing.OutQuad }
        }
        Repeater {
          model: 12
          Rectangle {
            required property int index
            width: 6; height: 6; radius: 3
            color: demoDots.dotColor
            opacity: index < demoDots.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 90 } }
            Behavior on color { ColorAnimation { duration: 160 } }
          }
        }
      }

      // Drives the step 5 preview: type 12 (~150 ms apart), hold, submit, wait,
      // fail, rest, repeat. Shuffle moves to the next effect each loop.
      QtObject {
        id: typingDemo
        readonly property bool active: root.step === 5 && win.visible
        property int typed: 0
        property bool holding: false
        property bool failed: false
        property int step: 0
        // [delay ms, action]
        readonly property var script: [
          [450, "t"], [150, "t"], [150, "t"], [150, "t"], [150, "t"], [150, "t"],
          [150, "t"], [150, "t"], [150, "t"], [150, "t"], [150, "t"], [150, "t"],
          [650, "submit"], [900, "fail"], [1500, "loop"]
        ]
        onActiveChanged: { if (active) root.scanEffects(); restart() }
        function restart() {
          typed = 0; holding = false; failed = false; step = 0
          demoTick.stop()
          if (active) demoTick.start()
        }
        function run(action) {
          var e = typingFx.item
          if (action === "t") { failed = false; typed += 1; if (e) e.keystroke(typed, 1) }
          else if (action === "submit") { holding = true; if (e) e.submit() }
          else if (action === "fail") {
            // The effect's fail() runs before the host drops level to 0.
            if (e) e.fail()
            failed = true; holding = false; typed = 0
            if (!root.reducedMotion) previewShake.restart()
          }
          else if (action === "loop") {
            failed = false
            if (root.typingEffect === "shuffle" && root.shufflePool.length > 1) { root.shuffleIndex += 1; return false }
          }
          return true
        }
      }
      Timer {
        id: demoTick
        interval: typingDemo.script[typingDemo.step][0]
        onTriggered: {
          var more = typingDemo.run(typingDemo.script[typingDemo.step][1])
          // Shuffle swaps the effect; its onLoaded restarts the script.
          if (!more) return
          typingDemo.step = (typingDemo.step + 1) % typingDemo.script.length
          start()
        }
      }

      // Step content: slides and fades on every step change.
      Item {
        id: page
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.6, 720)
        y: parent.height * (root.step === 4 ? 0.23 : root.step >= 3 ? 0.36 : 0.30)
        height: parent.height * 0.5
        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

        property real shift: 0
        transform: Translate { x: page.shift }
        Connections {
          target: root
          function onStepChanged() { stepAnim.restart(); focusTimer.restart() }
        }
        SequentialAnimation {
          id: stepAnim
          ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 0; duration: 110 }
            NumberAnimation { target: page; property: "shift"; to: -root.direction * 26; duration: 110 }
          }
          ScriptAction { script: { content.shownStep = root.step; page.shift = root.direction * 26 } }
          ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: page; property: "shift"; to: 0; duration: 380; easing.type: Easing.OutCubic }
          }
        }
        Timer {
          id: focusTimer
          interval: 130
          onTriggered: {
            if (content.shownStep === 1) nameInput.forceActiveFocus()
            else if (content.shownStep === 2) monthInput.forceActiveFocus()
            else if (content.shownStep === 3 && root.logoChoice === "wordmark") wordmarkInput.forceActiveFocus()
            else stage.forceActiveFocus()
          }
        }

        Column {
          id: content
          property int shownStep: 0
          width: parent.width
          spacing: Math.round(win.height * 0.022)

          Text {
            id: statusLine
            anchors.horizontalCenter: parent.horizontalCenter
            text: ["HELLO LOCK", "STEP 1 / 5 · NAME", "STEP 2 / 5 · BIRTHDAY", "STEP 3 / 5 · LOGO", "STEP 4 / 5 · UNLOCK SYMBOL",
                   "STEP 5 / 5 · TYPING", "ALL SET"][content.shownStep]
            readonly property int size: Math.max(12, Math.round(win.height * 0.014))
            color: root.accent
            font.family: "Share Tech Mono"
            font.pixelSize: size
            font.letterSpacing: size * 0.35
            leftPadding: size * 0.35
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: [
              "Hello.",
              "What should I call you?",
              "When's your birthday?",
              "Pick your logo",
              "Pick your unlock symbol",
              "How should it react as you type?",
              "Nice to meet you, " + (root.name.trim() || "friend") + "."
            ][content.shownStep]
            color: root.text
            font.family: "Oxanium"
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(win.height * (content.shownStep === 0 ? 0.075 : 0.042))
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: [
              "Let's make your lock screen yours. It takes about thirty seconds.",
              "Your name appears in the greetings when you unlock.",
              "Optional. On the day, your unlock says happy birthday.",
              root.logoChoice === "wordmark" ? (root.wordmarkStyle === "omarchy" ? "The Omarchy logo's own font by CoSMiC cHiLD. Letters only." : "Type a word and pick a style. Letters and numbers.") + " Tab changes style, ↑ ↓ switch options."
                : root.logoChoice === "image" ? "An SVG or PNG with a transparent background works best."
                : "Keep the Omarchy logo. You can change it later.",
              "It plays when you unlock: your logo, the Omarchy symbol or a console insignia.",
              root.typingEffects[Math.max(0, root.typingEffectIds.indexOf(root.typingEffect))].hint,
              "Lock with Super + Ctrl + L to see it. Run  omarchy-shell lock onboarding  to change anything later."
            ][content.shownStep]
            color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.7)
            font.family: "Oxanium"
            font.pixelSize: Math.round(win.height * 0.017)
          }

          Item { width: 1; height: Math.round(win.height * 0.012) }

          // Step 1: name.
          PillField {
            visible: content.shownStep === 1
            anchors.horizontalCenter: parent.horizontalCenter
            TextInput {
              id: nameInput
              anchors.fill: parent
              anchors.leftMargin: 20; anchors.rightMargin: 20
              verticalAlignment: TextInput.AlignVCenter
              horizontalAlignment: TextInput.AlignHCenter
              text: root.name
              maximumLength: 40
              color: root.text
              selectionColor: root.accent
              font.family: "Oxanium"
              font.pixelSize: Math.round(win.height * 0.022)
              onTextEdited: root.name = text
              Keys.onReturnPressed: root.next()
              Keys.onEnterPressed: root.next()
              Keys.onEscapePressed: root.back()
            }
          }

          // Step 2: birthday (MM / DD).
          Row {
            visible: content.shownStep === 2
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14
            PillField {
              width: 110
              TextInput {
                id: monthInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                text: root.birthMonth
                maximumLength: 2
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
                color: root.text
                font.family: "Share Tech Mono"
                font.pixelSize: Math.round(win.height * 0.024)
                onTextEdited: { root.birthMonth = text; if (text.length === 2) dayInput.forceActiveFocus() }
                Keys.onReturnPressed: root.next()
                Keys.onEnterPressed: root.next()
                Keys.onEscapePressed: root.back()
                Text { anchors.centerIn: parent; visible: !parent.text; text: "MM"; color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.3); font: parent.font }
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "/"
              color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.5)
              font.family: "Share Tech Mono"
              font.pixelSize: Math.round(win.height * 0.024)
            }
            PillField {
              width: 110
              TextInput {
                id: dayInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                text: root.birthDay
                maximumLength: 2
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator { regularExpression: /\d{0,2}/ }
                color: root.text
                font.family: "Share Tech Mono"
                font.pixelSize: Math.round(win.height * 0.024)
                onTextEdited: root.birthDay = text
                Keys.onReturnPressed: root.next()
                Keys.onEnterPressed: root.next()
                Keys.onEscapePressed: root.back()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Backspace && text.length === 0) { monthInput.forceActiveFocus(); event.accepted = true }
                }
                Text { anchors.centerIn: parent; visible: !parent.text; text: "DD"; color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.3); font: parent.font }
              }
            }
          }

          // Step 3: logo choice.
          Row {
            visible: content.shownStep === 3
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
              model: [
                { id: "wordmark", label: "Type it", key: "1" },
                { id: "image", label: "Use an image", key: "2" },
                { id: "omarchy", label: "Omarchy logo", key: "3" }
              ]
              ChoiceChip {
                required property var modelData
                label: modelData.label
                hint: modelData.key
                selected: root.logoChoice === modelData.id
                onClicked: {
                  root.logoChoice = modelData.id
                  if (modelData.id === "wordmark") focusTimer.restart()
                  if (modelData.id === "image" && !root.imagePath) root.pickImage()
                }
              }
            }
          }

          PillField {
            visible: content.shownStep === 3 && root.logoChoice === "wordmark"
            anchors.horizontalCenter: parent.horizontalCenter
            TextInput {
              id: wordmarkInput
              anchors.fill: parent
              anchors.leftMargin: 20; anchors.rightMargin: 20
              verticalAlignment: TextInput.AlignVCenter
              horizontalAlignment: TextInput.AlignHCenter
              text: root.wordmarkText
              maximumLength: 20
              color: root.text
              font.family: "Oxanium"
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 2
              font.pixelSize: Math.round(win.height * 0.022)
              onTextEdited: { root.wordmarkText = text; root.renderWordmark() }
              Keys.onReturnPressed: root.next()
              Keys.onEnterPressed: root.next()
              Keys.onEscapePressed: { stage.forceActiveFocus(); root.back() }
              Keys.onUpPressed: root.cycleLogo(-1)
              Keys.onDownPressed: root.cycleLogo(1)
              Keys.onTabPressed: root.cycleStyle(1)
              Keys.onBacktabPressed: root.cycleStyle(-1)
              Text { anchors.centerIn: parent; visible: !parent.text; text: "YOUR NAME OR BRAND"; color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.3); font: parent.font }
            }
          }

          // Wordmark styles: two rows (the original Omarchy font first), live preview above.
          Grid {
            visible: content.shownStep === 3 && root.logoChoice === "wordmark"
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 6
            spacing: 8
            Repeater {
              model: root.wordmarkStyles
              ChoiceChip {
                required property var modelData
                label: modelData.label
                small: true
                selected: root.wordmarkStyle === modelData.id
                onClicked: { root.wordmarkStyle = modelData.id; root.renderWordmark(); focusTimer.restart() }
              }
            }
          }

          // Step 4: unlock symbols, one labeled row per family. The selected
          // (or hovered) symbol's name shows underneath.
          Column {
            id: symbolGrid
            visible: content.shownStep === 4
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -labelWidth / 2
            spacing: 7
            property string hovered: ""
            readonly property real labelWidth: Math.round(win.height * 0.075)
            Repeater {
              model: root.symbolGroups
              Row {
                id: groupRow
                required property var modelData
                spacing: 7
                Text {
                  width: symbolGrid.labelWidth
                  anchors.verticalCenter: parent.verticalCenter
                  rightPadding: 10
                  horizontalAlignment: Text.AlignRight
                  text: groupRow.modelData.label
                  color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.45)
                  font.family: "Share Tech Mono"
                  font.pixelSize: Math.max(10, Math.round(win.height * 0.0105))
                  font.letterSpacing: 1.5
                }
                Repeater {
                  model: groupRow.modelData.ids
                  SymbolTile {
                    required property string modelData
                    source: root.symbolFile(modelData)
                    tinted: modelData !== "logo" || root.previewTinted
                    selected: root.symbolChoice === modelData
                    onClicked: root.symbolChoice = modelData
                    onHoveredChanged: symbolGrid.hovered = hovered ? modelData : (symbolGrid.hovered === modelData ? "" : symbolGrid.hovered)
                  }
                }
              }
            }
          }

          // Step 5: typing effects.
          Row {
            visible: content.shownStep === 5
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
              model: root.typingEffects
              ChoiceChip {
                required property var modelData
                label: modelData.label
                small: true
                selected: root.typingEffect === modelData.id
                onClicked: root.typingEffect = modelData.id
              }
            }
          }

          // Shuffle names the effect its preview is showing right now.
          Text {
            visible: content.shownStep === 5
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.typingEffect === "shuffle" && root.previewEffect ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            text: "NOW SHOWING · " + root.effectLabel(root.previewEffect).toUpperCase()
            readonly property int size: Math.max(12, Math.round(win.height * 0.014))
            color: root.accent
            font.family: "Share Tech Mono"
            font.pixelSize: size
            font.letterSpacing: size * 0.35
            leftPadding: size * 0.35
          }

          Text {
            visible: content.shownStep === 4
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.symbolLabel(symbolGrid.hovered || root.symbolChoice).toUpperCase()
            readonly property int size: Math.max(12, Math.round(win.height * 0.014))
            color: root.accent
            font.family: "Share Tech Mono"
            font.pixelSize: size
            font.letterSpacing: size * 0.35
            leftPadding: size * 0.35
          }

          Row {
            visible: content.shownStep === 3 && root.logoChoice === "image"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18
            TextButton { label: root.imagePath ? "Choose a different file" : "Choose a file"; onClicked: root.pickImage() }
            TextButton {
              label: (root.tintImage ? "◉" : "○") + "  Match my theme colors"
              onClicked: root.tintImage = !root.tintImage
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text.length > 0
            text: content.shownStep === 3 && root.logoChoice === "wordmark" ? root.wordmarkError
              : content.shownStep === 2 && !root.birthdayValid ? "That date doesn't exist." : root.saveError
            color: Commons.Color.urgent
            font.family: "Share Tech Mono"
            font.pixelSize: Math.max(12, Math.round(win.height * 0.013))
          }

          Item { width: 1; height: Math.round(win.height * 0.01) }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            TextButton {
              label: content.shownStep === 0 ? "Not now" : content.shownStep === 2 ? "Skip" : "Back"
              onClicked: {
                if (content.shownStep === 2) { root.birthMonth = ""; root.birthDay = ""; root.next() }
                else root.back()
              }
            }
            PrimaryButton {
              label: content.shownStep === 0 ? "Let's go" : content.shownStep === 6 ? (root.saving ? "Saving…" : "Save and try it") : "Continue"
              enabled: root.canContinue && !root.saving
              onClicked: root.next()
            }
          }
        }
      }

      // Progress dots.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.08
        spacing: 10
        Repeater {
          model: root.stepCount
          Rectangle {
            required property int index
            width: index === root.step ? 22 : 7
            height: 7
            radius: 3.5
            color: index <= root.step ? root.accent : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.25)
            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 260 } }
          }
        }
      }
    }
  }

  // ---- Small themed controls.

  component PillField: Rectangle {
    width: Math.min(420, win.width * 0.5)
    height: Math.round(win.height * 0.052)
    radius: height / 2
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.55)
    border.width: 1
    border.color: {
      var focused = false
      for (var i = 0; i < children.length; i++) if (children[i].activeFocus) focused = true
      return focused ? root.accent : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.22)
    }
  }

  component ChoiceChip: Rectangle {
    id: chip
    property string label: ""
    property string hint: ""
    property bool selected: false
    property bool small: false
    signal clicked()
    width: small ? Math.max(chipText.implicitWidth + 28, win.height * 0.085) : chipText.implicitWidth + 44
    height: Math.round(win.height * (small ? 0.036 : 0.046))
    radius: height / 2
    color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                    : chipMouse.containsMouse ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.08) : "transparent"
    border.width: 1
    border.color: selected ? root.accent : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.22)
    Behavior on color { ColorAnimation { duration: 160 } }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: root.text
      font.family: "Oxanium"
      font.weight: chip.selected ? Font.DemiBold : Font.Normal
      font.pixelSize: Math.round(win.height * (chip.small ? 0.014 : 0.016))
    }
    MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
  }

  component SymbolTile: Rectangle {
    id: tile
    property string source: ""
    property bool tinted: true
    property bool selected: false
    readonly property bool hovered: tileMouse.containsMouse
    signal clicked()
    width: Math.round(win.height * 0.05)
    height: width
    radius: 9
    color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                    : tileMouse.containsMouse ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.08) : "transparent"
    border.width: 1
    border.color: selected ? root.accent : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.16)
    scale: tileMouse.pressed ? 0.95 : 1
    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Image {
      id: tileImage
      x: tile.width * 0.08; y: x
      width: tile.width * 0.84; height: width
      source: tile.source ? root.fileUrl(tile.source, root.wordmarkVersion) : ""
      fillMode: Image.PreserveAspectFit
      sourceSize.width: 96
      cache: false
      visible: false
    }
    MultiEffect {
      anchors.fill: tileImage
      source: tileImage
      visible: tileImage.status === Image.Ready
      brightness: tile.tinted ? 1 : 0
      colorization: tile.tinted ? 1 : 0
      colorizationColor: tile.selected ? root.accent : root.text
    }
    MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
  }

  component PrimaryButton: Rectangle {
    id: btn
    property string label: ""
    signal clicked()
    width: btnText.implicitWidth + 56
    height: Math.round(win.height * 0.05)
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: btnMouse.pressed ? Qt.darker(root.accent, 1.15) : root.accent
    scale: btnMouse.containsMouse && enabled ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      // Dark text on light accents, light text on dark ones.
      color: (0.299 * root.accent.r + 0.587 * root.accent.g + 0.114 * root.accent.b) > 0.6 ? "#111111" : "#ffffff"
      font.family: "Oxanium"
      font.weight: Font.DemiBold
      font.pixelSize: Math.round(win.height * 0.017)
    }
    MouseArea { id: btnMouse; anchors.fill: parent; enabled: btn.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
  }

  component TextButton: Text {
    id: tb
    property string label: ""
    signal clicked()
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    text: label
    color: Qt.rgba(root.text.r, root.text.g, root.text.b, tbMouse.containsMouse ? 0.95 : 0.6)
    font.family: "Oxanium"
    font.pixelSize: Math.round(win.height * 0.016)
    MouseArea { id: tbMouse; anchors.fill: parent; anchors.margins: -10; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
  }
}
