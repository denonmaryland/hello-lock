import QtQuick
import QtQuick.Effects
import "Icons.js" as Icons

// 07 · Presets: the saved presets as a carousel of small lock screens, the
// one in use lit in the middle with the symbol it unlocks with. Using a
// preset (in the list) turns the carousel to it.
Item {
  id: stage
  property Item s: null
  readonly property var items: s.brandingPresets
  readonly property int count: items.length
  readonly property int current: {
    for (var i = 0; i < items.length; i++) if (items[i].id === s.selectedPreset) return i
    return -1
  }
  // Without a preset in use, the middle card is the current branding.
  readonly property var center: current >= 0 ? look(items[current].branding) : currentLook
  readonly property var currentLook: ({
    logo: s.logoPreview, tinted: s.logoTinted,
    symbol: s.symbolFile(s.symbolChoice), symbol2: s.symbolChoice === "custom" && s.customSymbol && s.customSymbol.paths.length > 1 ? s.customSymbol.paths[1] : "",
    symbolTinted: s.symbolChoice === "logo" ? s.logoTinted : s.symbolChoice === "custom" ? s.tintLogo : true,
    symbolName: s.symbolLabel(s.symbolChoice),
    logoName: s.logoChoice === "wordmark" ? "Wordmark" : s.logoChoice === "image" ? "Image" : s.defaultLogoLabel,
    colors: s.logoTinted ? "Match theme" : "Own colors"
  })
  readonly property int prevIndex: count > 2 ? (current - 1 + count) % count : current < 0 && count > 1 ? count - 1 : -1
  readonly property int nextIndex: count > 1 ? (current + 1) % count : current < 0 && count === 1 ? 0 : -1
  readonly property string modeShort: s.presetMode === "cycle" ? "Cycle" : s.presetMode === "shuffle" ? "Shuffle" : "Keep current"

  function pad(n) { return (n < 10 ? "0" : "") + n }
  // What a preset's branding looks like (paths as Settings resolves them).
  function look(b) {
    b = b || {}
    var parts = Array.isArray(b.symbolParts) ? b.symbolParts : []
    var logo = typeof b.logo === "string" && b.logo ? s.expand(b.logo) : s.omarchyLogo
    var tinted = !b.logo || !!b.wordmarkText || b.tintLogo !== false
    var sym = typeof b.symbol === "string" ? b.symbol : ""
    var builtin = /^@[a-z0-9-]+$/.test(sym) ? sym.slice(1) : ""
    var symbol = parts.length ? s.expand(parts[0]) : builtin === "shuffle" ? s.pluginDir + "/symbols/omarchy.svg" : sym ? s.expand(sym) : logo
    return {
      logo: logo, tinted: tinted,
      symbol: symbol, symbol2: parts.length > 1 ? s.expand(parts[1]) : "",
      symbolTinted: builtin ? true : sym || parts.length ? b.tintLogo !== false : tinted,
      symbolName: builtin ? (builtin === "shuffle" ? "Shuffle" : s.symbolLabel(builtin)) : sym || parts.length ? "Custom" : "Its logo",
      logoName: b.wordmarkText ? "Wordmark" : b.logo ? "Image" : s.defaultLogoLabel,
      colors: b.wordmarkText || b.tintLogo !== false ? "Match theme" : "Own colors"
    }
  }

  // Turning: the middle card slides in from the side it came from.
  property int lastCurrent: current
  onCurrentChanged: {
    var dir = lastCurrent >= 0 && count > 0 && (lastCurrent - current + count) % count === 1 ? -1 : 1
    lastCurrent = current
    turn.dir = dir
    turn.restart()
  }
  ParallelAnimation {
    id: turn
    property int dir: 1
    NumberAnimation { target: centerCard; property: "shift"; from: Theme.calm ? 0 : turn.dir * 302; to: 0; duration: Theme.slowMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: centerCard; property: "opacity"; from: Theme.calm ? 0 : 0.6; to: 1; duration: Theme.slowMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: sides; property: "opacity"; from: 0; to: 1; duration: Theme.slowMs; easing.type: Easing.OutCubic }
  }

  // "Play unlock": the symbol box pulses.
  property real pulse: 0
  NumberAnimation { id: pulseAnim; target: stage; property: "pulse"; from: 0; to: 1; duration: 900 }
  function play() {
    if (s.sounds) s.playCue("unlock-orbit")
    pulseAnim.restart()
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    Item {
      width: 758
      height: 327

      Item {
        id: sides
        anchors.fill: parent
        SideCard { x: 0; index: stage.prevIndex; caption: stage.prevIndex >= 0 ? stage.pad(stage.prevIndex + 1) : "" }
        SideCard { x: 758 - 150; index: stage.nextIndex; caption: stage.nextIndex >= 0 ? stage.pad(stage.nextIndex + 1) + " · NEXT" : "" }
      }

      Item {
        id: centerCard
        property real shift: 0
        x: 164
        width: 430
        height: 327
        transform: [
          Translate { x: centerCard.shift },
          Scale { origin.x: 215; origin.y: 134; xScale: 1 - Math.abs(centerCard.shift) / 302 * (1 - 150 / 430); yScale: xScale }
        ]
        RectangularShadow {
          anchors.fill: screenCard
          offset.y: 40
          blur: 90
          radius: 10
          color: Qt.rgba(0, 0, 0, Theme.dark ? 0.65 : 0.22)
        }
        Rectangle {
          id: screenCard
          width: 430
          height: 269
          radius: 10
          color: Theme.deepest
          border.width: 1
          border.color: Theme.a(Theme.line, 0.9)
          clip: true
          Glow { anchors.centerIn: parent; width: 1.2 * parent.width; height: 1.1 * parent.height; strength: 0.08 + 0.12 * Math.sin(Math.PI * stage.pulse); midStrength: 0.03; mid: 0.5; reach: 0.7 }
          LockMock {
            anchors.fill: parent
            compact: true
            logoSource: stage.center.logo
            logoTinted: stage.center.tinted
            version: stage.s.previewVersion
            showClock: stage.s.clock
          }
        }
        Item {
          y: 269 + 14
          width: 430
          height: 44
          MonoText {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            text: stage.current >= 0 ? stage.pad(stage.current + 1) + " · IN USE" : "CURRENT BRANDING"
            color: Theme.accent
            tracking: 0.18
          }
          Row {
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            spacing: 10
            Column {
              anchors.verticalCenter: parent.verticalCenter
              MonoText { anchors.right: parent.right; text: "UNLOCKS"; tracking: 0.18; size: 10 }
              MonoText { anchors.right: parent.right; text: "WITH"; tracking: 0.18; size: 10 }
            }
            Rectangle {
              width: 44
              height: 44
              radius: 10
              color: Theme.a(Theme.accent, 0.12)
              border.width: 1
              border.color: Theme.accent
              RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                blur: 16 + 12 * Math.sin(Math.PI * stage.pulse)
                spread: Theme.calm ? 0 : 6 * Math.sin(Math.PI * stage.pulse)
                color: Theme.a(Theme.accent, 0.18 + 0.2 * Math.sin(Math.PI * stage.pulse))
                z: -1
              }
              SymbolMark {
                anchors.centerIn: parent
                width: 26
                height: 26
                halo: 0
                source: stage.center.symbol
                source2: stage.center.symbol2
                tinted: stage.center.symbolTinted
                color: Theme.accent
                version: stage.s.previewVersion
                opacity: stage.pulse > 0 && stage.pulse < 1 ? Theme.outCubic(Math.min(1, stage.pulse / 0.45)) : 1
                scale: Theme.calm || stage.pulse <= 0 || stage.pulse >= 1 ? 1 : 0.86 + 0.14 * Theme.outCubic(Math.min(1, stage.pulse / 0.45))
              }
            }
          }
        }
      }
    }

    Transport {
      anchors.horizontalCenter: parent.horizontalCenter
      scrubber: false
      label: stage.modeShort
      detail: "on each lock"
      time: stage.count ? Math.max(1, stage.current + 1) + " / " + stage.count : "0 / 0"
      ActionButton {
        kind: "primary"
        implicitHeight: 34
        icon: Icons.play
        iconFilled: true
        text: "Play unlock"
        onClicked: stage.play()
      }
      trailing: [
        Row {
          spacing: 4
          Repeater {
            model: Math.min(stage.count, 12)
            Rectangle {
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              width: index === stage.current ? 18 : 6
              height: 4
              radius: 2
              color: index === stage.current ? Theme.accent : Theme.line
              Behavior on width { enabled: !Theme.calm; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
          }
        }
      ]
    }

    Placard {
      title: stage.current >= 0 ? stage.items[stage.current].name : "Current branding"
      subtitle: stage.current >= 0 ? "PRESET " + stage.pad(stage.current + 1) + " OF " + stage.pad(stage.count) + " · IN USE"
        : stage.count ? "NO PRESET IN USE · CURRENT BRANDING" : "NO PRESETS YET · CURRENT BRANDING"
      legend: [
        { label: "LOGO", value: stage.center.logoName },
        { label: "SYMBOL", value: stage.center.symbolName },
        { label: "COLORS", value: stage.center.colors }
      ]
    }
  }

  // A neighbouring preset, small and dimmed.
  component SideCard: Item {
    id: side
    property int index: -1
    property string caption: ""
    readonly property var preset: index >= 0 ? stage.items[index] : null
    readonly property var lk: preset ? stage.look(preset.branding) : null
    visible: preset !== null
    y: 88
    width: 150
    height: 224
    opacity: 0.6
    Rectangle {
      width: 150
      height: 94
      radius: 8
      color: Theme.deepest
      border.width: 1
      border.color: Theme.a(Theme.line, 0.9)
      clip: true
      LockMock {
        anchors.fill: parent
        compact: true
        glow: 0
        logoSource: side.lk ? side.lk.logo : ""
        logoTinted: side.lk ? side.lk.tinted : true
        version: stage.s.previewVersion
        showClock: stage.s.clock
      }
    }
    Item {
      y: 94 + 10
      width: 150
      height: 30
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: 110
        spacing: 2
        MonoText { text: side.caption; tracking: 0.18; size: 9 }
        UiText { width: parent.width; elide: Text.ElideRight; text: side.preset ? side.preset.name : ""; font.pixelSize: 12 }
      }
      Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30
        radius: 7
        color: Theme.ground
        border.width: 1
        border.color: Theme.a(Theme.line, 0.7)
        SymbolMark {
          anchors.centerIn: parent
          width: 18
          height: 18
          halo: 0
          source: side.lk ? side.lk.symbol : ""
          source2: side.lk ? side.lk.symbol2 : ""
          tinted: side.lk ? side.lk.symbolTinted : true
          version: stage.s.previewVersion
        }
      }
    }
  }
}
