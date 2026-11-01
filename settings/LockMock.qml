import QtQuick
import "Icons.js" as Icons

// The lock screen in miniature, laid out like LockView: the clock near the
// top, the logo fitted into a box 72% wide and 30% tall just above the
// middle, the password pill below it. Sizes follow the mock's height;
// `compact` is for the small preset cards. `logo` replaces the plain logo
// (the typing page hosts the real effect there).
Item {
  id: mock
  property string logoSource: ""
  property string logoSource2: ""
  property bool logoTinted: true
  property int version: 0
  property bool showClock: true
  property bool showField: true
  property bool caps: false
  property int dots: 0
  property bool typing: false
  property bool compact: false
  property real glow: 0.08
  property Component logo: null
  readonly property real k: height / 474
  readonly property Item logoBox: box
  readonly property real logoAspect: probe.implicitHeight > 0 ? probe.implicitWidth / probe.implicitHeight : 4

  // Like the lock screen: 12-hour time and an upper-case date.
  readonly property var now: new Date()
  readonly property string timeString: {
    var h = now.getHours() % 12
    var m = now.getMinutes()
    return (h === 0 ? 12 : h) + ":" + (m < 10 ? "0" + m : m)
  }
  readonly property string dateString: Qt.formatDate(now, "dddd · MMMM d").toUpperCase()

  Image {
    id: probe
    visible: false
    source: Theme.fileUrl(mock.logoSource, mock.version)
    sourceSize.width: 128
    asynchronous: true
    cache: false
  }

  Column {
    visible: mock.showClock
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(mock.height * 0.15 - height / 2)
    spacing: Math.round(mock.height * (mock.compact ? 0.01 : 0.006))
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: mock.timeString
      color: Theme.lockText
      font.family: Theme.display
      font.weight: Font.Light
      font.pixelSize: Math.max(8, Math.round(mock.height * (mock.compact ? 0.14 : 0.095)))
      textFormat: Text.PlainText
    }
    MonoText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: mock.dateString
      color: Theme.a(Theme.accent, 0.85)
      size: Math.max(5, Math.round(mock.height * (mock.compact ? 0.032 : 0.019)))
      tracking: mock.compact ? 0.12 : 0.35
    }
  }

  Glow {
    anchors.centerIn: box
    width: box.width * 1.4
    height: box.height * 2.4
    color: Theme.lockText
    strength: mock.glow
    midStrength: mock.glow * 0.3
    mid: 0.5
    reach: 0.9
  }

  Item {
    id: box
    readonly property real boxWidth: mock.width * (mock.compact ? 0.52 : 0.72)
    readonly property real boxHeight: mock.height * (mock.compact ? 0.2 : 0.30)
    width: Math.min(boxWidth, boxHeight * mock.logoAspect)
    height: width / mock.logoAspect
    x: (mock.width - width) / 2
    y: mock.height * (mock.compact ? 0.47 : 0.44) - height / 2
    Loader {
      anchors.fill: parent
      sourceComponent: mock.logo || plainLogo
    }
  }
  Component {
    id: plainLogo
    LogoImage {
      source: mock.logoSource
      source2: mock.logoSource2
      tinted: mock.logoTinted
      version: mock.version
    }
  }

  Rectangle {
    id: field
    visible: mock.showField
    width: Math.round((mock.compact ? 132 : 176) * mock.k)
    height: Math.max(6, Math.round((mock.compact ? 24 : 26) * mock.k))
    x: (mock.width - width) / 2
    y: mock.height * (mock.compact ? 0.8 : 0.72) - height / 2
    radius: height / 2
    color: Theme.a(Theme.ground, 0.45)
    border.width: 1
    border.color: mock.typing || mock.dots > 0 ? Theme.a(Theme.accent, 0.7) : Theme.a(Theme.lockText, 0.22)
    Behavior on border.color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    UiText {
      visible: mock.dots === 0 && !mock.compact
      anchors.centerIn: parent
      text: "Enter Password"
      color: Theme.a(Theme.lockText, 0.45)
      font.pixelSize: Math.max(6, Math.round(10 * mock.k))
    }
    Row {
      anchors.centerIn: parent
      spacing: Math.max(2, Math.round(5 * mock.k))
      Repeater {
        model: Math.min(mock.dots, 14)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(2, Math.round(6 * mock.k))
          height: width
          radius: width / 2
          color: Theme.lockText
        }
      }
      Rectangle {
        visible: mock.typing
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: Math.round(11 * mock.k)
        color: Theme.lockText
      }
    }
  }
  Row {
    visible: mock.caps && mock.showField
    anchors { left: field.right; leftMargin: Math.round(9 * mock.k); verticalCenter: field.verticalCenter }
    spacing: 4
    opacity: visible ? 1 : 0
    Glyph {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(10 * mock.k); height: width
      path: Icons.caps
      strokeWidth: 2
      color: Theme.muted
    }
    MonoText {
      anchors.verticalCenter: parent.verticalCenter
      text: "CAPS"
      tracking: 0.14
      size: Math.max(6, Math.round(9 * mock.k))
    }
  }
}
