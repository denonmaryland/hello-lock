import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons

// Hello Lock power-on splash shown after a successful unlock. Purely visual: the
// lock service unlocks on its own; this only covers the desktop for ~3.5s.
// prime() maps an opaque theme-colored stage while the session is still
// locked, so releasing the lock reveals the stage instead of the desktop.
// play() picks one of eleven symbol animations and a greeting (shuffle bags, so
// neither repeats until all have played), then fades out. Any key or click skips.
// A rare gold "legendary" sequence (index 11) can replace the bag pick, quick
// unlocks get a ~1.1s short pop, and a telemetry line shows live status.
// Reduced motion swaps every animation for a calm fade. With several monitors
// only the focused one plays the full animation; the others crossfade quietly.
//
// play(forcedVariant, context)
//   forcedVariant: -1/undefined = random, 0-10 = that variant, 11 = legendary
//   context (all optional): { awaySeconds, forceShort, forceGreeting: "away"|"special"|"",
//     status: { battery, charging, temp, condition, updates, special: {status, text} },
//     preview-only, this play alone: symbol: built-in name, motion: "reduced"|"full",
//     secondary: true (every screen plays the unfocused-monitor version) }
Item {
  id: root

  property bool shown: false
  property bool playing: false
  property int primeToken: 0
  property int playToken: 0
  property int skipToken: 0
  property int variant: 0
  property bool shortMode: false
  property string statusLine: ""
  property string greetingLine: ""
  property string telemetryLine: ""
  property bool titleCard: false
  // Sound for the current play (unlock-<variant>, unlock-legendary, unlock-short).
  property string lastSound: ""
  signal soundRequested(string name)
  // Current wallpaper, supplied by the lock service. Loaded fresh on every
  // lock (preload) so it is ready the moment the session is released, and
  // unloaded after the splash; theme switches replace the file underneath.
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool preload: false
  // Must match LockView's unlockStageDim so the handoff frame is identical.
  readonly property real stageDim: 0.5

  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }
  // Set by the lock service from ~/.config/hello-lock/config.json.
  property string userName: "friend"
  // Optional word for the first status line (e.g. "ADA ONLINE"); empty = "SYSTEM".
  property string brand: ""
  // One image (the whole symbol) or two (outer + inner part, animated separately).
  property var symbolPaths: []
  property bool tintSymbol: true
  property bool legendaryEnabled: true
  // Built-in symbol name ("radar") or "" for image symbols; grids in
  // pluginDir/symbols/grids.json. reducedMotion: see Service.qml.
  property string symbolName: ""
  property string pluginDir: ""
  property bool reducedMotion: false
  function pathUrl(path) {
    return path ? "file://" + String(path).split("/").map(encodeURIComponent).join("/") : ""
  }
  // Preview IPC: a built-in symbol for one play only (cleared by finish()).
  property string symbolOverride: ""
  readonly property string activeSymbolName: symbolOverride || symbolName
  readonly property string outerSource: symbolOverride ? pathUrl(pluginDir + "/symbols/" + symbolOverride + ".svg")
    : pathUrl(symbolPaths && symbolPaths.length > 0 ? symbolPaths[0] : "")
  readonly property string innerSource: symbolOverride ? ""
    : pathUrl(symbolPaths && symbolPaths.length > 1 ? symbolPaths[1] : "")

  // Shuffle-bag variants; the legendary one sits after them and is never bagged.
  readonly property int variantCount: 11
  readonly property int legendaryVariant: 11
  readonly property int pixelsVariant: 10
  readonly property real legendaryChance: 0.02
  readonly property var variantNames: ["coin", "assemble", "scan", "glitch", "heartbeat", "orbit", "monolith", "particles", "warp", "split", "pixels", "legendary"]
  // When each animation's symbol has settled and the greeting may begin (ms).
  readonly property var textDelays: [1250, 1000, 1150, 1000, 900, 1150, 1050, 1250, 950, 1000, 1200, 2450]
  // Reduced motion: greeting delay of the calm fade.
  readonly property int calmTextDelay: 700

  // Per play: calm fade instead of the animation; preview override for the
  // unfocused-monitor version; the stage fades in only when not primed.
  property bool calm: false
  property bool forceSecondary: false
  property bool stageFadeIn: false
  property string focusedScreen: ""

  // The focused monitor plays the full animation. If Hyprland names none of
  // our screens, the first screen does, so exactly one always plays it.
  function isPrimaryScreen(screen) {
    if (forceSecondary) return false
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (screens[i] && screens[i].name === focusedScreen) return screen === screens[i]
    return screens.length === 0 || screen === screens[0]
  }

  // --- Pixel grid for the "pixels" animation -------------------------------
  // Cells are fractions of the symbol box (the square the symbol image fills):
  // { x, y, w, h, c: colour or "" } plus flight constants added by decorate().
  // Built-ins come from symbols/grids.json; image symbols are sampled at
  // runtime by a Canvas in the splash window (sampledKey / sampledCells).
  property var grids: ({})
  property real gridInk: 0.77
  property string sampledKey: ""
  property var sampledCells: []
  readonly property string imageKey: outerSource + "|" + innerSource
  readonly property var pixelCells: activeSymbolName
    ? decorate(builtinCells(grids[activeSymbolName]))
    : (sampledKey === imageKey ? sampledCells : [])

  function knowsSymbol(name) { return !!grids[name] }

  FileView {
    path: root.pluginDir ? root.pluginDir + "/symbols/grids.json" : ""
    printErrors: false
    onLoaded: {
      try {
        var g = JSON.parse(String(text() || "{}"))
        root.gridInk = Number(g.ink) || 0.77
        root.grids = g.symbols || {}
      } catch (e) { console.warn("hello-lock splash: bad grids.json: " + e) }
    }
  }

  // Grid rows -> cells, placed the way build.py draws the SVG: ink centred,
  // its longer side spanning gridInk. Tall cells (omarchy, ~4:1) are merged
  // along each run into roughly square pieces to keep the item count low.
  function builtinCells(g) {
    if (!g || !g.rows || g.rows.length === 0) return []
    var rows = g.rows, a = Number(g.cellAspect) || 1, cols = 0
    for (var i = 0; i < rows.length; i++) cols = Math.max(cols, rows[i].length)
    var w = gridInk / Math.max(cols, rows.length * a), h = w * a
    var ox = 0.5 - cols * w / 2, oy = 0.5 - rows.length * h / 2
    var merge = Math.max(1, Math.round(a))
    var cells = []
    for (var r = 0; r < rows.length; r++) {
      var c = 0
      while (c < rows[r].length) {
        if (rows[r].charAt(c) !== "#") { c++; continue }
        var n = 0
        while (c + n < rows[r].length && rows[r].charAt(c + n) === "#" && n < merge) n++
        cells.push({ x: ox + c * w, y: oy + r * h, w: n * w, h: h, c: "" })
        c += n
      }
    }
    return cells
  }

  // Alpha (and colour) of an aspect-fit drawing -> square cells, ~28 across
  // the ink's longer side (more for wide wordmarks, so they keep ~12 rows).
  function sampleCells(data, size) {
    var px = data.data, stride = data.width, minX = size, minY = size, maxX = -1, maxY = -1
    for (var y = 0; y < size; y++)
      for (var x = 0; x < size; x++)
        if (px[(y * stride + x) * 4 + 3] > 40) {
          if (x < minX) minX = x; if (x > maxX) maxX = x
          if (y < minY) minY = y; if (y > maxY) maxY = y
        }
    if (maxX < 0) return []
    var bw = maxX - minX + 1, bh = maxY - minY + 1
    var across = Math.max(28, Math.min(44, Math.round(12 * Math.max(bw, bh) / Math.min(bw, bh))))
    var cs = Math.max(bw, bh) / across
    var nx = Math.max(1, Math.round(bw / cs)), ny = Math.max(1, Math.round(bh / cs))
    var gx = minX + bw / 2 - nx * cs / 2, gy = minY + bh / 2 - ny * cs / 2
    var cells = []
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        var x0 = Math.max(0, Math.floor(gx + i * cs)), x1 = Math.min(size, Math.ceil(gx + (i + 1) * cs))
        var y0 = Math.max(0, Math.floor(gy + j * cs)), y1 = Math.min(size, Math.ceil(gy + (j + 1) * cs))
        var sa = 0, sr = 0, sg = 0, sb = 0, count = 0
        for (var yy = y0; yy < y1; yy++) {
          for (var xx = x0; xx < x1; xx++) {
            var k = (yy * stride + xx) * 4, al = px[k + 3]
            sa += al; sr += px[k] * al; sg += px[k + 1] * al; sb += px[k + 2] * al; count++
          }
        }
        if (count === 0 || sa / count < 0.42 * 255) continue
        cells.push({ x: (gx + i * cs) / size, y: (gy + j * cs) / size, w: cs / size, h: cs / size,
                     c: Qt.rgba(sr / sa / 255, sg / sa / 255, sb / sa / 255, 1).toString() })
      }
    }
    return cells
  }

  function setSampled(key, cells) {
    sampledCells = decorate(cells)
    sampledKey = key
  }

  // Flight constants per cell. d: start in the cascade (0-0.55 of pixelT),
  // top row first and each row from its centre outward; sx/sy: start offset
  // (symbol sizes) out past the symbol along the cell's own direction; r: spin.
  function decorate(cells) {
    if (cells.length === 0) return cells
    var keys = [], lo = 1e9, hi = -1e9
    for (var i = 0; i < cells.length; i++) {
      var cx = cells[i].x + cells[i].w / 2, cy = cells[i].y + cells[i].h / 2
      var k = cy * 0.85 + Math.abs(cx - 0.5) * 0.32 + hash(i, 1) * 0.05
      keys.push(k); lo = Math.min(lo, k); hi = Math.max(hi, k)
    }
    var out = []
    for (var j = 0; j < cells.length; j++) {
      var c = cells[j]
      var dx = c.x + c.w / 2 - 0.5, dy = c.y + c.h / 2 - 0.5
      var base = (Math.abs(dx) + Math.abs(dy) > 0.02) ? Math.atan2(dy, dx) : hash(j, 2) * Math.PI * 2
      var angle = base + (hash(j, 3) - 0.5) * 1.3
      var dist = 0.75 + hash(j, 4) * 0.9
      out.push({ x: c.x, y: c.y, w: c.w, h: c.h, c: c.c,
                 d: hi > lo ? (keys[j] - lo) / (hi - lo) * 0.55 : 0,
                 sx: Math.cos(angle) * dist, sy: Math.sin(angle) * dist,
                 r: (hash(j, 5) < 0.5 ? -1 : 1) * (90 + hash(j, 6) * 120) })
    }
    return out
  }

  function hash(i, k) {
    var x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return x - Math.floor(x)
  }
  // Quick-unlock short mode is disabled (0): the user wants a full, different
  // animation on every unlock. Set to N seconds to re-enable for unlocks < N s.
  readonly property int shortAwayLimit: 0
  readonly property int awayGreetingMin: 900

  // {name} is the user's name, {NAME} upper-cased, {tod} morning/afternoon/evening.
  readonly property var greetings: [
    { status: "{BRAND} ONLINE", text: "Hello, {name}." },
    { status: "IDENTITY CONFIRMED", text: "Welcome back, {name}." },
    { status: "ALL SYSTEMS NOMINAL", text: "Good {tod}, {name}." },
    { status: "NEURAL LINK ESTABLISHED", text: "Ready when you are, {name}." },
    { status: "ACCESS GRANTED", text: "The bridge is yours, {name}." },
    { status: "COMMAND AUTHORITY VERIFIED", text: "Welcome aboard, {name}." },
    { status: "CORE ONLINE", text: "Standing by, {name}." },
    { status: "UPLINK SECURED", text: "Welcome home, {name}." },
    { status: "LINK STABLE", text: "Right where you left off, {name}." },
    { status: "SIGNAL LOCKED", text: "Back online, {name}." },
    { status: "SYSTEM READY", text: "{name}." },
    { status: "WELCOME", text: "{NAME}", title: true }
  ]
  readonly property var nightGreeting: ({ status: "NIGHT OPERATIONS", text: "Still at it, {name}?" })

  function fill(template) {
    var name = String(userName || "friend")
    var brandWord = String(brand || "").trim().toUpperCase() || "SYSTEM"
    return String(template).replace(/\{tod\}/g, timeOfDay()).replace(/\{NAME\}/g, name.toUpperCase())
      .replace(/\{name\}/g, name).replace(/\{BRAND\}/g, brandWord)
  }

  property var variantBag: []
  property var greetingBag: []
  property int lastVariant: -1
  property int lastGreeting: -1

  function shuffled(count, avoidFirst) {
    var bag = []
    for (var i = 0; i < count; i++) bag.push(i)
    for (var j = count - 1; j > 0; j--) {
      var k = Math.floor(Math.random() * (j + 1))
      var t = bag[j]; bag[j] = bag[k]; bag[k] = t
    }
    // Never start a new round with the item that ended the last one.
    if (count > 1 && bag[0] === avoidFirst) { bag[0] = bag[1]; bag[1] = avoidFirst }
    return bag
  }

  function timeOfDay() {
    var h = new Date().getHours()
    if (h >= 5 && h < 12) return "morning"
    if (h >= 12 && h < 17) return "afternoon"
    return "evening"
  }

  function pickVariant() {
    if (variantBag.length === 0) variantBag = shuffled(variantCount, lastVariant)
    lastVariant = variantBag.shift()
    return lastVariant
  }

  function finiteNumber(value) {
    if (value === undefined || value === null || value === "" || typeof value === "boolean") return null
    var n = Number(value)
    return isFinite(n) ? n : null
  }

  function cleanText(value) {
    if (value === undefined || value === null) return ""
    return String(value).trim()
  }

  // "2h 14m", "14m", or "3d 2h".
  function formatAway(seconds) {
    var minutes = Math.max(1, Math.floor(seconds / 60))
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h " + (minutes % 60) + "m"
    return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
  }

  // BATTERY 84% · CHARGING · 72°F CLEAR · 3 UPDATES (null fields omitted).
  function buildTelemetry(status) {
    if (!status || typeof status !== "object") return ""
    var parts = []
    var battery = finiteNumber(status.battery)
    if (battery !== null) parts.push("BATTERY " + Math.round(battery) + "%")
    if (status.charging === true) parts.push("CHARGING")
    var weather = [cleanText(status.temp), cleanText(status.condition)].filter(function(s) { return s.length > 0 }).join(" ")
    if (weather.length > 0) parts.push(weather)
    var updates = finiteNumber(status.updates)
    if (updates !== null && updates > 0) parts.push(Math.round(updates) + (Math.round(updates) === 1 ? " UPDATE" : " UPDATES"))
    return parts.join(" · ").toUpperCase()
  }

  function pickGreeting(ctx) {
    var h = new Date().getHours()
    var force = typeof ctx.forceGreeting === "string" ? ctx.forceGreeting : ""
    var status = (ctx.status && typeof ctx.status === "object") ? ctx.status : null
    var special = (status && status.special && typeof status.special === "object"
                   && (cleanText(status.special.status) || cleanText(status.special.text))) ? status.special : null
    var away = finiteNumber(ctx.awaySeconds)
    var g = null
    var kind = ""
    if (special && (force === "special" || (force !== "away" && Math.random() < 0.7))) {
      g = { status: cleanText(special.status).toUpperCase() || "SPECIAL DAY", text: cleanText(special.text) || fill("Hello, {name}.") }
      kind = "special"
    } else if (away !== null && away > 0 && (force === "away" || (away >= awayGreetingMin && Math.random() < 0.35))) {
      g = { status: Math.random() < 0.5 ? "WELCOME BACK" : "SESSION RESUMED", text: "You were away " + formatAway(away) + fill(", {name}.") }
      kind = "away"
    } else if (h < 5 && Math.random() < 0.5) {
      g = nightGreeting
    } else {
      if (greetingBag.length === 0) greetingBag = shuffled(greetings.length, lastGreeting)
      lastGreeting = greetingBag.shift()
      g = greetings[lastGreeting]
    }
    statusLine = (variant === legendaryVariant && kind !== "special") ? "LEGENDARY UNLOCK" : fill(g.status)
    greetingLine = fill(g.text)
    titleCard = !!g.title
  }

  function prime() {
    primeToken += 1
    shown = true
    safetyTimer.restart()
  }

  // forcedVariant 0-10 plays that animation, 11 the legendary one (preview IPC);
  // anything else picks from the bag with a rare legendary roll.
  function play(forcedVariant, context) {
    var ctx = (context && typeof context === "object") ? context : ({})
    symbolOverride = (typeof ctx.symbol === "string" && knowsSymbol(ctx.symbol)) ? ctx.symbol : ""
    calm = ctx.motion === "reduced" || (ctx.motion !== "full" && reducedMotion)
    forceSecondary = ctx.secondary === true
    focusedScreen = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    // A primed stage is already up under the lock; only an unprimed one fades in.
    stageFadeIn = calm && !shown
    if (!shown) prime()
    var forced = finiteNumber(forcedVariant)
    var away = finiteNumber(ctx.awaySeconds)
    shortMode = !calm && (ctx.forceShort === true || (away !== null && away < shortAwayLimit))
    if (shortMode) {
      statusLine = ""; greetingLine = ""; telemetryLine = ""; titleCard = false
      lastSound = "unlock-short"
    } else {
      if (forced !== null && forced >= 0 && forced <= legendaryVariant && Math.floor(forced) === forced)
        variant = forced
      else
        variant = (legendaryEnabled && Math.random() < legendaryChance) ? legendaryVariant : pickVariant()
      pickGreeting(ctx)
      telemetryLine = buildTelemetry(ctx.status)
      // The calm fade has no hits to time a chime to: a soft two-note tap.
      lastSound = calm ? "unlock-short" : "unlock-" + variantNames[variant]
    }
    playing = true
    playToken += 1
    safetyTimer.restart()
    soundRequested(lastSound)
    console.log("hello-lock splash: " + (shortMode ? "short" : variantNames[variant])
      + (calm && !shortMode ? " (reduced motion)" : "") + (symbolOverride ? " symbol=" + symbolOverride : "")
      + " focused=" + (focusedScreen || "?") + (forceSecondary ? " (secondary preview)" : "")
      + " away=" + (away === null ? "?" : Math.round(away) + "s")
      + (shortMode ? "" : " greeting=\"" + statusLine + " / " + greetingLine + "\""))
  }

  function skip() {
    if (playing) skipToken += 1
  }

  function finish() {
    playing = false
    shown = false
    safetyTimer.stop()
    symbolOverride = ""
  }

  // Never let the overlay outlive a failed or stalled animation. Longest full
  // run is legendary + telemetry (~6.5s), so this leaves >1.5s of margin.
  Timer {
    id: safetyTimer
    interval: 8500
    onTriggered: root.finish()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData
      visible: root.shown
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "hello-lock-splash"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.playing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      // S is the symbol's square canvas; C is a padded canvas twice that size
      // so pieces can move, rotate and glow without hitting layer edges.
      // symbolSize sizes the text and effects (a square symbol's box). Wide
      // symbols such as typed wordmarks get a larger drawing box (stageSize, up
      // to 62% of the width) so they aren't squeezed into the square.
      readonly property real symbolSize: Math.round(Math.min(width, height) * 0.42)
      readonly property real symbolAspect: symbolProbe.implicitHeight > 0 ? symbolProbe.implicitWidth / symbolProbe.implicitHeight : 1
      readonly property real stageSize: symbolAspect > 1
        ? Math.round(Math.min(symbolSize * Math.sqrt(symbolAspect), width * 0.62)) : symbolSize
      // Half the visible height of the symbol, for placing the text under it.
      readonly property real inkHalf: symbolAspect > 1 ? stageSize / symbolAspect / 2 : symbolSize * 0.386
      readonly property real canvasSize: stageSize * 2
      readonly property real symbolCenterY: height * 0.40
      readonly property int statusSize: Math.max(13, Math.round(symbolSize * 0.05))
      readonly property int greetSize: Math.round(symbolSize * (root.titleCard ? 0.16 : 0.105))
      readonly property real coinDepth: Math.max(1, symbolSize * 0.0045)
      readonly property int telemetrySize: Math.max(12, Math.round(win.statusSize * 0.82))
      readonly property bool legendary: root.variant === root.legendaryVariant && !root.shortMode
      // Warm gold, nudged a little toward the theme accent so it still belongs.
      readonly property color goldColor: "#E8C26A"
      readonly property color goldGlow: Qt.tint(goldColor, Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22))
      readonly property color glyphColor: Commons.Color.foreground
      readonly property color faceColor: legendary ? Qt.lighter(goldColor, 1.06) : glyphColor
      readonly property color glowColor: legendary ? goldGlow : Commons.Color.accent
      readonly property color altColor: Commons.Color.urgent
      readonly property color sheenColor: legendary ? Qt.rgba(1, 0.93, 0.72, 0.75) : Qt.rgba(1, 1, 1, 0.55)

      // Particle targets inside the symbol silhouette (fractions of S).
      readonly property var points: [[0.406, 0.635], [0.344, 0.469], [0.531, 0.823], [0.844, 0.323], [0.115, 0.615], [0.594, 0.615], [0.240, 0.219], [0.240, 0.281], [0.385, 0.865], [0.260, 0.510], [0.344, 0.281], [0.760, 0.260], [0.302, 0.865], [0.302, 0.198], [0.510, 0.469], [0.260, 0.406], [0.573, 0.198], [0.615, 0.865], [0.656, 0.448], [0.385, 0.573], [0.865, 0.573], [0.365, 0.156], [0.552, 0.531], [0.115, 0.385], [0.760, 0.802], [0.198, 0.552], [0.323, 0.740], [0.552, 0.156], [0.302, 0.156], [0.573, 0.615], [0.177, 0.448], [0.323, 0.802], [0.385, 0.677], [0.698, 0.344], [0.469, 0.490], [0.760, 0.365], [0.615, 0.552], [0.635, 0.260], [0.823, 0.427], [0.719, 0.844], [0.865, 0.385], [0.885, 0.594], [0.677, 0.156], [0.448, 0.635], [0.385, 0.760], [0.615, 0.365], [0.302, 0.260], [0.240, 0.802], [0.698, 0.323], [0.760, 0.240], [0.594, 0.135], [0.323, 0.427], [0.719, 0.823], [0.615, 0.781], [0.656, 0.177], [0.531, 0.844], [0.115, 0.490], [0.469, 0.135], [0.198, 0.344], [0.469, 0.552], [0.448, 0.719], [0.344, 0.344], [0.802, 0.552], [0.885, 0.448]]

      Image {
        id: symbolProbe
        visible: false
        source: root.outerSource
        sourceSize.width: 400
      }

      // Animated state. Offsets are fractions of symbolSize: reset() can run
      // before the window has a size, so absolute pixels would be wrong.
      property real outerOpacity: 0
      property real outerScale: 1
      property real outerY: 0
      property real innerOpacity: 0
      property real innerY: 0
      property real spinAngle: 0
      property real flipAngle: 0
      property real symbolScale: 1
      property real symbolOpacity: 1
      property real symbolRise: 0
      property real glowOpacity: 0
      property real flash: 0
      property real ringScale: 0.9
      property real ringOpacity: 0
      property real sheenX: -1.1
      property real reveal: 1
      property real scanOpacity: 0
      property real glitch: 0
      property var jitter: [0, 0, 0, 0, 0, 0, 0, 0]
      property real particleT: 0
      property real particleOpacity: 0
      property real warpT: 0
      property real streakOpacity: 0
      property real arcT: 0
      property real arcOpacity: 0
      property real split: 0
      property bool halves: false
      // Legendary: gold sparks burst out then converge, a second wide orbit,
      // and a trailing second ring.
      property real sparkOpacity: 0
      property real burstT: 0
      property real convergeT: 0
      property real arc2T: 0
      property real arc2Opacity: 0
      property real ring2Scale: 0.9
      property real ring2Opacity: 0

      // Pixels: cascade clock (each cell flies over 0.45 of it, starting at its
      // own d), cell layer on/opacity, and a short wait for an image grid.
      property real pixelT: 0
      property bool pixOn: false
      property real pixOpacity: 1
      property int pixWaited: 0
      // Focused monitor (full animation) or another one (quiet crossfade, no text).
      property bool primary: true
      property int calmDelay: 0
      property real exitScale: 1.05

      property real typed: 0
      property real statusOpacity: 0
      property real greetOpacity: 0
      property real greetRise: 1
      property real greetTrack: 1
      property real telemetryOpacity: 0
      property bool blink: true
      property int textDelay: 1000
      property int typeDuration: 400
      property int holdDuration: 1000

      function prand(i, k) {
        var x = Math.sin(i * 12.9898 + k * 78.233) * 43758.5453
        return x - Math.floor(x)
      }

      function stopAll() {
        for (var i = 0; i < variantAnims.length; i++) variantAnims[i].stop()
        textTimeline.stop()
        shortAnim.stop()
        calmAnim.stop()
        pixWait.stop()
        skipOut.stop()
      }

      function reset() {
        stopAll()
        scene.opacity = 1
        outerOpacity = 0; outerScale = 1; outerY = 0
        innerOpacity = 0; innerY = 0
        spinAngle = 0; flipAngle = 0
        symbolScale = 1; symbolOpacity = 1; symbolRise = 0
        glowOpacity = 0; flash = 0
        ringScale = 0.9; ringOpacity = 0
        sheenX = -1.1
        reveal = 1; scanOpacity = 0
        glitch = 0; jitter = [0, 0, 0, 0, 0, 0, 0, 0]
        particleT = 0; particleOpacity = 0
        warpT = 0; streakOpacity = 0
        arcT = 0; arcOpacity = 0
        split = 0; halves = false
        sparkOpacity = 0; burstT = 0; convergeT = 0
        arc2T = 0; arc2Opacity = 0
        ring2Scale = 0.9; ring2Opacity = 0
        pixelT = 0; pixOn = false; pixOpacity = 1
        typed = 0; statusOpacity = 0
        greetOpacity = 0; greetRise = 1; greetTrack = 1
        telemetryOpacity = 0
      }

      // Starting pose for each animation, before its timeline runs.
      function setup(v) {
        switch (v) {
        case 0: innerY = 0.18; outerScale = 0.9; break
        case 1: outerY = -0.45; innerY = 0.45; break
        case 2: outerOpacity = 1; innerOpacity = 1; reveal = 0; break
        case 3: outerOpacity = 1; innerOpacity = 1; symbolOpacity = 0; glitch = 1; break
        case 4: outerOpacity = 1; innerOpacity = 1; symbolScale = 0; break
        case 5: symbolScale = 1.15; break
        case 6: outerOpacity = 1; innerOpacity = 1; symbolOpacity = 0; flipAngle = 80; symbolRise = 0.35; break
        case 7: break
        case 8: outerOpacity = 1; innerOpacity = 1; symbolScale = 3.2; symbolOpacity = 0; break
        case 9: outerOpacity = 1; innerOpacity = 1; symbolOpacity = 0; halves = true; split = 0.7; break
        case 10: break
        case 11: outerScale = 0.9; break
        }
      }

      function start() {
        reset()
        primary = root.isPrimaryScreen(win.modelData)
        exitScale = root.calm ? 1 : 1.05
        if (root.shortMode) {
          symbolScale = 0.9
          shortAnim.restart()
          scene.forceActiveFocus()
          return
        }
        typeDuration = Math.min(650, Math.max(250, root.statusLine.length * 28))
        // Give the telemetry line a moment to be read.
        holdDuration = root.telemetryLine.length > 0 ? 1400 : 1000
        scene.forceActiveFocus()
        if (root.calm) {
          startCalm(0, root.stageFadeIn)
        } else if (!primary) {
          // Other monitors: the same stage and timing, a quiet crossfade a
          // beat after the focused one, and no text.
          textDelay = root.textDelays[root.variant]
          startCalm(120, false)
        } else if (root.variant === root.pixelsVariant && root.pixelCells.length === 0) {
          // Image grid still being sampled (first play after a symbol change).
          pixWaited = 0
          pixWait.restart()
        } else {
          setup(root.variant)
          textDelay = root.textDelays[root.variant]
          variantAnims[root.variant].restart()
          textTimeline.restart()
        }
      }

      function startCalm(delay, fadeStage) {
        if (root.calm) textDelay = root.calmTextDelay
        calmDelay = delay
        if (fadeStage) scene.opacity = 0
        calmAnim.restart()
        textTimeline.restart()
      }

      readonly property var variantAnims: [coinAnim, assembleAnim, scanAnim, glitchAnim, heartbeatAnim, orbitAnim, monolithAnim, particlesAnim, warpAnim, splitAnim, pixelsAnim, legendaryAnim]

      // Waits up to ~400ms for the sampled grid; without one, the calm fade.
      Timer {
        id: pixWait
        interval: 16
        repeat: true
        onTriggered: {
          win.pixWaited += 1
          if (root.pixelCells.length > 0) {
            stop()
            win.textDelay = root.textDelays[root.pixelsVariant]
            pixelsAnim.restart()
            textTimeline.restart()
          } else if (win.pixWaited >= 25) {
            stop()
            console.warn("hello-lock splash: no pixel grid for this symbol; playing the calm fade")
            win.textDelay = root.calmTextDelay
            win.startCalm(0, false)
          }
        }
      }

      Connections {
        target: root
        function onShownChanged() { if (!root.shown) win.stopAll() }
        function onPrimeTokenChanged() { win.reset(); win.outerOpacity = 0; win.innerOpacity = 0 }
        function onPlayTokenChanged() { win.start() }
        function onSkipTokenChanged() {
          if (!root.playing) return
          win.stopAll()
          skipOut.restart()
        }
      }

      Timer {
        interval: 45
        repeat: true
        running: root.playing && win.glitch > 0
        onTriggered: {
          var next = []
          for (var i = 0; i < 8; i++) next.push(Math.random() < 0.45 ? (Math.random() * 2 - 1) : 0)
          win.jitter = next
        }
      }

      Timer {
        interval: 380
        repeat: true
        running: root.playing
        onTriggered: win.blink = !win.blink
      }

      Item {
        id: scene
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { root.skip(); event.accepted = true }

        // Samples an image symbol's alpha into the pixel grid (once per symbol,
        // shared by all screens). Invisible; painting needs a mapped window, so
        // it runs when the splash is primed or shown.
        Canvas {
          id: sampler
          width: 224
          height: 224
          opacity: 0
          property string key: ""
          property var urls: []
          readonly property bool wanted: root.shown && root.activeSymbolName === ""
            && root.outerSource !== "" && root.sampledKey !== root.imageKey
          onWantedChanged: if (wanted) start()
          function start() {
            key = root.imageKey
            urls = [root.outerSource, root.innerSource].filter(function(u) { return u })
            for (var i = 0; i < urls.length; i++) if (!isImageLoaded(urls[i])) loadImage(urls[i])
            requestPaint()
          }
          onImageLoaded: requestPaint()
          onPaint: {
            if (!key || key !== root.imageKey || root.sampledKey === key) return
            for (var i = 0; i < urls.length; i++) {
              if (isImageError(urls[i])) { root.setSampled(key, []); return }
              if (!isImageLoaded(urls[i])) return
            }
            var ctx = getContext("2d")
            ctx.reset()
            // The backing image is in device pixels (fractional scales too),
            // which getImageData reads unscaled: find its size from a corner mark.
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(width - 1, height - 1, 1, 1)
            var probe = ctx.getImageData(0, 0, width * 4, 1 + height * 4)
            var side = width
            for (var pi = probe.data.length - 1; pi >= 3; pi -= 4)
              if (probe.data[pi] > 0) { side = (pi - 3) / 4 % probe.width + 1; break }
            ctx.clearRect(0, 0, width, height)
            // Aspect-fit into the square, as the symbol Images draw.
            for (var j = 0; j < urls.length; j++) {
              var img = ctx.createImageData(urls[j])
              var iw = img && img.width > 0 ? img.width : width, ih = img && img.height > 0 ? img.height : height
              var f = Math.min(width / iw, height / ih)
              ctx.drawImage(urls[j], (width - iw * f) / 2, (height - ih * f) / 2, iw * f, ih * f)
            }
            root.setSampled(key, root.sampleCells(ctx.getImageData(0, 0, side, side), side))
          }
        }

        // Stage: the same blurred wallpaper as the lock screen, tinted.
        Rectangle {
          anchors.fill: parent
          color: Commons.Color.background
        }

        Image {
          id: wallpaper
          anchors.fill: parent
          source: (root.preload || root.shown) ? root.fileUrl(root.backgroundPath) : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          sourceSize.width: width
          sourceSize.height: height
        }

        MultiEffect {
          anchors.fill: wallpaper
          source: wallpaper
          autoPaddingEnabled: false
          blurEnabled: wallpaper.status === Image.Ready
          blur: 1.0
          blurMax: 128
          blurMultiplier: 1.25
          contrast: -0.08
        }

        Rectangle {
          anchors.fill: parent
          color: Commons.Color.background
          opacity: root.stageDim
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          hoverEnabled: true
          // No pointer on the boot screen; it returns when the overlay unmaps.
          cursorShape: Qt.BlankCursor
          onPressed: root.skip()
        }

        Item {
          id: stageSymbol
          readonly property real sz: win.stageSize
          readonly property real cz: win.canvasSize
          width: sz
          height: sz
          x: (win.width - sz) / 2
          y: win.symbolCenterY - sz / 2 + win.symbolRise * sz
          scale: win.symbolScale
          opacity: win.symbolOpacity

          // Thin accent ring that pulses outward.
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.95 * win.ringScale
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: win.glowColor
            opacity: win.ringOpacity
            visible: opacity > 0
          }

          // Legendary: a second, finer gold ring trailing the first.
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.95 * win.ring2Scale
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: win.goldColor
            opacity: win.ring2Opacity
            visible: opacity > 0
          }

          // Legendary: a wider counter-rotating gold orbit outside the arcs.
          Repeater {
            model: 2

            Shape {
              required property int index
              anchors.fill: parent
              visible: win.arc2Opacity > 0
              opacity: win.arc2Opacity * (1 - index * 0.25)
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                strokeColor: win.goldColor
                strokeWidth: 1.6 - index * 0.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                  centerX: stageSymbol.sz / 2
                  centerY: stageSymbol.sz / 2
                  radiusX: stageSymbol.sz * (0.78 + index * 0.12) * (1 + (1 - win.arc2T) * 0.6)
                  radiusY: radiusX
                  startAngle: 200 + index * 180 + (1 - win.arc2T) * (index === 0 ? 400 : -400)
                  sweepAngle: 150 - index * 40
                }
              }
            }
          }

          // Legendary sparks: burst out from the center, then fall onto points
          // inside the silhouette just as the coin materialises there.
          Repeater {
            model: win.points.length

            Rectangle {
              required property int index
              readonly property var target: win.points[index]
              readonly property real angle: win.prand(index, 7) * Math.PI * 2
              readonly property real dist: 0.45 + win.prand(index, 8) * 0.75
              readonly property real b: 1 - Math.pow(1 - win.burstT, 3)
              readonly property real delay: win.prand(index, 9) * 0.3
              readonly property real ct: Math.max(0, Math.min(1, (win.convergeT - delay) / 0.7))
              readonly property real c: ct < 0.5 ? 4 * ct * ct * ct : 1 - Math.pow(-2 * ct + 2, 3) / 2
              readonly property real bx: 0.5 + Math.cos(angle) * dist * b
              readonly property real by: 0.5 + Math.sin(angle) * dist * b
              visible: win.sparkOpacity > 0
              width: Math.max(2.5, stageSymbol.sz * (0.011 + win.prand(index, 10) * 0.008))
              height: width
              radius: width / 2
              color: index % 3 === 0 ? Qt.lighter(win.goldColor, 1.25) : win.goldColor
              opacity: win.sparkOpacity * (0.45 + 0.55 * win.prand(index, 11))
              x: (bx + (target[0] - bx) * c) * stageSymbol.sz - width / 2
              y: (by + (target[1] - by) * c) * stageSymbol.sz - height / 2
            }
          }

          // Orbit: three accent arcs spiral in and collapse into the symbol.
          Repeater {
            model: 3

            Shape {
              required property int index
              anchors.fill: parent
              visible: win.arcOpacity > 0
              opacity: win.arcOpacity * (1 - index * 0.18)
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                strokeColor: win.glowColor
                strokeWidth: 3 - index * 0.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                  centerX: stageSymbol.sz / 2
                  centerY: stageSymbol.sz / 2
                  radiusX: stageSymbol.sz * (0.5 + index * 0.1) * (1 + (1 - win.arcT) * 1.4)
                  radiusY: radiusX
                  startAngle: index * 120 + (1 - win.arcT) * (index % 2 === 0 ? -320 : 320)
                  sweepAngle: 80 + index * 30
                }
              }
            }
          }

          // Warp: radial streaks rushing inward.
          Repeater {
            model: 28

            Rectangle {
              required property int index
              readonly property real angle: (index / 28) * Math.PI * 2 + win.prand(index, 1) * 0.2
              readonly property real len: stageSymbol.sz * (0.2 + win.prand(index, 2) * 0.35)
              readonly property real dist: stageSymbol.sz * (1.9 - 1.4 * win.warpT) + win.prand(index, 3) * stageSymbol.sz * 0.3
              visible: win.streakOpacity > 0
              width: 2
              height: len
              radius: 1
              color: win.glowColor
              opacity: win.streakOpacity * (0.35 + 0.65 * win.prand(index, 4))
              x: stageSymbol.sz / 2 + Math.cos(angle) * dist - width / 2
              y: stageSymbol.sz / 2 + Math.sin(angle) * dist - height / 2
              rotation: angle * 180 / Math.PI + 90
            }
          }

          // Particles: diamonds fly in from a scattered ring to points inside
          // the silhouette, then the symbol resolves where they land.
          Repeater {
            model: win.points.length

            Rectangle {
              required property int index
              readonly property var target: win.points[index]
              readonly property real angle: win.prand(index, 5) * Math.PI * 2
              readonly property real dist: 0.9 + win.prand(index, 6) * 0.8
              readonly property real delay: (index % 16) / 16 * 0.35
              readonly property real t: Math.max(0, Math.min(1, (win.particleT - delay) / 0.65))
              readonly property real e: 1 - Math.pow(1 - t, 4)
              readonly property real sx: 0.5 + Math.cos(angle) * dist
              readonly property real sy: 0.5 + Math.sin(angle) * dist
              visible: win.particleOpacity > 0
              width: Math.max(3, stageSymbol.sz * 0.02)
              height: width
              rotation: 45
              color: win.glowColor
              opacity: win.particleOpacity * (0.3 + 0.7 * t)
              x: (sx + (target[0] - sx) * e) * stageSymbol.sz - width / 2
              y: (sy + (target[1] - sy) * e) * stageSymbol.sz - height / 2
            }
          }

          Item {
            id: canvasHost
            x: -stageSymbol.sz / 2
            y: -stageSymbol.sz / 2
            width: stageSymbol.cz
            height: stageSymbol.cz

            // Both symbol parts, animated separately, rendered as one layer.
            Item {
              id: glyphs
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Image {
                x: stageSymbol.sz / 2
                y: stageSymbol.sz / 2 + win.outerY * stageSymbol.sz
                width: stageSymbol.sz
                height: stageSymbol.sz
                source: root.outerSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(stageSymbol.sz * 1.5)
                sourceSize.height: Math.round(stageSymbol.sz * 1.5)
                opacity: win.outerOpacity
                scale: win.outerScale
              }

              Image {
                x: stageSymbol.sz / 2
                y: stageSymbol.sz / 2 + win.innerY * stageSymbol.sz
                width: stageSymbol.sz
                height: stageSymbol.sz
                source: root.innerSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(stageSymbol.sz * 1.5)
                sourceSize.height: Math.round(stageSymbol.sz * 1.5)
                opacity: win.innerOpacity
              }
            }

            // What the symbol effects draw from: a white silhouette when tinted,
            // so the theme colour applies to any symbol colour.
            Item {
              id: glyphSource
              anchors.fill: parent
              visible: false
              layer.enabled: true

              MultiEffect {
                anchors.fill: parent
                source: glyphs
                brightness: root.tintSymbol ? 1 : 0
              }
            }

            // Separate unpadded copy used only as the sheen mask: sharing
            // `glyphs` lets the bloom's auto-padding stretch the mask.
            Item {
              id: sheenMask
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Image {
                x: stageSymbol.sz / 2
                y: stageSymbol.sz / 2 + win.outerY * stageSymbol.sz
                width: stageSymbol.sz
                height: stageSymbol.sz
                source: root.outerSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(stageSymbol.sz * 1.5)
                sourceSize.height: Math.round(stageSymbol.sz * 1.5)
                opacity: win.outerOpacity
                scale: win.outerScale
              }

              Image {
                x: stageSymbol.sz / 2
                y: stageSymbol.sz / 2 + win.innerY * stageSymbol.sz
                width: stageSymbol.sz
                height: stageSymbol.sz
                source: root.innerSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(stageSymbol.sz * 1.5)
                sourceSize.height: Math.round(stageSymbol.sz * 1.5)
                opacity: win.innerOpacity
              }
            }

            // Light sheen band, clipped to the symbol's shape below.
            Item {
              id: sheenSource
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Rectangle {
                x: stageSymbol.sz / 2 + win.sheenX * stageSymbol.sz
                y: 0
                width: stageSymbol.sz * 0.32
                height: stageSymbol.cz
                rotation: 18
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 0.5; color: win.sheenColor }
                  GradientStop { position: 1.0; color: "transparent" }
                }
              }
            }

            // Coin edge: darker copies stacked behind the face. Each shares the
            // rotation, then shifts by depth × sin(angle), so the symbol shows
            // thickness when turned. Farthest layer first.
            Repeater {
              model: 7

              MultiEffect {
                required property int index
                readonly property int depth: 7 - index
                anchors.fill: parent
                source: glyphSource
                visible: Math.abs(Math.sin(win.spinAngle * Math.PI / 180)) > 0.02
                  || Math.abs(Math.sin(win.flipAngle * Math.PI / 180)) > 0.02
                colorization: 1
                colorizationColor: Qt.darker(win.faceColor, 1.35 + depth * 0.07)
                transform: [
                  Rotation { origin.x: stageSymbol.sz; origin.y: stageSymbol.sz; axis.x: 0; axis.y: 1; axis.z: 0; angle: win.spinAngle },
                  Rotation { origin.x: stageSymbol.sz; origin.y: stageSymbol.sz; axis.x: 1; axis.y: 0; axis.z: 0; angle: win.flipAngle },
                  Translate {
                    x: -depth * win.coinDepth * Math.sin(win.spinAngle * Math.PI / 180)
                    y: depth * win.coinDepth * Math.sin(win.flipAngle * Math.PI / 180)
                  }
                ]
              }
            }

            // Scan reveal: clips everything above the moving beam.
            Item {
              id: revealClip
              width: parent.width
              height: win.reveal >= 1 ? parent.height : parent.height * (0.29 + win.reveal * 0.42)
              clip: win.reveal < 1

              Item {
                id: coin
                width: canvasHost.width
                height: canvasHost.height
                transform: [
                  Rotation { origin.x: stageSymbol.sz; origin.y: stageSymbol.sz; axis.x: 0; axis.y: 1; axis.z: 0; angle: win.spinAngle },
                  Rotation { origin.x: stageSymbol.sz; origin.y: stageSymbol.sz; axis.x: 1; axis.y: 0; axis.z: 0; angle: win.flipAngle }
                ]

                // Symbol face in the theme foreground; accent bloom drawn as
                // a centered shadow. Not auto-padded: padding stretched the
                // layer source ~15% larger than the symbol box (a visible pop
                // after split/glitch/pixels). The 2x canvas leaves the bloom
                // ample room without it.
                MultiEffect {
                  anchors.fill: parent
                  source: glyphSource
                  autoPaddingEnabled: false
                  visible: !win.halves && win.glitch <= 0
                  colorization: root.tintSymbol ? 1 : 0
                  colorizationColor: win.faceColor
                  brightness: win.flash
                  shadowEnabled: true
                  shadowColor: win.glowColor
                  shadowOpacity: win.glowOpacity
                  shadowBlur: 1
                  shadowScale: 1.04
                  shadowHorizontalOffset: 0
                  shadowVerticalOffset: 0
                  blurMax: 64
                }

                // Glitch: offset color ghosts plus horizontally jittered slices.
                MultiEffect {
                  anchors.fill: parent
                  source: glyphSource
                  visible: win.glitch > 0
                  x: -win.glitch * stageSymbol.sz * 0.045
                  colorization: 1
                  colorizationColor: win.glowColor
                  opacity: win.glitch * 0.75
                }

                MultiEffect {
                  anchors.fill: parent
                  source: glyphSource
                  visible: win.glitch > 0
                  x: win.glitch * stageSymbol.sz * 0.045
                  colorization: 1
                  colorizationColor: win.altColor
                  opacity: win.glitch * 0.6
                }

                Repeater {
                  model: 8

                  Item {
                    required property int index
                    visible: win.glitch > 0
                    x: (win.jitter[index] || 0) * win.glitch * stageSymbol.sz * 0.12
                    y: index * coin.height / 8
                    width: coin.width
                    height: coin.height / 8
                    clip: true

                    MultiEffect {
                      y: -parent.y
                      width: coin.width
                      height: coin.height
                      source: glyphSource
                      colorization: root.tintSymbol ? 1 : 0
                      colorizationColor: win.glyphColor
                    }
                  }
                }

                // Split: left and right halves slide together.
                Item {
                  visible: win.halves
                  x: -win.split * stageSymbol.sz
                  width: coin.width / 2
                  height: coin.height
                  clip: true

                  MultiEffect {
                    width: coin.width
                    height: coin.height
                    source: glyphSource
                    colorization: root.tintSymbol ? 1 : 0
                    colorizationColor: win.glyphColor
                  }
                }

                Item {
                  visible: win.halves
                  x: coin.width / 2 + win.split * stageSymbol.sz
                  width: coin.width / 2
                  height: coin.height
                  clip: true

                  MultiEffect {
                    x: -coin.width / 2
                    width: coin.width
                    height: coin.height
                    source: glyphSource
                    colorization: root.tintSymbol ? 1 : 0
                    colorizationColor: win.glyphColor
                  }
                }

                MultiEffect {
                  anchors.fill: parent
                  source: sheenSource
                  autoPaddingEnabled: false
                  maskEnabled: true
                  maskSource: sheenMask
                }
              }
            }

            // Scan beam riding the reveal edge.
            Rectangle {
              visible: win.scanOpacity > 0
              x: stageSymbol.sz * 0.15
              y: revealClip.height - stageSymbol.sz * 0.12
              width: stageSymbol.sz * 1.7
              height: stageSymbol.sz * 0.12
              opacity: win.scanOpacity * 0.35
              gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: win.glowColor }
              }
            }

            Rectangle {
              visible: win.scanOpacity > 0
              x: stageSymbol.sz * 0.15
              y: revealClip.height - 1
              width: stageSymbol.sz * 1.7
              height: 2
              radius: 1
              color: win.glowColor
              opacity: win.scanOpacity
            }
          }

          // Pixels: each grid cell flies in spinning from beyond the symbol,
          // lands on its exact spot with a white-hot flash and a small pop,
          // then the real symbol takes over underneath. Cells overlap by a
          // fraction of a pixel so the assembled grid shows no seams.
          Repeater {
            model: root.pixelCells

            Rectangle {
              required property var modelData
              readonly property real p: Math.max(0, Math.min(1, (win.pixelT - modelData.d) / 0.45))
              readonly property real f: Math.min(1, p / 0.7)
              readonly property real e: 1 - Math.pow(1 - f, 3)
              readonly property real l: Math.max(0, (p - 0.7) / 0.3)
              readonly property color face: root.tintSymbol || !modelData.c ? (root.tintSymbol ? win.faceColor : "#ffffff") : modelData.c
              visible: win.pixOn && p > 0
              antialiasing: true
              x: (modelData.x + modelData.sx * (1 - e)) * stageSymbol.sz - 0.35
              y: (modelData.y + modelData.sy * (1 - e)) * stageSymbol.sz - 0.35
              width: modelData.w * stageSymbol.sz + 0.7
              height: modelData.h * stageSymbol.sz + 0.7
              rotation: modelData.r * (1 - e)
              scale: f < 1 ? 0.3 + 0.7 * e : 1 + 0.22 * Math.sin(l * Math.PI) * (1 - l)
              opacity: win.pixOpacity * Math.min(1, f * 2.2)
              color: f < 1 ? win.glowColor : face

              Rectangle {
                anchors.fill: parent
                antialiasing: true
                visible: parent.f >= 1 && parent.l < 1
                color: Qt.lighter(win.glowColor, 1.6)
                opacity: 0.9 * (1 - parent.l) * (1 - parent.l)
              }
            }
          }
        }

        // Greeting: a typed status line in the accent color, then the
        // greeting tracking in beneath it.
        Item {
          id: statusBox
          width: statusMetrics.advanceWidth
          height: statusText.implicitHeight
          anchors.horizontalCenter: parent.horizontalCenter
          y: win.symbolCenterY + win.inkHalf + win.height * 0.055
          visible: win.primary
          opacity: win.statusOpacity

          TextMetrics {
            id: statusMetrics
            font: statusText.font
            text: root.statusLine
          }

          Text {
            id: statusText
            textFormat: Text.PlainText
            text: root.statusLine.substring(0, Math.floor(win.typed))
            color: win.glowColor
            font.family: "Share Tech Mono"
            font.pixelSize: win.statusSize
            font.letterSpacing: win.statusSize * 0.42
          }

          Rectangle {
            x: statusText.contentWidth + 2
            anchors.verticalCenter: statusText.verticalCenter
            width: Math.round(win.statusSize * 0.55)
            height: Math.round(win.statusSize * 0.95)
            color: win.glowColor
            visible: win.typed < root.statusLine.length || win.blink
          }
        }

        Text {
          id: greetingText
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          y: statusBox.y + statusBox.height + win.symbolSize * 0.035 + win.greetRise * win.symbolSize * 0.06
          text: root.greetingLine
          color: win.glyphColor
          visible: false
          layer.enabled: true
          font.family: "Oxanium"
          font.weight: root.titleCard ? Font.Medium : Font.DemiBold
          font.pixelSize: win.greetSize
          font.letterSpacing: win.greetSize * ((root.titleCard ? 0.45 : 0.02) + win.greetTrack * 0.22)
        }

        // Soft accent glow around the greeting (separate item so the glow is
        // auto-padded rather than clipped to the text's bounds).
        MultiEffect {
          x: greetingText.x
          y: greetingText.y
          width: greetingText.width
          height: greetingText.height
          source: greetingText
          visible: win.primary && win.greetOpacity > 0
          opacity: win.greetOpacity
          shadowEnabled: true
          shadowColor: win.glowColor
          shadowOpacity: 0.45
          shadowBlur: 0.7
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 0
          blurMax: 32
        }

        // Telemetry: live status in small muted mono under the greeting.
        Text {
          id: telemetryText
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          y: statusBox.y + statusBox.height + win.symbolSize * 0.035 + greetingText.height
            + win.symbolSize * 0.045 + win.greetRise * win.symbolSize * 0.03
          text: root.telemetryLine
          visible: win.primary && text.length > 0 && win.telemetryOpacity > 0
          color: win.glyphColor
          opacity: win.telemetryOpacity * 0.55
          font.family: "Share Tech Mono"
          font.pixelSize: win.telemetrySize
          font.letterSpacing: win.telemetrySize * 0.32
        }
      }

      // --- Animations -------------------------------------------------------

      // 0 · Coin: two upright turns, decelerating to rest facing forward.
      ParallelAnimation {
        id: coinAnim
        NumberAnimation { target: win; property: "spinAngle"; from: 0; to: 720; duration: 1250; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "outerScale"; from: 0.9; to: 1; duration: 900; easing.type: Easing.OutQuint }
        SequentialAnimation {
          PauseAnimation { duration: 180 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "innerY"; from: 0.18; to: 0; duration: 750; easing.type: Easing.OutQuint }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 250 }
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 450; easing.type: Easing.OutQuad }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 700; easing.type: Easing.InOutQuad }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1000 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.55; to: 0; duration: 900; easing.type: Easing.OutQuad }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1150 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 1 · Assemble: arch drops in from above, pedestal rises from below,
      // they dock with a flash.
      ParallelAnimation {
        id: assembleAnim
        NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "outerY"; from: -0.45; to: 0; duration: 750; easing.type: Easing.OutQuint }
        SequentialAnimation {
          PauseAnimation { duration: 80 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 350; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "innerY"; from: 0.45; to: 0; duration: 750; easing.type: Easing.OutQuint }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 600 }
          NumberAnimation { target: win; property: "flash"; from: 0; to: 0.4; duration: 70 }
          NumberAnimation { target: win; property: "flash"; to: 0; duration: 450; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
          PauseAnimation { duration: 600 }
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 150 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 800; easing.type: Easing.InOutQuad }
        }
        SequentialAnimation {
          PauseAnimation { duration: 620 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.6; to: 0; duration: 900; easing.type: Easing.OutQuad }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 950 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 2 · Scan: an accent beam sweeps down, revealing the symbol.
      ParallelAnimation {
        id: scanAnim
        NumberAnimation { target: win; property: "scanOpacity"; from: 0; to: 1; duration: 150 }
        NumberAnimation { target: win; property: "reveal"; from: 0; to: 1; duration: 1000; easing.type: Easing.InOutCubic }
        SequentialAnimation {
          PauseAnimation { duration: 950 }
          NumberAnimation { target: win; property: "scanOpacity"; to: 0; duration: 250 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 300 }
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 0.75; duration: 700 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 500 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1000 }
          NumberAnimation { target: win; property: "flash"; from: 0; to: 0.3; duration: 80 }
          NumberAnimation { target: win; property: "flash"; to: 0; duration: 400 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1000 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.5; to: 0; duration: 900; easing.type: Easing.OutQuad }
          }
        }
      }

      // 3 · Glitch: flickers in through color ghosts and torn slices, then locks.
      ParallelAnimation {
        id: glitchAnim
        SequentialAnimation {
          NumberAnimation { target: win; property: "symbolOpacity"; to: 1; duration: 60 }
          NumberAnimation { target: win; property: "symbolOpacity"; to: 0.25; duration: 50 }
          NumberAnimation { target: win; property: "symbolOpacity"; to: 1; duration: 60 }
          PauseAnimation { duration: 120 }
          NumberAnimation { target: win; property: "symbolOpacity"; to: 0.55; duration: 40 }
          NumberAnimation { target: win; property: "symbolOpacity"; to: 1; duration: 60 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 480 }
          NumberAnimation { target: win; property: "glitch"; from: 1; to: 0; duration: 420; easing.type: Easing.InQuad }
        }
        SequentialAnimation {
          PauseAnimation { duration: 880 }
          NumberAnimation { target: win; property: "flash"; from: 0; to: 0.4; duration: 60 }
          NumberAnimation { target: win; property: "flash"; to: 0; duration: 400 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 880 }
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 120 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 700 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 900 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.55; to: 0; duration: 900; easing.type: Easing.OutQuad }
          }
        }
      }

      // 4 · Heartbeat: pops in, then two power pulses like a console LED.
      ParallelAnimation {
        id: heartbeatAnim
        SequentialAnimation {
          NumberAnimation { target: win; property: "symbolScale"; from: 0; to: 1.08; duration: 420; easing.type: Easing.OutCubic }
          NumberAnimation { target: win; property: "symbolScale"; to: 1; duration: 220; easing.type: Easing.InOutQuad }
          PauseAnimation { duration: 120 }
          NumberAnimation { target: win; property: "symbolScale"; to: 1.05; duration: 110; easing.type: Easing.OutQuad }
          NumberAnimation { target: win; property: "symbolScale"; to: 1; duration: 230; easing.type: Easing.InQuad }
          PauseAnimation { duration: 150 }
          NumberAnimation { target: win; property: "symbolScale"; to: 1.035; duration: 110; easing.type: Easing.OutQuad }
          NumberAnimation { target: win; property: "symbolScale"; to: 1; duration: 260; easing.type: Easing.InQuad }
        }
        SequentialAnimation {
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 0.6; duration: 420 }
          PauseAnimation { duration: 340 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 1; duration: 110 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.5; duration: 230 }
          PauseAnimation { duration: 150 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.9; duration: 110 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 260 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 760 }
          NumberAnimation { target: win; property: "flash"; from: 0; to: 0.25; duration: 110 }
          NumberAnimation { target: win; property: "flash"; to: 0; duration: 230 }
          PauseAnimation { duration: 150 }
          NumberAnimation { target: win; property: "flash"; to: 0.18; duration: 110 }
          NumberAnimation { target: win; property: "flash"; to: 0; duration: 260 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 760 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.6; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.6; to: 0; duration: 700; easing.type: Easing.OutQuad }
          }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.6; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.4; to: 0; duration: 700; easing.type: Easing.OutQuad }
          }
        }
      }

      // 5 · Orbit: accent arcs spiral inward and collapse into the symbol.
      ParallelAnimation {
        id: orbitAnim
        NumberAnimation { target: win; property: "arcOpacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { target: win; property: "arcT"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutCubic }
        SequentialAnimation {
          PauseAnimation { duration: 860 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "arcOpacity"; to: 0; duration: 220 }
            NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 120 }
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 120 }
            NumberAnimation { target: win; property: "symbolScale"; from: 1.15; to: 1; duration: 600; easing.type: Easing.OutQuint }
            SequentialAnimation {
              NumberAnimation { target: win; property: "flash"; from: 0; to: 0.4; duration: 60 }
              NumberAnimation { target: win; property: "flash"; to: 0; duration: 450; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
              NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 120 }
              NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 800 }
            }
            ParallelAnimation {
              NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.8; duration: 900; easing.type: Easing.OutCubic }
              NumberAnimation { target: win; property: "ringOpacity"; from: 0.7; to: 0; duration: 900; easing.type: Easing.OutQuad }
            }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1150 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 6 · Monolith: rises from below while tilting upright, like a slab
      // standing up, settling with a slight overshoot.
      ParallelAnimation {
        id: monolithAnim
        NumberAnimation { target: win; property: "symbolOpacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "flipAngle"; from: 80; to: 0; duration: 1050; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
        NumberAnimation { target: win; property: "symbolRise"; from: 0.35; to: 0; duration: 1000; easing.type: Easing.OutQuint }
        SequentialAnimation {
          PauseAnimation { duration: 550 }
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 350 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 700 }
        }
        SequentialAnimation {
          PauseAnimation { duration: 950 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.55; to: 0; duration: 900; easing.type: Easing.OutQuad }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1100 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 7 · Particles: light diamonds converge onto the silhouette, then it resolves.
      ParallelAnimation {
        id: particlesAnim
        NumberAnimation { target: win; property: "particleOpacity"; from: 0; to: 1; duration: 150 }
        NumberAnimation { target: win; property: "particleT"; from: 0; to: 1; duration: 1050 }
        SequentialAnimation {
          PauseAnimation { duration: 950 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "particleOpacity"; to: 0; duration: 380 }
            SequentialAnimation {
              NumberAnimation { target: win; property: "flash"; from: 0; to: 0.4; duration: 80 }
              NumberAnimation { target: win; property: "flash"; to: 0; duration: 420 }
            }
            SequentialAnimation {
              NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 150 }
              NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 750 }
            }
            ParallelAnimation {
              NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
              NumberAnimation { target: win; property: "ringOpacity"; from: 0.55; to: 0; duration: 900; easing.type: Easing.OutQuad }
            }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1250 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 8 · Warp: drops out of hyperspace, zooming in past light streaks.
      ParallelAnimation {
        id: warpAnim
        NumberAnimation { target: win; property: "warpT"; from: 0; to: 1; duration: 750; easing.type: Easing.OutQuad }
        SequentialAnimation {
          NumberAnimation { target: win; property: "streakOpacity"; from: 0; to: 1; duration: 100 }
          PauseAnimation { duration: 400 }
          NumberAnimation { target: win; property: "streakOpacity"; to: 0; duration: 300 }
        }
        NumberAnimation { target: win; property: "symbolOpacity"; from: 0; to: 1; duration: 350 }
        NumberAnimation { target: win; property: "symbolScale"; from: 3.2; to: 1; duration: 750; easing.type: Easing.OutExpo }
        SequentialAnimation {
          PauseAnimation { duration: 650 }
          ParallelAnimation {
            SequentialAnimation {
              NumberAnimation { target: win; property: "flash"; from: 0; to: 0.4; duration: 70 }
              NumberAnimation { target: win; property: "flash"; to: 0; duration: 420 }
            }
            SequentialAnimation {
              NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 150 }
              NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 750 }
            }
            ParallelAnimation {
              NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
              NumberAnimation { target: win; property: "ringOpacity"; from: 0.6; to: 0; duration: 900; easing.type: Easing.OutQuad }
            }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1000 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 9 · Split: the two halves slide together and seal with a flash.
      ParallelAnimation {
        id: splitAnim
        NumberAnimation { target: win; property: "symbolOpacity"; from: 0; to: 1; duration: 300 }
        NumberAnimation { target: win; property: "split"; from: 0.7; to: 0; duration: 750; easing.type: Easing.OutQuint }
        SequentialAnimation {
          PauseAnimation { duration: 700 }
          ScriptAction { script: win.halves = false }
          ParallelAnimation {
            SequentialAnimation {
              NumberAnimation { target: win; property: "flash"; from: 0; to: 0.4; duration: 60 }
              NumberAnimation { target: win; property: "flash"; to: 0; duration: 450 }
            }
            SequentialAnimation {
              NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 120 }
              NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 800 }
            }
            ParallelAnimation {
              NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
              NumberAnimation { target: win; property: "ringOpacity"; from: 0.6; to: 0; duration: 900; easing.type: Easing.OutQuad }
            }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1000 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // 10 · Pixels: the symbol's grid cells cascade in row by row, spinning
      // in from beyond the symbol and snapping onto the grid with a flash;
      // once the last lands the real symbol fades in beneath them (pixel
      // exact for built-ins), the cells dissolve and the symbol blooms.
      ParallelAnimation {
        id: pixelsAnim
        ScriptAction { script: win.pixOn = true }
        NumberAnimation { target: win; property: "pixelT"; from: 0; to: 1; duration: 1150 }
        SequentialAnimation {
          PauseAnimation { duration: 950 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 120 }
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 120 }
          }
          PauseAnimation { duration: 60 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "pixOpacity"; from: 1; to: 0; duration: 320; easing.type: Easing.InOutQuad }
            SequentialAnimation {
              NumberAnimation { target: win; property: "flash"; from: 0; to: 0.35; duration: 70 }
              NumberAnimation { target: win; property: "flash"; to: 0; duration: 450; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
              NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 1; duration: 150 }
              NumberAnimation { target: win; property: "glowOpacity"; to: 0.55; duration: 800; easing.type: Easing.InOutQuad }
            }
            ParallelAnimation {
              NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.7; duration: 900; easing.type: Easing.OutCubic }
              NumberAnimation { target: win; property: "ringOpacity"; from: 0.55; to: 0; duration: 900; easing.type: Easing.OutQuad }
            }
          }
          ScriptAction { script: win.pixOn = false }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1350 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 650; easing.type: Easing.InOutCubic }
        }
      }

      // Calm fade: reduced motion (calmDelay 0, stage fading in when it was
      // not primed) and the unfocused monitors (calmDelay 120). No flash,
      // rings or sheen; the symbol scales by 3% at most.
      ParallelAnimation {
        id: calmAnim
        NumberAnimation { target: scene; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
        SequentialAnimation {
          PauseAnimation { duration: win.calmDelay }
          ParallelAnimation {
            NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "symbolScale"; from: root.calm ? 1 : 0.97; to: 1; duration: 800; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 0.5; duration: 900; easing.type: Easing.InOutQuad }
          }
        }
      }

      // 11 · Legendary (rare): gold sparks burst outward and converge onto
      // the silhouette inside a wide double orbit; the coin materialises from
      // them, spins two turns and lands with a gold flash, rings and sheen.
      ParallelAnimation {
        id: legendaryAnim
        // Sparks: burst (0-700), converge (550-1400), dissolve into the coin.
        NumberAnimation { target: win; property: "sparkOpacity"; from: 0; to: 1; duration: 120 }
        NumberAnimation { target: win; property: "burstT"; from: 0; to: 1; duration: 700; easing.type: Easing.Linear }
        SequentialAnimation {
          PauseAnimation { duration: 550 }
          NumberAnimation { target: win; property: "convergeT"; from: 0; to: 1; duration: 850; easing.type: Easing.Linear }
        }
        SequentialAnimation {
          PauseAnimation { duration: 1300 }
          NumberAnimation { target: win; property: "sparkOpacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
        }
        // Double orbit: accent-gold arcs inside, a wider gold pair outside.
        NumberAnimation { target: win; property: "arcOpacity"; from: 0; to: 0.9; duration: 300 }
        NumberAnimation { target: win; property: "arcT"; from: 0; to: 1; duration: 1350; easing.type: Easing.InOutCubic }
        NumberAnimation { target: win; property: "arc2Opacity"; from: 0; to: 0.8; duration: 400 }
        NumberAnimation { target: win; property: "arc2T"; from: 0; to: 1; duration: 1500; easing.type: Easing.InOutCubic }
        SequentialAnimation {
          PauseAnimation { duration: 1250 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "arcOpacity"; to: 0; duration: 300 }
            NumberAnimation { target: win; property: "arc2Opacity"; to: 0; duration: 450 }
          }
        }
        // Coin: fades in face-on where the sparks landed, then spins down.
        SequentialAnimation {
          PauseAnimation { duration: 1250 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "outerScale"; from: 0.9; to: 1; duration: 900; easing.type: Easing.OutQuint }
            NumberAnimation { target: win; property: "spinAngle"; from: 0; to: 720; duration: 1150; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 0.6; duration: 500 }
          }
        }
        // Landing: gold flash, bloom, two rings.
        SequentialAnimation {
          PauseAnimation { duration: 2200 }
          ParallelAnimation {
            SequentialAnimation {
              NumberAnimation { target: win; property: "flash"; from: 0; to: 0.5; duration: 80 }
              NumberAnimation { target: win; property: "flash"; to: 0; duration: 650; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
              NumberAnimation { target: win; property: "glowOpacity"; to: 1; duration: 140 }
              NumberAnimation { target: win; property: "glowOpacity"; to: 0.65; duration: 900; easing.type: Easing.InOutQuad }
            }
            ParallelAnimation {
              NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 2.0; duration: 1100; easing.type: Easing.OutCubic }
              NumberAnimation { target: win; property: "ringOpacity"; from: 0.75; to: 0; duration: 1100; easing.type: Easing.OutQuad }
            }
            SequentialAnimation {
              PauseAnimation { duration: 160 }
              ParallelAnimation {
                NumberAnimation { target: win; property: "ring2Scale"; from: 0.9; to: 1.55; duration: 1000; easing.type: Easing.OutCubic }
                NumberAnimation { target: win; property: "ring2Opacity"; from: 0.7; to: 0; duration: 1000; easing.type: Easing.OutQuad }
              }
            }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 2350 }
          NumberAnimation { target: win; property: "sheenX"; from: -1.1; to: 1.5; duration: 800; easing.type: Easing.InOutCubic }
        }
      }

      // Short mode (quick unlocks): a single pop with a flash and ring, then
      // straight back to the desktop (~1.1s, no text).
      ParallelAnimation {
        id: shortAnim
        NumberAnimation { target: win; property: "outerOpacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "innerOpacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "symbolScale"; from: 0.9; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        SequentialAnimation {
          PauseAnimation { duration: 120 }
          NumberAnimation { target: win; property: "flash"; from: 0; to: 0.35; duration: 70 }
          NumberAnimation { target: win; property: "flash"; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
          NumberAnimation { target: win; property: "glowOpacity"; from: 0; to: 0.9; duration: 190 }
          NumberAnimation { target: win; property: "glowOpacity"; to: 0.5; duration: 400; easing.type: Easing.InOutQuad }
        }
        SequentialAnimation {
          PauseAnimation { duration: 120 }
          ParallelAnimation {
            NumberAnimation { target: win; property: "ringScale"; from: 0.9; to: 1.55; duration: 650; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "ringOpacity"; from: 0.55; to: 0; duration: 650; easing.type: Easing.OutQuad }
          }
        }
        SequentialAnimation {
          PauseAnimation { duration: 600 }
          ParallelAnimation {
            NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InOutCubic }
            NumberAnimation { target: win; property: "symbolScale"; to: 1.04; duration: 500; easing.type: Easing.InCubic }
          }
          ScriptAction { script: root.finish() }
        }
      }

      // Greeting, hold, then fade the whole stage out to the desktop.
      SequentialAnimation {
        id: textTimeline
        PauseAnimation { duration: win.textDelay }
        ParallelAnimation {
          NumberAnimation { target: win; property: "statusOpacity"; from: 0; to: 1; duration: 120 }
          NumberAnimation { target: win; property: "typed"; from: 0; to: root.statusLine.length; duration: win.typeDuration }
        }
        PauseAnimation { duration: 80 }
        ParallelAnimation {
          NumberAnimation { target: win; property: "greetOpacity"; from: 0; to: 1; duration: 550; easing.type: Easing.OutCubic }
          NumberAnimation { target: win; property: "greetRise"; from: root.calm ? 0 : 1; to: 0; duration: 750; easing.type: Easing.OutQuint }
          NumberAnimation { target: win; property: "greetTrack"; from: root.calm ? 0 : 1; to: 0; duration: 1000; easing.type: Easing.OutQuint }
          SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: win; property: "telemetryOpacity"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
          }
        }
        PauseAnimation { duration: win.holdDuration }
        ParallelAnimation {
          NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InOutCubic }
          NumberAnimation { target: win; property: "symbolScale"; to: win.exitScale; duration: 600; easing.type: Easing.InCubic }
        }
        // Only the primary timeline can finish every monitor. Its pixels path
        // may start later while the image is sampled; a secondary must not cut
        // the greeting short. The safety timer covers a primary disappearing.
        ScriptAction { script: { if (win.primary || root.forceSecondary) root.finish() } }
      }

      SequentialAnimation {
        id: skipOut
        NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutCubic }
        ScriptAction { script: root.finish() }
      }
    }
  }
}
