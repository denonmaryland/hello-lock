import QtQuick
import "Icons.js" as Icons

// The icon rail: Hello Lock's mark, the eight sections (line icon and a
// label; the current one raised with an accent edge bar that slides between
// them) and the version at the foot.
Rectangle {
  id: rail
  property var sections: []
  property int current: 0
  property string mark: ""
  property string version: ""
  signal picked(int index)
  readonly property var icons: ({
    you: Icons.user, logo: Icons.logo, unlock: Icons.unlock, typing: Icons.keyboard,
    lock: Icons.monitor, sound: Icons.sound, presets: Icons.layers, privacy: Icons.cloud
  })
  width: 76
  color: Theme.rail

  Rectangle {
    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
    width: 1
    color: Theme.a(Theme.line, 0.55)
  }

  Rectangle {
    id: brand
    anchors.horizontalCenter: parent.horizontalCenter
    y: 20
    width: 36
    height: 36
    radius: 10
    color: Theme.ground
    border.width: 1
    border.color: Theme.a(Theme.line, 0.9)
    LogoImage {
      anchors.centerIn: parent
      width: 22
      height: 22
      opacity: 0.92
      source: rail.mark
      color: Theme.fg
    }
  }
  Rectangle {
    id: brandRule
    anchors.horizontalCenter: parent.horizontalCenter
    y: brand.y + brand.height + 14
    width: 28
    height: 1
    color: Theme.a(Theme.line, 0.8)
  }

  Column {
    id: nav
    x: 6
    y: brandRule.y + 1 + 10 + 6
    spacing: 4

    Repeater {
      model: rail.sections
      Rectangle {
        id: item
        required property var modelData
        required property int index
        readonly property bool active: rail.current === index
        width: 64
        height: 56
        radius: 10
        color: active ? Theme.a(Theme.accent, 0.09) : itemMouse.containsMouse ? Theme.a(Theme.line, 0.25) : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.a(Theme.accent, 0.7)
        scale: itemMouse.pressed ? Theme.pressScale : 1
        activeFocusOnTab: true
        Keys.onSpacePressed: rail.picked(index)
        Keys.onReturnPressed: rail.picked(index)
        Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }

        Column {
          anchors.centerIn: parent
          spacing: 5
          Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 20
            height: 20
            path: rail.icons[item.modelData.id] || ""
            color: item.active ? Theme.accent : Theme.muted
            Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
          }
          UiText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: item.modelData.label
            font.pixelSize: 10
            font.weight: item.active ? Font.DemiBold : Font.Medium
            color: item.active ? Theme.accent : Theme.muted
            Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
          }
        }
        MouseArea {
          id: itemMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: rail.picked(item.index)
        }
      }
    }
  }

  // One edge bar for the current section, sliding to it.
  Rectangle {
    x: 0
    y: nav.y + rail.current * 60 + 16
    width: 3
    height: 24
    radius: 2
    color: Theme.accent
    Behavior on y { enabled: !Theme.calm; NumberAnimation { duration: Theme.slowMs; easing.type: Easing.OutCubic } }
  }

  MonoText {
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
    text: rail.version ? "v" + rail.version : ""
    tracking: 0.08
    size: 11
    color: Theme.a(Theme.muted, 0.7)
  }
}
