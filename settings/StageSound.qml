import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "Icons.js" as Icons
import "SoundPeaks.js" as Peaks

// 06 · Sound: every cue on one desk. The unlock cue (Coin) is drawn large with
// the moments of the animation its hits land on; each row plays its cue
// through the sound helper (one process per click) while a playhead runs
// over waveforms precomputed by sounds/peaks.py. The meter follows the volume.
Item {
  id: stage
  property Item s: null
  readonly property real axis: 1.5
  readonly property var markers: [
    { key: "BLIP", t: 0.30, turn: 0.14 },
    { key: "SETTLE", t: 0.47, turn: 0.62 },
    { key: "RING", t: 1.00, turn: 1 }
  ]
  readonly property var families: ["pulse", "phase", "flux", "grain", "drift", "circuit"]
  // The typing patch a play uses: the chosen one, or a fresh pick for Shuffle.
  property string shuffled: "pulse"
  readonly property string family: families.indexOf(s.typingSound) >= 0 ? s.typingSound : shuffled
  readonly property var rows: [
    { id: "lock", title: "Lock", hint: "Lands as the power-down ends", file: "lock", heading: "LOCK CUE", tag: "Lock" },
    { id: "typing", title: "Typing", hint: "One pulse per keystroke · " + typingName, file: "type-" + family + "-1", heading: "TYPING CUE", tag: cap(family) },
    { id: "unlock", title: "Unlock", hint: "Follows the unlock animation · Coin", file: "unlock-coin", heading: "UNLOCK CUE", tag: "Coin" },
    { id: "wrong", title: "Wrong password", hint: "A low two-step fall", file: "error", heading: "WRONG PASSWORD CUE", tag: "Fall" }
  ]
  readonly property string typingName: s.typingSounds.filter(function(x) { return x.id === s.typingSound })[0].label
  function cap(w) { return w.charAt(0).toUpperCase() + w.slice(1) }
  function rowFor(id) { return rows.filter(function(r) { return r.id === id })[0] }

  // ---- Playback. The audio itself is a detached helper process; the desk
  // runs its own clock alongside it.
  property string playing: ""
  property string selected: "unlock"
  property real t: 0.47
  property bool chain: false
  property int chainIndex: 0
  readonly property real duration: playing ? Peaks.cues[rowFor(playing).file].duration : 1.5
  readonly property real heroT: playing === "" ? 0.47 : t
  readonly property bool heroCoin: playing === "" || playing === "unlock"

  function play(id) {
    if (!s.sounds) return
    if (id === "typing" && s.typingSound === "off") return
    if (id === "typing" && s.typingSound === "shuffle") shuffled = families[Math.floor(Math.random() * families.length)]
    clock.stop()
    selected = id
    playing = id
    t = 0
    s.playCue(rowFor(id).file)
    clock.duration = Math.round(duration * 1000)
    clock.restart()
  }
  function stop() {
    chain = false
    gap.stop()
    clock.stop()
    playing = ""
  }
  function playAll() {
    if (chain) { stop(); return }
    chain = true
    chainIndex = 0
    play("lock")
  }
  readonly property var chainOrder: s.typingSound === "off" ? ["lock", "unlock", "wrong"] : ["lock", "typing", "unlock", "wrong"]
  NumberAnimation {
    id: clock
    target: stage
    property: "t"
    from: 0
    to: stage.duration
    onFinished: {
      stage.playing = ""
      if (stage.chain && stage.chainIndex + 1 < stage.chainOrder.length) gap.restart()
      else stage.chain = false
    }
  }
  Timer {
    id: gap
    interval: 280
    onTriggered: { stage.chainIndex += 1; stage.play(stage.chainOrder[stage.chainIndex]) }
  }
  // The level: the volume at rest, the playing cue's envelope while it plays.
  readonly property real level: {
    if (!playing) return s.volume
    var peaks = Peaks.cues[rowFor(playing).file].peaks
    var i = Math.min(peaks.length - 1, Math.floor(t / duration * peaks.length))
    return s.volume * (0.25 + 0.75 * peaks[Math.max(0, i)])
  }

  // Bars as one path: 2 px wide every `pitch` px, centred on `mid`.
  function wavePath(peaks, pitch, maxHeight, mid) {
    var d = ""
    for (var i = 0; i < peaks.length; i++) {
      var h = Math.max(1, Math.round(peaks[i] * maxHeight))
      d += "M" + (i * pitch).toFixed(1) + " " + (mid - h / 2).toFixed(1) + "h2v" + h + "h-2z"
    }
    return d
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    Item {
      id: desk
      width: 758
      height: 592
      opacity: stage.s.sounds ? 1 : 0.45
      Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
      RectangularShadow {
        anchors.fill: parent
        offset.y: 40
        blur: 90
        radius: 10
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.65 : 0.22)
      }
      Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.deep
        border.width: 1
        border.color: Theme.a(Theme.line, 0.9)
        clip: true
        Glow { x: -0.08 * parent.width; y: -0.33 * parent.height; width: 0.76 * parent.width; height: 1.1 * parent.height; color: Theme.line; strength: 0.4; midStrength: 0.15; mid: 0.4; reach: 0.7 }
        Glow { x: 0.27 * parent.width; y: -0.25 * parent.height; width: 0.46 * parent.width; height: 1.1 * parent.height; strength: 0.05; midStrength: 0.02; mid: 0.4; reach: 0.7 }
      }

      Column {
        x: 28
        y: 24
        width: 702
        spacing: 14

        // The large waveform's header.
        Item {
          width: parent.width
          height: 16
          Row {
            spacing: 10
            MonoText {
              text: stage.heroCoin ? "UNLOCK CUE" : stage.rowFor(stage.playing).heading
              tracking: 0.2
              color: Theme.fg
            }
            UiText {
              text: stage.heroCoin ? "Coin · every hit lands on a moment of the animation"
                : stage.rowFor(stage.playing).hint
              color: Theme.muted
              font.pixelSize: 12
            }
          }
          MonoText {
            anchors.right: parent.right
            text: (stage.heroCoin ? 1.5 : stage.duration).toFixed(2) + " S"
            tracking: 0.14
            size: 11
          }
        }

        Item {
          id: wave
          width: parent.width
          height: 242
          readonly property real playX: 1 + Math.min(stage.heroT, stage.axis) / stage.axis * 700

          Rectangle {
            y: 22
            width: parent.width
            height: 126
            radius: 8
            color: Theme.a(Theme.deepest, 0.6)
            border.width: 1
            border.color: Theme.a(Theme.line, 0.35)
          }
          // The coin cue: dim, with the part played so far in the accent.
          Item {
            y: 25
            width: 700
            height: 120
            opacity: stage.heroCoin ? 1 : 0.35
            Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
            WaveShape {
              anchors.fill: parent
              path: stage.wavePath(Peaks.cues["unlock-coin"].hero, 4, 112, 60)
              color: Theme.a(Theme.accent, 0.3)
            }
            Item {
              width: stage.heroCoin ? wave.playX - 1 : 0
              height: parent.height
              clip: true
              WaveShape {
                width: 700
                height: 120
                path: stage.wavePath(Peaks.cues["unlock-coin"].hero, 4, 112, 60)
                color: Theme.accent
              }
            }
          }
          // Ruler.
          Item {
            y: 154
            width: parent.width
            height: 14
            Repeater {
              model: 7
              Rectangle {
                required property int index
                x: 1 + index * 700 / 6
                width: 1
                height: index === 0 || index === 6 ? 6 : 3
                color: Theme.a(Theme.muted, 0.5)
              }
            }
            MonoText { x: 4; y: 2; text: "0"; size: 10 }
            MonoText { anchors.right: parent.right; anchors.rightMargin: 4; y: 2; text: "1.5s"; size: 10 }
          }
          // What is on screen when each hit lands.
          Repeater {
            model: stage.markers
            Item {
              id: marker
              required property var modelData
              readonly property bool lit: stage.heroCoin && stage.heroT >= modelData.t
              x: 1 + modelData.t / stage.axis * 700
              height: parent.height
              Rectangle {
                y: 16
                width: 1
                height: 170
                color: marker.lit ? Theme.accent : Theme.a(Theme.muted, 0.4)
                Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
              }
              Rectangle {
                x: -24
                y: -1
                width: 48
                height: 16
                radius: 4
                color: marker.lit && marker.modelData.key === "SETTLE" ? Theme.accent : "transparent"
                MonoText {
                  anchors.centerIn: parent
                  text: marker.modelData.t.toFixed(2) + "s"
                  tracking: 0.06
                  size: 11
                  color: marker.lit && marker.modelData.key === "SETTLE" ? Theme.deepest : marker.lit ? Theme.accent : Theme.fg
                }
              }
              Rectangle {
                x: -18
                y: 186
                width: 36
                height: 36
                radius: 8
                color: marker.lit ? Theme.a(Theme.accent, 0.08) : Theme.deepest
                border.width: 1
                border.color: marker.lit ? Theme.accent : Theme.a(Theme.line, 0.6)
                Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
                SymbolMark {
                  anchors.centerIn: parent
                  width: 22
                  height: 22
                  halo: 0
                  source: stage.s.symbolFile(stage.s.symbolChoice)
                  tinted: stage.s.symbolChoice === "logo" ? stage.s.logoTinted : stage.s.symbolChoice === "custom" ? stage.s.tintLogo : true
                  color: marker.lit ? Theme.accent : Theme.muted
                  version: stage.s.previewVersion
                  transform: Scale { origin.x: 11; xScale: marker.modelData.turn }
                }
              }
              MonoText {
                x: -40
                y: 228
                width: 80
                horizontalAlignment: Text.AlignHCenter
                text: marker.modelData.key
                tracking: 0.16
                size: 10
                color: marker.lit ? Theme.accent : Theme.muted
              }
            }
          }
          // The playhead while a cue plays.
          Rectangle {
            visible: stage.playing !== ""
            x: wave.playX
            y: 16
            width: 1
            height: 136
            color: Theme.fg
            opacity: 0.8
          }
          Column {
            y: 192
            spacing: 3
            MonoText { text: "ON SCREEN"; tracking: 0.16; size: 10 }
            UiText { text: stage.s.symbolLabel(stage.s.symbolChoice) + ", mid-spin"; color: Theme.muted; font.pixelSize: 11 }
          }
        }

        // One row per cue, and the level meter.
        Row {
          topPadding: 6
          spacing: 20
          Column {
            width: 626
            spacing: 4
            Repeater {
              model: stage.rows
              Rectangle {
                id: cueRow
                required property var modelData
                readonly property bool active: stage.playing === modelData.id
                readonly property bool chosen: stage.selected === modelData.id
                readonly property bool off: modelData.id === "typing" && stage.s.typingSound === "off"
                readonly property var cue: Peaks.cues[modelData.file]
                width: 626
                height: 44
                radius: 10
                color: chosen ? Theme.a(Theme.line, 0.34) : rowMouse.containsMouse ? Theme.a(Theme.line, 0.18) : "transparent"
                border.width: chosen ? 1 : 0
                border.color: Theme.a(Theme.accent, 0.22)
                opacity: off ? 0.45 : 1
                Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
                Rectangle {
                  x: 10
                  anchors.verticalCenter: parent.verticalCenter
                  width: 28
                  height: 28
                  radius: 14
                  color: cueRow.chosen ? Theme.a(Theme.accent, 0.14) : "transparent"
                  border.width: 1
                  border.color: cueRow.chosen ? Theme.a(Theme.accent, 0.7) : Theme.a(Theme.line, 0.95)
                  Glyph {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: cueRow.active ? 0 : 1
                    width: 10
                    height: 10
                    path: cueRow.active ? Icons.pause : Icons.play
                    filled: true
                    color: cueRow.chosen ? Theme.accent : Theme.fg
                  }
                }
                Column {
                  x: 50
                  anchors.verticalCenter: parent.verticalCenter
                  width: 236
                  spacing: 1
                  UiText { text: cueRow.modelData.title; font.weight: Font.Medium }
                  UiText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: cueRow.off ? "Off" : cueRow.modelData.hint
                    color: Theme.muted
                    font.pixelSize: 12
                  }
                }
                Item {
                  x: 300
                  anchors.verticalCenter: parent.verticalCenter
                  width: 158
                  height: 26
                  WaveShape {
                    anchors.fill: parent
                    path: stage.wavePath(cueRow.cue.peaks, 4, 26, 13)
                    color: cueRow.active ? Theme.a(Theme.accent, 0.3) : cueRow.chosen ? Theme.accent : Theme.a(Theme.muted, 0.75)
                  }
                  Item {
                    visible: cueRow.active
                    width: 158 * Math.min(1, stage.t / stage.duration)
                    height: parent.height
                    clip: true
                    WaveShape {
                      width: 158
                      height: 26
                      path: stage.wavePath(cueRow.cue.peaks, 4, 26, 13)
                      color: Theme.accent
                    }
                  }
                  Rectangle {
                    visible: cueRow.active
                    x: 157 * Math.min(1, stage.t / stage.duration)
                    y: -3
                    width: 1
                    height: 32
                    color: Theme.fg
                  }
                }
                MonoText {
                  anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                  text: cueRow.cue.duration.toFixed(2) + "s"
                  tracking: 0.06
                  size: 11
                  color: cueRow.chosen ? Theme.fg : Theme.muted
                }
                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  enabled: stage.s.sounds && !cueRow.off
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (cueRow.active) stage.stop()
                    else { stage.chain = false; gap.stop(); stage.play(cueRow.modelData.id) }
                  }
                }
              }
            }
          }
          // Level: the volume, or what is playing.
          Item {
            width: 56
            height: 188
            Rectangle { width: 1; height: parent.height; color: Theme.a(Theme.line, 0.35) }
            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: 1
              y: 4
              spacing: 8
              MonoText { anchors.horizontalCenter: parent.horizontalCenter; text: "LEVEL"; tracking: 0.2; size: 10 }
              Row {
                id: meter
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3
                readonly property int lit: Math.round(Math.max(0, Math.min(1, stage.level)) * 14)
                Repeater {
                  model: 2
                  Column {
                    spacing: 3
                    Repeater {
                      model: 14
                      Rectangle {
                        required property int index
                        // Lit from the bottom; brightest at the top of the lit run.
                        readonly property int fromTop: index - (14 - meter.lit)
                        width: 8
                        height: 7
                        radius: 1
                        color: fromTop < 0 ? Theme.a(Theme.line, 0.6) : Theme.a(Theme.fg, 1 - 0.7 * fromTop / Math.max(1, meter.lit - 1))
                      }
                    }
                  }
                }
              }
              MonoText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(stage.s.volume * 100) + "%"
                color: Theme.fg
                tracking: 0.04
              }
            }
          }
        }
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        label: stage.playing ? stage.rowFor(stage.playing).tag : "Coin"
        detail: stage.playing ? stage.rowFor(stage.playing).title : "Unlock"
        progress: stage.playing ? Math.min(1, stage.t / stage.duration) : 0.47 / 1.5
        time: (stage.playing ? stage.t : 0.47).toFixed(2) + " / " + stage.duration.toFixed(2) + "s"
        ActionButton {
          kind: "primary"
          implicitHeight: 34
          icon: stage.chain ? Icons.stop : Icons.play
          iconFilled: true
          text: stage.chain ? "Stop" : "Play all cues"
          enabled: stage.s.sounds
          onClicked: stage.playAll()
        }
        ActionButton {
          implicitHeight: 34
          icon: Icons.keyboard
          text: "Play typing"
          enabled: stage.s.sounds && stage.s.typingSound !== "off"
          onClicked: { stage.chain = false; gap.stop(); stage.play("typing") }
        }
      }
    }

    Placard {
      title: stage.playing && stage.playing !== "unlock" ? stage.rowFor(stage.playing).tag : "Coin"
      subtitle: stage.playing && stage.playing !== "unlock" ? stage.rowFor(stage.playing).heading : "UNLOCK CUE · THREE HITS"
      legend: [
        { label: "SOUNDS", value: stage.s.sounds ? "On · follows mute" : "Off" },
        { label: "TYPING", value: stage.typingName },
        { label: "QUIET HOURS", value: stage.s.quietHours ? stage.s.quietStart + ":00–" + stage.s.quietEnd + ":00" : "Off" }
      ]
    }
  }

  // Waveform bars as one filled path, in pixels (crisp, axis-aligned).
  component WaveShape: Shape {
    id: waveShape
    property string path: ""
    property color color: Theme.accent
    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillColor: waveShape.color
      PathSvg { path: waveShape.path }
    }
  }
}
