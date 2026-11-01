import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "Icons.js" as Icons

// The stage's transport bar: play actions on the left, then what is
// playing, a scrubber (seekable when `seekable`), the time, and optionally a
// full-screen button that opens the real preview.
Item {
  id: transport
  default property alias actions: actionRow.data
  property string label: ""
  property string detail: ""
  property real progress: 0
  property string time: ""
  property bool scrubber: true
  property bool seekable: false
  property bool fullScreen: false
  property string fullScreenHint: "Full screen"
  property alias trailing: trailingRow.data
  signal seek(real fraction)
  signal fullScreenClicked()
  width: 650
  height: 46

  RectangularShadow {
    anchors.fill: bar
    offset.y: 12
    blur: 30
    radius: bar.radius
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.14)
  }
  Rectangle {
    id: bar
    anchors.fill: parent
    radius: 12
    color: Theme.a(Theme.deepest, 0.86)
    border.width: 1
    border.color: Theme.a(Theme.line, 0.85)

    RowLayout {
      anchors { fill: parent; leftMargin: 6; rightMargin: transport.fullScreen ? 6 : 16 }
      spacing: 12
      Row {
        id: actionRow
        Layout.alignment: Qt.AlignVCenter
        spacing: 8
      }
      Rectangle {
        visible: transport.label !== ""
        Layout.alignment: Qt.AlignVCenter
        width: 1
        height: 20
        color: Theme.a(Theme.line, 0.95)
      }
      // What is playing; the detail gives way first when space is short.
      Item {
        visible: transport.label !== ""
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: !transport.scrubber
        Layout.preferredWidth: labelText.implicitWidth + detailText.implicitWidth
        Layout.maximumWidth: transport.scrubber ? 230 : 10000
        Layout.minimumWidth: Math.min(labelText.implicitWidth, 120)
        implicitHeight: 16
        MonoText {
          id: labelText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width)
          elide: Text.ElideRight
          text: transport.label
          tracking: 0.06
          color: Theme.fg
        }
        MonoText {
          id: detailText
          visible: transport.detail !== ""
          x: labelText.width
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, Math.min(implicitWidth, parent.width - labelText.width))
          elide: Text.ElideRight
          text: " · " + transport.detail
          tracking: 0.06
        }
      }
      Item {
        id: scrub
        visible: transport.scrubber
        Layout.fillWidth: true
        Layout.minimumWidth: 36
        Layout.alignment: Qt.AlignVCenter
        height: 16
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 3; radius: 2; color: Theme.a(Theme.line, 0.95) }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Math.round(parent.width * transport.progress); height: 3; radius: 2; color: Theme.accent }
        Rectangle {
          x: transport.progress * (parent.width - width)
          anchors.verticalCenter: parent.verticalCenter
          width: 11
          height: 11
          radius: 6
          color: Theme.fg
          Rectangle { anchors.centerIn: parent; width: 17; height: 17; radius: 9; color: "transparent"; border.width: 3; border.color: Theme.a(Theme.accent, scrubMouse.pressed ? 0.45 : 0.25) }
        }
        MouseArea {
          id: scrubMouse
          enabled: transport.seekable
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          preventStealing: true
          function at(mx) { return Math.max(0, Math.min(1, (mx - 6) / scrub.width)) }
          onPressed: function(mouse) { transport.seek(at(mouse.x)) }
          onPositionChanged: function(mouse) { if (pressed) transport.seek(at(mouse.x)) }
        }
      }
      Item { visible: !transport.scrubber; Layout.fillWidth: true }
      Row {
        id: trailingRow
        Layout.alignment: Qt.AlignVCenter
        spacing: 8
      }
      MonoText {
        visible: transport.time !== ""
        Layout.alignment: Qt.AlignVCenter
        text: transport.time
        size: 11
      }
      ActionButton {
        visible: transport.fullScreen
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 34
        iconOnly: true
        kind: "ghost"
        icon: Icons.expand
        onClicked: transport.fullScreenClicked()
      }
    }
  }
}
