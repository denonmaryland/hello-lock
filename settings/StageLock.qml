import QtQuick
import "Icons.js" as Icons

// 05 · Lock screen: the lock screen as configured (clock, Caps Lock badge),
// and "Play lock": a small CRT power-down storyboard. The desktop collapses
// to a line, then a dot, then the lock screen fades in. With the effect off,
// Calm motion or reduced motion it is a plain fade. Driven by one clock, `t`.
Item {
  id: stage
  property Item s: null
  readonly property real tLine: 0.26
  readonly property real tDot: 0.42
  readonly property real tLockIn: 0.70
  readonly property real tEnd: 0.98
  property real t: tEnd
  property bool caps: true
  readonly property bool fade: !s.powerDown || s.motion === "reduced" || Theme.calm
  readonly property var frames: [
    { key: "SCREEN", t: 0 }, { key: "LINE", t: tLine }, { key: "DOT", t: tDot }, { key: "LOCKED", t: tEnd }
  ]
  readonly property int frameIndex: t < tLine ? 0 : t < tDot ? 1 : t < tEnd ? 2 : 3
  readonly property string motionLabel: s.motion === "full" ? "Full" : s.motion === "reduced" ? "Calm" : "Automatic"

  // The storyboard at t.
  readonly property real lockIn: Theme.outCubic(Theme.seg(t, tLockIn, tEnd))
  readonly property real collapseY: Theme.inCubic(Theme.seg(t, 0, tLine))
  readonly property real collapseX: Theme.inCubic(Theme.seg(t, tLine, tDot))
  readonly property real dotOut: Theme.inCubic(Theme.seg(t, tDot, tLockIn))

  function play() {
    if (s.sounds) s.playCue("lock")
    clock.restart()
  }
  NumberAnimation { id: clock; target: stage; property: "t"; from: 0; to: stage.tEnd; duration: stage.tEnd * 1000 }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -6
    spacing: 22

    ScreenFrame {
      bar: false
      lockStyle: true

      LockMock {
        anchors.fill: parent
        anchors.bottomMargin: 30
        logoSource: stage.s.logoPreview
        logoTinted: stage.s.logoTinted
        version: stage.s.previewVersion
        showClock: stage.s.clock
        caps: stage.caps
        opacity: stage.lockIn
        scale: stage.fade ? 1 : 0.985 + 0.015 * stage.lockIn
      }

      // The power-down, drawn over the lock screen until it lands.
      Item {
        id: crt
        anchors.fill: parent
        visible: stage.t < stage.tEnd
        Rectangle {
          anchors.fill: parent
          color: "black"
          opacity: 1 - Theme.outCubic(Theme.seg(stage.t, stage.tLockIn + 0.1, stage.tEnd))
        }
        // The desktop being switched off.
        Item {
          id: tube
          anchors.fill: parent
          visible: stage.fade ? stage.t < stage.tDot : stage.t < stage.tDot
          opacity: stage.fade ? 1 - Theme.seg(stage.t, 0, stage.tDot) : 1
          transform: Scale {
            origin.x: tube.width / 2
            origin.y: tube.height / 2
            xScale: stage.fade ? 1 : 1 - stage.collapseX * (1 - 0.012)
            yScale: stage.fade ? 1 : 1 - stage.collapseY * (1 - 0.006)
          }
          Rectangle { anchors.fill: parent; color: Theme.deep }
          Rectangle { x: 34; y: 40; width: 330; height: 250; radius: 6; color: Theme.ground; border.width: 1; border.color: Theme.a(Theme.line, 0.55) }
          Rectangle { x: 380; y: 40; width: 344; height: 400; radius: 6; color: Theme.ground; border.width: 1; border.color: Theme.a(Theme.line, 0.5) }
          Rectangle { x: 34; y: 304; width: 330; height: 136; radius: 6; color: Theme.ground; border.width: 1; border.color: Theme.a(Theme.line, 0.5) }
          Rectangle { width: parent.width; height: 18; color: Theme.a(Theme.deepest, 0.5) }
          // It brightens as it collapses, like the tube's last light.
          Rectangle {
            anchors.fill: parent
            color: Theme.lockText
            opacity: stage.fade ? 0 : 0.85 * Theme.inCubic(Theme.seg(stage.t, 0.06, stage.tLine))
          }
        }
        Rectangle {
          visible: !stage.fade && stage.t >= stage.tLine * 0.92 && stage.t < stage.tDot
          anchors.centerIn: parent
          width: parent.width * (1 - stage.collapseX * (1 - 0.012))
          height: 2
          color: Theme.lockText
          opacity: Theme.seg(stage.t, stage.tLine * 0.92, stage.tLine)
          Rectangle { anchors.centerIn: parent; width: parent.width; height: 8; radius: 4; color: Theme.a(Theme.accent, 0.35) }
        }
        Item {
          visible: !stage.fade && stage.t >= stage.tDot && stage.t < stage.tLockIn
          anchors.centerIn: parent
          width: 10
          height: 10
          opacity: 1 - stage.dotOut
          scale: 1 - 0.5 * stage.dotOut
          Glow { anchors.centerIn: parent; width: 60; height: 60; color: Theme.accent; strength: 0.6; midStrength: 0.2; mid: 0.4; reach: 1 }
          Rectangle { anchors.fill: parent; radius: 5; color: Theme.lockText }
        }
      }

      Transport {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        label: stage.fade ? "Fade" : "Power-down"
        detail: stage.motionLabel
        progress: stage.t / stage.tEnd
        time: stage.t.toFixed(2) + " / " + stage.tEnd.toFixed(2) + "s"
        seekable: true
        onSeek: function(f) { clock.stop(); stage.t = f * stage.tEnd }
        ActionButton {
          kind: "primary"
          implicitHeight: 34
          icon: Icons.play
          iconFilled: true
          text: "Play lock"
          onClicked: stage.play()
        }
        ActionButton {
          implicitHeight: 34
          icon: Icons.caps
          text: "Caps Lock"
          active: stage.caps
          onClicked: stage.caps = !stage.caps
        }
      }
    }

    // What plays, and its four frames (click one to see it).
    Item {
      width: 758
      height: 86
      Column {
        x: 4
        width: 300
        spacing: 4
        Text {
          text: stage.fade ? "Fade" : "Power-down"
          color: Theme.fg
          font.family: Theme.display
          font.pixelSize: 24
          font.weight: Font.Medium
        }
        MonoText {
          text: stage.fade ? "PLAIN FADE · ON LOCK" : "CRT SHUT-OFF · ON LOCK"
          tracking: 0.18
          size: 11
        }
        Item { width: 1; height: 6 }
        UiText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: stage.s.powerDown ? "The screenshot lives in memory and is deleted right after." : "No screenshot is taken. The lock screen fades in."
          color: Theme.muted
          font.pixelSize: 12
        }
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: 4
        spacing: 10
        opacity: stage.fade ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
        Repeater {
          model: stage.frames
          Column {
            id: frameItem
            required property var modelData
            required property int index
            readonly property bool lit: stage.frameIndex === index
            spacing: 8
            Rectangle {
              width: 96
              height: 60
              radius: 6
              color: Theme.deepest
              border.width: 1
              border.color: frameItem.lit ? Theme.a(Theme.accent, 0.55) : Theme.a(Theme.line, 0.9)
              clip: true
              Behavior on border.color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
              Item {
                visible: frameItem.index === 0
                anchors.fill: parent
                anchors.margins: 6
                Rectangle { width: parent.width * 0.42; height: parent.height * 0.62; radius: 2; color: Theme.ground }
                Rectangle { x: parent.width * 0.47; width: parent.width * 0.53; height: parent.height; radius: 2; color: Theme.ground }
                Rectangle { y: parent.height * 0.7; width: parent.width * 0.42; height: parent.height * 0.3; radius: 2; color: Theme.ground }
              }
              Rectangle {
                visible: frameItem.index === 1
                anchors.centerIn: parent
                width: parent.width - 12
                height: 2
                color: Theme.lockText
              }
              Item {
                visible: frameItem.index === 2
                anchors.centerIn: parent
                width: 6
                height: 6
                Glow { anchors.centerIn: parent; width: 36; height: 36; strength: 0.5; midStrength: 0.15; mid: 0.4; reach: 1 }
                Rectangle { anchors.fill: parent; radius: 3; color: Theme.lockText }
              }
              Column {
                visible: frameItem.index === 3
                anchors.centerIn: parent
                spacing: 5
                LogoImage {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: 52
                  height: 14
                  source: stage.s.logoPreview
                  tinted: stage.s.logoTinted
                  version: stage.s.previewVersion
                }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 30; height: 4; radius: 2; color: "transparent"; border.width: 1; border.color: Theme.a(Theme.lockText, 0.4) }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { clock.stop(); stage.t = frameItem.modelData.t }
              }
            }
            Item {
              width: 96
              height: 12
              MonoText { text: frameItem.modelData.key; tracking: 0.16; size: 10; color: frameItem.lit ? Theme.accent : Theme.muted }
              MonoText { anchors.right: parent.right; text: frameItem.modelData.t.toFixed(2) + "s"; tracking: 0.06; size: 10; color: frameItem.lit ? Theme.accent : Theme.muted }
            }
          }
        }
      }
    }
  }
}
