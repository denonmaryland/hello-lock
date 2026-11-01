import QtQuick
import "Icons.js" as Icons

// 01 · You: the greeting moment. The symbol settles, the status line types
// in, the greeting and a sample telemetry line follow; name, status word and
// birthday update live from the fields. Driven by one clock, `t`.
Item {
  id: stage
  property Item s: null
  readonly property real total: 2.4
  property real t: total
  readonly property bool calm: Theme.calm

  readonly property string person: s.name.trim() || s.suggestedName || "friend"
  readonly property string statusWord: (s.brand.trim() ? s.brand.trim().toUpperCase() : "SYSTEM") + " ONLINE"
  readonly property string tod: {
    var h = new Date().getHours()
    return h >= 5 && h < 12 ? "morning" : h >= 12 && h < 17 ? "afternoon" : "evening"
  }
  readonly property bool hasBirthday: s.birthMonth !== "" && s.birthDay !== "" && s.birthdayValid
  readonly property string birthdayLabel: hasBirthday
    ? ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][Number(s.birthMonth) - 1] + " " + Number(s.birthDay)
    : ""
  readonly property bool birthday: s.previewBirthday && hasBirthday
  // A sample of the real telemetry line (the weather part only with weather on).
  readonly property string telemetry: ["BATTERY 30%"].concat(s.weather ? ["50° CLEAR"] : []).concat(["2 UPDATES"]).join(" · ")

  // The timeline (seconds): symbol 0–0.52, status types from 0.56 at 42 ms a
  // letter, then the greeting and the telemetry.
  readonly property real typeStart: 0.56
  readonly property real typeEnd: typeStart + statusWord.length * 0.042
  readonly property real symbolIn: Theme.outCubic(Theme.seg(t, 0, 0.52))
  readonly property real haloIn: Theme.seg(t, 0.12, 1.02)
  readonly property int typed: calm ? (t >= typeStart ? statusWord.length : 0) : Math.floor(Theme.seg(t, typeStart, typeEnd) * statusWord.length)
  readonly property real greetIn: Theme.outCubic(Theme.seg(t, typeEnd, typeEnd + 0.26))
  readonly property real teleIn: Theme.outCubic(Theme.seg(t, typeEnd + 0.18, typeEnd + 0.42))
  readonly property string phase: t < typeStart ? "Symbol" : t < typeEnd ? "Typing status" : t < typeEnd + 0.42 ? "Greeting" : "Holding"

  function play() {
    if (s.sounds) s.playCue("unlock-orbit")
    clock.restart()
  }
  NumberAnimation { id: clock; target: stage; property: "t"; from: 0; to: stage.total; duration: stage.total * 1000 }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    ScreenFrame {
      id: screen
      Item {
        id: artwork
        anchors.fill: parent
        Column {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -22
          SymbolMark {
            anchors.horizontalCenter: parent.horizontalCenter
            source: stage.s.symbolFile(stage.s.symbolChoice)
            source2: stage.s.symbolChoice === "custom" && stage.s.customSymbol && stage.s.customSymbol.paths.length > 1 ? stage.s.customSymbol.paths[1] : ""
            tinted: stage.s.symbolChoice === "logo" ? stage.s.logoTinted : stage.s.symbolChoice === "custom" ? stage.s.tintLogo : true
            version: stage.s.previewVersion
            width: stage.s.symbolChoice === "logo" ? 300 : 150
            opacity: stage.symbolIn
            scale: stage.calm ? 1 : 0.86 + 0.14 * stage.symbolIn
            halo: Math.min(1, stage.haloIn / 0.55)
            haloScale: stage.calm ? 1 : stage.haloIn < 0.55 ? 0.7 + 0.42 * Theme.outCubic(stage.haloIn / 0.55) : 1.12 - 0.12 * Theme.outCubic((stage.haloIn - 0.55) / 0.45)
          }
          Item { width: 1; height: 28 }
          // Each line spans the screen, so its annotation can sit beside it.
          Item {
            width: artwork.width
            height: statusLine.height
            Row {
              id: statusLine
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 2
              leftPadding: 5
              MonoText {
                anchors.verticalCenter: parent.verticalCenter
                text: stage.statusWord.slice(0, stage.typed)
                color: Theme.accent
                tracking: 0.42
                opacity: stage.calm ? Theme.seg(stage.t, stage.typeStart, stage.typeStart + 0.2) : 1
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 13
                color: Theme.accent
                opacity: stage.t >= stage.typeStart ? 1 : 0
              }
            }
            Row {
              anchors { right: statusLine.left; rightMargin: 22; verticalCenter: statusLine.verticalCenter }
              spacing: 8
              Badge { anchors.verticalCenter: parent.verticalCenter; letter: "C" }
              MonoText { anchors.verticalCenter: parent.verticalCenter; text: "STATUS WORD"; tracking: 0.14; size: 11 }
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 84; height: 1; color: Theme.a(Theme.accent, 0.35) }
            }
          }
          Item { width: 1; height: 8 }
          Item {
            width: artwork.width
            height: greetingLine.height
            Row {
              id: greetingLine
              anchors.horizontalCenter: parent.horizontalCenter
              opacity: stage.greetIn
              transform: Translate { y: stage.calm ? 0 : 8 * (1 - stage.greetIn) }
              Text {
                text: stage.birthday ? "Happy birthday, " : "Good " + stage.tod + ", "
                color: Theme.lockText
                font.family: Theme.display
                font.weight: Font.Light
                font.pixelSize: 30
                textFormat: Text.PlainText
              }
              Text {
                text: stage.person
                color: Theme.lockText
                font.family: Theme.display
                font.weight: Font.Light
                font.pixelSize: 30
                textFormat: Text.PlainText
                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 3 }
                  height: 1
                  color: Theme.a(Theme.accent, 0.55)
                }
              }
              Text {
                text: "."
                color: Theme.lockText
                font.family: Theme.display
                font.weight: Font.Light
                font.pixelSize: 30
              }
            }
            Row {
              anchors { left: greetingLine.right; leftMargin: 18; verticalCenter: greetingLine.verticalCenter; verticalCenterOffset: 8 }
              spacing: 8
              opacity: stage.greetIn
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 52; height: 1; color: Theme.a(Theme.accent, 0.35) }
              Badge { anchors.verticalCenter: parent.verticalCenter; letter: "A" }
              MonoText { anchors.verticalCenter: parent.verticalCenter; text: "NAME"; tracking: 0.14; size: 11 }
            }
          }
          Item { width: 1; height: 12 }
          MonoText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stage.telemetry
            tracking: 0.18
            size: 11
            color: Theme.a(Theme.muted, 0.85)
            opacity: stage.teleIn
          }
        }
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        label: stage.birthday ? "Birthday" : stage.tod.charAt(0).toUpperCase() + stage.tod.slice(1)
        detail: stage.phase
        progress: stage.t / stage.total
        time: stage.t.toFixed(1) + " / " + stage.total.toFixed(1) + "s"
        seekable: true
        onSeek: function(f) { clock.stop(); stage.t = f * stage.total }
        ActionButton {
          kind: "primary"
          implicitHeight: 34
          icon: Icons.play
          iconFilled: true
          text: "Play unlock"
          onClicked: stage.play()
        }
        ActionButton {
          implicitHeight: 34
          icon: Icons.calendar
          text: stage.s.previewBirthday ? "Back to " + stage.tod : "Preview birthday"
          active: stage.s.previewBirthday
          alertTone: true
          enabled: stage.hasBirthday
          onClicked: stage.s.previewBirthday = !stage.s.previewBirthday
        }
      }
    }

    Placard {
      title: "Greeting"
      subtitle: "YOU · WHAT YOUR UNLOCK SAYS"
      legend: [
        { label: "A · NAME", value: stage.person },
        { label: "C · STATUS", value: stage.statusWord }
      ]
      Column {
        width: 196
        spacing: 7
        MonoText {
          text: stage.hasBirthday ? "B · ON " + stage.birthdayLabel : "B · NOT SET"
          tracking: 0.18
          size: 11
          color: stage.birthday ? Theme.accent : Theme.muted
        }
        Rectangle {
          width: 196
          height: 84
          radius: 6
          color: Theme.deep
          border.width: 1
          border.color: stage.birthday ? Theme.a(Theme.alert, 0.55) : Theme.a(Theme.line, 0.9)
          opacity: stage.hasBirthday ? 1 : 0.45
          Glow { anchors.fill: parent; strength: 0.08; midStrength: 0.03; reach: 0.7 }
          Column {
            anchors.centerIn: parent
            spacing: 5
            SymbolMark {
              anchors.horizontalCenter: parent.horizontalCenter
              width: stage.s.symbolChoice === "logo" ? 48 : 24
              height: 24
              halo: 0
              source: stage.s.symbolFile(stage.s.symbolChoice)
              tinted: stage.s.symbolChoice === "logo" ? stage.s.logoTinted : stage.s.symbolChoice === "custom" ? stage.s.tintLogo : true
              version: stage.s.previewVersion
            }
            MonoText {
              anchors.horizontalCenter: parent.horizontalCenter
              text: stage.statusWord
              tracking: 0.4
              size: 6
              color: Theme.accent
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Happy birthday, " + stage.person + "."
              color: Theme.lockText
              font.family: Theme.display
              font.weight: Font.Light
              font.pixelSize: 13
              textFormat: Text.PlainText
            }
          }
        }
      }
    }
  }
}
