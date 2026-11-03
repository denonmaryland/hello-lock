import QtQuick
import "Icons.js" as Icons

// 03 · Unlock: the chosen symbol with its halo and the greeting under it.
// "Play unlock" replays a short reveal; "Play transition" hands the lock
// screen's logo over to the symbol with the real handoff/<name>.qml effect
// (the built-in fall back if it can't load; a crossfade with reduced
// motion). Greeting and Background change the stage as the splash would.
// The full-screen button opens the real unlock preview.
Item {
  id: stage
  property Item s: null
  readonly property real total: s && s.unlockDuration > 0 ? Math.min(2.4, s.unlockDuration / 1000) : 2.4
  property real t: total
  property string mode: "unlock"
  property string playedHandoff: ""
  property bool gold: false
  readonly property bool calm: Theme.calm

  readonly property string symbolId: s.symbolChoice
  readonly property string groupLabel: {
    if (symbolId === "shuffle") return "SHUFFLE · A NEW SYMBOL EVERY UNLOCK"
    for (var i = 0; i < s.symbolGroups.length; i++)
      if (s.symbolGroups[i].ids.indexOf(symbolId) >= 0) return s.symbolGroups[i].label + " · UNLOCK SYMBOL"
    return "YOURS · UNLOCK SYMBOL"
  }
  readonly property string person: s.name.trim() || s.suggestedName || "friend"
  readonly property string statusWord: (s.brand.trim() ? s.brand.trim().toUpperCase() : "SYSTEM") + " ONLINE"
  readonly property string tod: {
    var h = new Date().getHours()
    return h >= 5 && h < 12 ? "morning" : h >= 12 && h < 17 ? "afternoon" : "evening"
  }
  readonly property string telemetry: ["BATTERY 30%"].concat(s.weather ? ["50° CLEAR"] : []).concat(["2 UPDATES"]).join(" · ")
  readonly property var handoffIds: s.handoffs.map(function(h) { return h.id }).filter(function(id) { return id !== "shuffle" })
  function handoffLabel(id) {
    var h = s.handoffs.filter(function(x) { return x.id === id })[0]
    return h ? h.label : id
  }

  // ---- The timeline. Unlock: symbol 0.08–0.6, halo and ring, then the
  // status types from 0.9 and the greeting follows. Transition: the logo
  // holds 0.3 s, hands over, and the greeting comes in at 1.24.
  readonly property bool transition: mode === "transition"
  readonly property real handStart: 0.3
  readonly property real faceIn: transition
    ? Theme.outCubic(Theme.seg(t, handStart, handStart + 0.42))
    : Theme.outCubic(Theme.seg(t, 0.08, 0.6))
  readonly property real haloIn: transition ? Theme.seg(t, 0.64, 1.24) : Theme.seg(t, 0.22, 1.12)
  readonly property real ringT: transition ? Theme.seg(t, 0.76, 1.66) : Theme.seg(t, 0.36, 1.26)
  readonly property real greetStart: transition ? 1.24 : 0.9
  readonly property int typed: calm ? (t >= greetStart ? statusWord.length : 0)
    : Math.floor(Theme.seg(t, greetStart, greetStart + statusWord.length * 0.038) * statusWord.length)
  readonly property real line2: Theme.outCubic(Theme.seg(t, greetStart + 0.38, greetStart + 0.8))
  readonly property real line3: Theme.outCubic(Theme.seg(t, greetStart + 0.72, greetStart + 1.1))
  // The fall back when there is no effect: the logo recedes, the symbol grows.
  readonly property real logoOut: Theme.inCubic(Theme.seg(t, handStart, handStart + 0.52))
  readonly property real fallbackEmerge: transition && !effect ? 0.86 + 0.14 * Theme.outCubic(Theme.seg(t, handStart, handStart + 0.76)) : 1
  readonly property Item effect: handoffLoader.status === Loader.Ready && effectRunning ? handoffLoader.item : null
  property bool effectRunning: false

  function playUnlock() {
    if (!s.unlockAnimation) return
    finishTransition()
    mode = "unlock"
    if (s.sounds) s.playCue(s.legendary && gold ? "unlock-legendary" : "unlock-orbit")
    clock.restart()
  }
  function playTransition() {
    if (!s.unlockAnimation) return
    finishTransition()
    var id = s.handoff === "shuffle" ? handoffIds[Math.floor(Math.random() * handoffIds.length)] : s.handoff
    playedHandoff = id
    mode = "transition"
    handoffLoader.source = calm ? "" : Qt.resolvedUrl("../handoff/" + id + ".qml")
    if (s.sounds) s.playCue("unlock-short")
    clock.restart()
    handTimer.restart()
  }
  // The effect leaves its last frame up until reset; put everything back.
  function finishTransition() {
    handTimer.stop()
    effectRunning = false
    if (handoffLoader.item) { try { handoffLoader.item.reset() } catch (e) {} }
  }
  NumberAnimation {
    id: clock
    target: stage
    property: "t"
    from: 0
    to: stage.total
    duration: stage.total * 1000
    onFinished: if (stage.mode === "transition") { stage.finishTransition(); stage.mode = "unlock" }
  }
  Timer {
    id: handTimer
    interval: stage.handStart * 1000
    onTriggered: {
      var e = handoffLoader.status === Loader.Ready ? handoffLoader.item : null
      if (!e) return
      try { e.play(); stage.effectRunning = true } catch (err) { console.warn("hello-lock settings: handoff failed: " + err) }
    }
  }

  // Turning Rare gold on shows the gold version for a moment.
  Connections {
    target: stage.s
    function onLegendaryChanged() { if (stage.s.legendary) { stage.gold = true; goldTimer.restart() } else stage.gold = false }
  }
  Timer { id: goldTimer; interval: 1600; onTriggered: stage.gold = false }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    ScreenFrame {
      id: screen
      // Background on: the blurred backdrop stays behind the symbol. Off: it
      // is gone, and the symbol plays over the desktop with a dark halo.
      windowsBlur: stage.s.unlockBackdrop ? 1 : 0
      backdrop: stage.s.unlockBackdrop ? 1 : 0.25
      Behavior on backdrop { NumberAnimation { duration: Theme.slowMs; easing.type: Easing.OutCubic } }

      Item {
        id: artwork
        anchors.fill: parent
        readonly property real symbolCenterY: height / 2 - 22 - 56

        Glow {
          anchors.centerIn: symbol
          width: 420
          height: 360
          color: Theme.deepest
          strength: 0.75
          midStrength: 0.45
          mid: 0.5
          reach: 1
          opacity: stage.s.unlockBackdrop ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: Theme.slowMs; easing.type: Easing.OutCubic } }
        }

        // The pulse ring.
        Rectangle {
          anchors.centerIn: symbol
          width: 150
          height: 150
          radius: 75
          color: "transparent"
          border.width: 2
          border.color: stage.gold ? Theme.gold : Theme.accent
          visible: !stage.calm && stage.ringT > 0 && stage.ringT < 1
          opacity: 0.8 * (1 - stage.ringT)
          scale: 0.9 + stage.ringT
        }

        SymbolMark {
          id: symbol
          readonly property bool wide: stage.symbolId === "logo"
          width: wide ? 300 : 150
          height: 150
          x: (artwork.width - width) / 2
          y: artwork.symbolCenterY - height / 2
          source: stage.s.symbolFile(stage.symbolId)
          source2: stage.symbolId === "custom" && stage.s.customSymbol && stage.s.customSymbol.paths.length > 1 ? stage.s.customSymbol.paths[1] : ""
          tinted: stage.symbolId === "logo" ? stage.s.logoTinted : stage.symbolId === "custom" ? stage.s.tintLogo : true
          version: stage.s.previewVersion
          color: stage.gold ? Theme.gold : Theme.fg
          glowColor: stage.gold ? Theme.gold : Theme.accent
          Behavior on color { ColorAnimation { duration: Theme.slowMs; easing.type: Easing.OutCubic } }
          opacity: stage.faceIn
          scale: stage.calm ? 1 : 0.86 + 0.14 * stage.faceIn
          halo: Math.min(1, stage.haloIn / 0.55)
          haloScale: stage.calm ? 1 : stage.haloIn < 0.55 ? 0.7 + 0.42 * Theme.outCubic(stage.haloIn / 0.55) : 1.12 - 0.12 * Theme.outCubic((stage.haloIn - 0.55) / 0.45)
          // The handoff's entrance for the symbol, as the splash applies it.
          transform: [
            Scale {
              origin.x: symbol.width / 2
              origin.y: symbol.height / 2
              xScale: stage.fallbackEmerge * (stage.effect ? stage.effect.emergeScale : 1)
              yScale: xScale
            },
            Rotation {
              origin.x: symbol.width / 2
              origin.y: symbol.height / 2
              axis { x: 0; y: 1; z: 0 }
              angle: stage.effect ? stage.effect.emergeTurn : 0
            },
            Translate {
              x: stage.effect ? stage.effect.emergeX * symbol.height : 0
              y: stage.effect ? stage.effect.emergeY * symbol.height : 0
            }
          ]
        }

        // The lock screen's logo, as the transition starts from it.
        Item {
          id: logoRest
          readonly property real aspect: logoImage.aspect > 0 ? logoImage.aspect : 4
          width: Math.min(artwork.width * 0.62, artwork.height * 0.3 * aspect)
          height: width / aspect
          x: (artwork.width - width) / 2
          y: artwork.symbolCenterY - height / 2
          visible: stage.transition
          opacity: stage.effect ? 1 : stage.calm ? 1 - Theme.seg(stage.t, stage.handStart, stage.handStart + 0.42) : 1 - stage.logoOut
          scale: stage.effect || stage.calm ? 1 : 1 - 0.2 * stage.logoOut
          Item {
            id: logoComposite
            anchors.fill: parent
            LogoImage {
              id: logoImage
              anchors.fill: parent
              source: stage.s.logoPreview
              tinted: stage.s.logoTinted
              version: stage.s.previewVersion
            }
          }
        }
        ShaderEffectSource {
          id: logoTexture
          sourceItem: logoComposite
          hideSource: stage.effect !== null
          visible: false
        }
        Loader {
          id: handoffLoader
          anchors.fill: parent
          onStatusChanged: if (status === Loader.Error) console.warn("hello-lock settings: handoff failed to load; using the fall back")
          onLoaded: {
            var e = item
            try {
              e.source = logoTexture
              e.sourceRect = Qt.binding(function() { return Qt.rect(logoRest.x, logoRest.y, logoRest.width, logoRest.height) })
              e.accent = Qt.binding(function() { return Theme.accent })
              e.logoColor = Qt.binding(function() { return Theme.lockText })
              e.alertColor = Qt.binding(function() { return Theme.alert })
              e.backgroundColor = Qt.binding(function() { return Theme.ground })
            } catch (err) { console.warn("hello-lock settings: handoff setup failed: " + err) }
          }
        }

        // The greeting under the symbol (hidden when Greeting is off).
        Column {
          id: greeting
          anchors.horizontalCenter: parent.horizontalCenter
          y: artwork.symbolCenterY + 75 + 28
          spacing: 8
          opacity: stage.s.greeting ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
          MonoText {
            anchors.horizontalCenter: parent.horizontalCenter
            leftPadding: 5
            text: stage.statusWord.slice(0, stage.typed)
            color: stage.gold ? Theme.gold : Theme.accent
            tracking: 0.42
            opacity: stage.calm ? Theme.seg(stage.t, stage.greetStart, stage.greetStart + 0.2) : 1
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Good " + stage.tod + ", " + stage.person + "."
            color: Theme.lockText
            font.family: Theme.display
            font.weight: Font.Light
            font.pixelSize: 30
            textFormat: Text.PlainText
            opacity: stage.line2
            transform: Translate { y: stage.calm ? 0 : 8 * (1 - stage.line2) }
          }
          MonoText {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 4
            text: stage.telemetry
            tracking: 0.18
            size: 11
            color: Theme.a(Theme.muted, 0.85)
            opacity: stage.line3
          }
        }
        // Hovering the Greeting setting outlines what it controls.
        Item {
          x: greeting.x - 24
          y: greeting.y - 12
          width: Math.max(350, greeting.width + 48)
          height: greeting.height + 24
          opacity: stage.s.greetingRowHovered ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
          DashedBox {
            anchors.fill: parent
            fill: Theme.a(Theme.accent, 0.04)
          }
          Tag {
            y: -height / 2 - 2
            strong: true
            text: stage.s.greeting ? "GREETING · ON" : "GREETING · OFF"
          }
        }
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        label: stage.s.symbolLabel(stage.symbolId)
        detail: !stage.s.unlockAnimation ? "Instant unlock · no splash"
          : stage.s.unlockDuration > 0 ? "Up to " + (stage.s.unlockDuration / 1000).toFixed(1) + "s"
          : stage.transition && stage.calm ? "Crossfade"
          : stage.transition && stage.s.handoff === "shuffle" ? "Shuffle → " + stage.handoffLabel(stage.playedHandoff)
          : stage.handoffLabel(stage.s.handoff)
        progress: stage.t / stage.total
        time: stage.t.toFixed(1) + " / " + stage.total.toFixed(1) + "s"
        seekable: true
        fullScreen: true
        onSeek: function(f) { clock.stop(); stage.finishTransition(); stage.mode = "unlock"; stage.t = f * stage.total }
        onFullScreenClicked: stage.s.unlockPreviewRequested(stage.s.previewSymbol, stage.s.previewHandoff)
        ActionButton {
          kind: "primary"
          implicitHeight: 34
          icon: Icons.play
          iconFilled: true
          text: "Play unlock"
          enabled: stage.s.unlockAnimation
          onClicked: stage.playUnlock()
        }
        ActionButton {
          implicitHeight: 34
          icon: Icons.shuffle
          text: "Play transition"
          enabled: stage.s.unlockAnimation
          onClicked: stage.playTransition()
        }
      }
    }

    Placard {
      title: stage.s.symbolLabel(stage.symbolId)
      subtitle: stage.groupLabel
      legend: [
        { label: "RARE GOLD", value: stage.s.legendary ? "1 in 50 unlocks" : "Off" },
        { label: "GREETING", value: stage.s.greeting ? "Shown" : "Symbol only", lit: stage.s.greetingRowHovered },
        { label: "BACKGROUND", value: stage.s.unlockBackdrop ? "Blurred backdrop" : "Over your desktop" }
      ]
    }
  }
}
