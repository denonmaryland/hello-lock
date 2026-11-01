import QtQuick
import QtQuick.Effects

// The stage's framed screen: a desktop with three ghost windows under a dark
// backdrop, at the design's 758×474. `lockStyle` blurs the windows and
// deepens the backdrop like the lock screen's blurred wallpaper; `bar` shows
// the desktop's top bar. Content goes on top, filling the screen.
Item {
  id: frame
  property bool bar: true
  property bool lockStyle: false
  property real windowsBlur: lockStyle ? 1 : 0
  property real windowsOpacity: 1
  property real backdrop: 1
  property string clock: Qt.formatTime(new Date(), "hh:mm")
  default property alias content: contentLayer.data
  readonly property alias surface: screen
  width: 758
  height: 474

  RectangularShadow {
    anchors.fill: screen
    offset.y: 40
    blur: 90
    radius: screen.radius
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.65 : 0.22)
  }
  Glow {
    anchors.centerIn: screen
    width: screen.width + 240
    height: screen.height + 240
    strength: 0.05
    midStrength: 0.03
    mid: 0.6
    reach: 1
  }

  // Rounded corners for the wallpaper: a mask, so its glows don't square off
  // the corners. It is static, so the masked layer renders once. Content on
  // top is only clipped to the rectangle.
  Rectangle {
    id: screenMask
    anchors.fill: screen
    radius: screen.radius
    visible: false
    layer.enabled: true
  }

  Rectangle {
    id: screen
    anchors.fill: parent
    radius: 10
    color: Theme.deep
    clip: true

    Item {
      id: wallpaper
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: screenMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
        autoPaddingEnabled: false
      }

      // Wallpaper light: a lifted corner, a faint alert warmth, an accent haze.
      Glow { x: -0.33 * parent.width; y: -0.3 * parent.height; width: 1.1 * parent.width; height: 1.2 * parent.height; color: Theme.line; strength: 0.55; midStrength: 0.25; mid: 0.4; reach: 0.7 }
      Glow { x: 0.32 * parent.width; y: 0.23 * parent.height; width: parent.width; height: 1.1 * parent.height; color: Theme.alert; strength: 0.07; midStrength: 0.03; mid: 0.4; reach: 0.7 }
      Glow { x: 0.25 * parent.width; y: -0.32 * parent.height; width: 0.9 * parent.width; height: parent.height; strength: 0.06; midStrength: 0.02; mid: 0.4; reach: 0.7 }

      Item {
        id: windows
        anchors.fill: parent
        readonly property real sx: frame.width / 758
        readonly property real sy: frame.height / 474
        opacity: frame.windowsOpacity
        layer.enabled: frame.windowsBlur > 0
        layer.effect: MultiEffect { blurEnabled: true; blur: frame.windowsBlur * 0.5; blurMax: 24; autoPaddingEnabled: false }
        Rectangle { x: 34 * windows.sx; y: 40 * windows.sy; width: 330 * windows.sx; height: 250 * windows.sy; radius: 6; color: Theme.a(Theme.ground, 0.55); border.width: 1; border.color: Theme.a(Theme.line, 0.55) }
        Rectangle { x: 380 * windows.sx; y: 40 * windows.sy; width: 344 * windows.sx; height: 400 * windows.sy; radius: 6; color: Theme.a(Theme.ground, 0.45); border.width: 1; border.color: Theme.a(Theme.line, 0.5) }
        Rectangle { x: 34 * windows.sx; y: 304 * windows.sy; width: 330 * windows.sx; height: 136 * windows.sy; radius: 6; color: Theme.a(Theme.ground, 0.5); border.width: 1; border.color: Theme.a(Theme.line, 0.5) }
      }

      // The backdrop: a dark wash, heaviest in the middle where content sits.
      Glow {
        anchors.centerIn: parent
        width: parent.width * (frame.lockStyle ? 1.2 : 0.96)
        height: parent.height * (frame.lockStyle ? 1.2 : 1.16)
        opacity: frame.backdrop
        color: Theme.deepest
        strength: frame.lockStyle ? 0.94 : 0.82
        mid: 0.6
        midStrength: frame.lockStyle ? 0.85 : 0.55
        reach: 1
        outer: frame.lockStyle ? 0.75 : 0.35
        bleed: 30
      }

      Rectangle {
        visible: frame.bar
        width: parent.width
        height: 18
        color: Theme.a(Theme.deepest, 0.5)
        Row {
          x: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 5; height: 5; radius: 3; color: Theme.a(Theme.fg, 0.5) }
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Theme.a(Theme.muted, 0.4) }
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Theme.a(Theme.muted, 0.4) }
        }
        MonoText {
          anchors.centerIn: parent
          text: frame.clock
          size: 8
          color: Theme.a(Theme.muted, 0.6)
        }
        Rectangle { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } width: 20; height: 5; radius: 2; color: Theme.a(Theme.muted, 0.3) }
      }
    }

    Item {
      id: contentLayer
      anchors.fill: parent
    }
  }
  Rectangle {
    anchors.fill: screen
    radius: screen.radius
    color: "transparent"
    border.width: 1
    border.color: Theme.a(Theme.line, 0.9)
  }
}
