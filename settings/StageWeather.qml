import QtQuick
import Quickshell
import Quickshell.Io
import "Icons.js" as Icons

// 08 · Weather: where the weather appears (one part of the unlock's telemetry
// line, outlined) and what the setting costs in privacy: at most one request
// to wttr.in every 30 minutes, nothing at all when it is off. The cache age
// is read from the local cache file's timestamp; this page makes no requests.
Item {
  id: stage
  property Item s: null
  readonly property real total: 1.3
  property real t: total
  readonly property bool on: s.weatherAvailable && s.weather
  readonly property string person: s.name.trim() || s.suggestedName || "friend"
  readonly property string statusWord: (s.brand.trim() ? s.brand.trim().toUpperCase() : "SYSTEM") + " ONLINE"
  readonly property string tod: {
    var h = new Date().getHours()
    return h >= 5 && h < 12 ? "morning" : h >= 12 && h < 17 ? "afternoon" : "evening"
  }
  // Minutes since the cache was written (-1: none).
  property int cacheAge: -1
  readonly property string cachePath: Quickshell.env("HELLO_STATUS_WEATHER_CACHE")
    || Quickshell.env("HOME") + "/.cache/hello-lock/weather.json"
  Process {
    running: true
    command: ["stat", "-c", "%Y", stage.cachePath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var seconds = parseInt(String(text || "").trim())
        stage.cacheAge = isFinite(seconds) ? Math.max(0, Math.round((Date.now() / 1000 - seconds) / 60)) : -1
      }
    }
  }

  readonly property real symbolIn: Theme.outCubic(Theme.seg(t, 0, 0.52))
  readonly property real statusIn: Theme.outCubic(Theme.seg(t, 0.38, 0.6))
  readonly property real helloIn: Theme.outCubic(Theme.seg(t, 0.6, 0.86))
  readonly property real teleIn: Theme.outCubic(Theme.seg(t, 0.82, 1.06))
  function play() {
    if (s.sounds) s.playCue("unlock-orbit")
    clock.restart()
  }
  NumberAnimation { id: clock; target: stage; property: "t"; from: 0; to: stage.total; duration: stage.total * 1000 }
  function setWeather(on) {
    if (!s.weatherAvailable || s.weather === on) return
    s.weather = on
    s.save({ weather: on })
  }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    ScreenFrame {
      Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -22
        SymbolMark {
          anchors.horizontalCenter: parent.horizontalCenter
          width: stage.s.symbolChoice === "logo" ? 300 : 150
          height: 150
          source: stage.s.symbolFile(stage.s.symbolChoice)
          source2: stage.s.symbolChoice === "custom" && stage.s.customSymbol && stage.s.customSymbol.paths.length > 1 ? stage.s.customSymbol.paths[1] : ""
          tinted: stage.s.symbolChoice === "logo" ? stage.s.logoTinted : stage.s.symbolChoice === "custom" ? stage.s.tintLogo : true
          version: stage.s.previewVersion
          opacity: 0.4 * stage.symbolIn
          scale: Theme.calm ? 1 : 0.86 + 0.14 * stage.symbolIn
        }
        Item { width: 1; height: 28 }
        MonoText {
          anchors.horizontalCenter: parent.horizontalCenter
          leftPadding: 5
          text: stage.statusWord
          color: Theme.accent
          tracking: 0.42
          opacity: 0.45 * stage.statusIn
        }
        Item { width: 1; height: 8 }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Good " + stage.tod + ", " + stage.person + "."
          color: Theme.lockText
          font.family: Theme.display
          font.weight: Font.Light
          font.pixelSize: 30
          textFormat: Text.PlainText
          opacity: 0.45 * stage.helloIn
          transform: Translate { y: Theme.calm ? 0 : 8 * (1 - stage.helloIn) }
        }
        Item { width: 1; height: 12 }
        // The telemetry line; the weather part is outlined, or gone when off.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 10
          opacity: stage.teleIn
          MonoText { anchors.verticalCenter: parent.verticalCenter; text: "BATTERY 30% ·"; tracking: 0.18; size: 11; color: Theme.a(Theme.muted, 0.5) }
          Item {
            id: segment
            anchors.verticalCenter: parent.verticalCenter
            width: stage.on ? weatherText.implicitWidth + 18 : 0
            height: 26
            clip: true
            opacity: stage.on ? 1 : 0
            Behavior on width { enabled: !Theme.calm; NumberAnimation { duration: stage.on ? 240 : 200; easing.type: stage.on ? Easing.OutCubic : Easing.InCubic } }
            Behavior on opacity { NumberAnimation { duration: stage.on ? 240 : 200; easing.type: stage.on ? Easing.OutCubic : Easing.InCubic } }
            DashedBox {
              width: weatherText.implicitWidth + 18
              height: parent.height
              radius: 6
              fill: Theme.a(Theme.accent, 0.06)
            }
            MonoText {
              id: weatherText
              x: 10
              anchors.verticalCenter: parent.verticalCenter
              text: "50° CLEAR"
              tracking: 0.18
              size: 11
              color: Theme.accent
            }
          }
          MonoText { anchors.verticalCenter: parent.verticalCenter; text: "· 2 UPDATES"; tracking: 0.18; size: 11; color: Theme.a(Theme.muted, 0.5) }
        }
        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: tag.width
          height: tag.height + 6
          Tag {
            id: tag
            y: 6
            strong: true
            text: stage.on ? "WEATHER · ON" : "WEATHER · OFF"
            opacity: stage.teleIn
          }
        }
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        scrubber: false
        label: stage.on ? (stage.cacheAge >= 0 ? "Cached" : "Not cached") : "Offline"
        detail: stage.on ? (stage.cacheAge >= 0 ? stage.cacheAge + " min ago" : "") : "no requests"
        time: stage.on ? (stage.cacheAge >= 0 && stage.cacheAge < 30 ? "NEXT ≥ " + (30 - stage.cacheAge) + " MIN" : "NEXT ON UNLOCK") : "NEXT · NEVER"
        ActionButton {
          kind: "primary"
          implicitHeight: 34
          icon: Icons.play
          iconFilled: true
          text: "Play unlock"
          onClicked: stage.play()
        }
        Segmented {
          enabled: stage.s.weatherAvailable
          width: 224
          itemPadding: 5
          proportional: true
          options: [{ value: "on", label: "With weather" }, { value: "off", label: "Offline" }]
          value: stage.on ? "on" : "off"
          onPicked: function(v) { stage.setWeather(v === "on") }
        }
      }
    }

    // The weather, and the one connection behind it.
    Item {
      width: 758
      height: 50
      Column {
        x: 4
        spacing: 4
        Text {
          text: stage.on ? "50° Clear" : "Offline"
          color: Theme.fg
          font.family: Theme.display
          font.pixelSize: 24
          font.weight: Font.Medium
        }
        MonoText { text: stage.on ? "WEATHER · VIA WTTR.IN" : "WEATHER · OFF"; tracking: 0.18; size: 11 }
      }
      Row {
        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
        spacing: 14
        Node { icon: Icons.monitor; title: "This machine"; note: stage.on ? "CACHE 30 MIN" : "NOTHING SENT" }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: 184
          spacing: 6
          MonoText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: stage.on ? "Cached for 30 min" : "No requests"
            tracking: 0.08
            size: 11
            color: stage.on ? Theme.fg : Theme.muted
          }
          Item {
            width: parent.width
            height: 10
            opacity: stage.on ? 1 : 0.3
            Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: Theme.accent }
            Row {
              x: 7
              anchors.verticalCenter: parent.verticalCenter
              spacing: 3
              Repeater {
                model: 25
                Rectangle { width: 4; height: 1; color: Theme.a(Theme.accent, 0.6) }
              }
            }
            Glyph {
              anchors { right: parent.right; verticalCenter: parent.verticalCenter }
              width: 8
              height: 10
              box: 10
              path: "M1 0l8 5-8 5z"
              filled: true
              color: Theme.accent
            }
          }
          MonoText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: stage.on ? "location + unit · your IP" : "nothing leaves this machine"
            tracking: 0.08
            size: 10
          }
        }
        Node { icon: Icons.cloud; title: "wttr.in"; note: "ONLY HOST"; opacity: stage.on ? 1 : 0.35 }
      }
    }
  }

  component Node: Row {
    id: node
    property string icon: ""
    property string title: ""
    property string note: ""
    spacing: 10
    Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    Rectangle {
      width: 36
      height: 36
      radius: 8
      color: Theme.ground
      border.width: 1
      border.color: Theme.line
      Glyph { anchors.centerIn: parent; width: 16; height: 16; path: node.icon; color: Theme.fg }
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 3
      UiText { text: node.title; font.weight: Font.Medium }
      MonoText { text: node.note; tracking: 0.14; size: 10 }
    }
  }
}
