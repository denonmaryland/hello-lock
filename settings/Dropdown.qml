import QtQuick
import QtQuick.Effects
import "Icons.js" as Icons

// A dropdown for a few options ([{ value, label }]). The menu opens in
// `overlay` (an item above the window's content), just below the field.
Rectangle {
  id: dropdown
  property var options: []
  property string value: ""
  property Item overlay: null
  property bool open: false
  signal picked(string value)
  readonly property string label: {
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return options[i].label
    return value
  }

  implicitHeight: 38
  radius: 8
  color: Theme.deepest
  border.width: 1
  border.color: open || activeFocus ? Theme.accent : dropMouse.containsMouse ? Theme.mix(Theme.line, Theme.fg, 0.22) : Theme.a(Theme.line, 0.6)
  opacity: enabled ? 1 : 0.55
  activeFocusOnTab: true
  Keys.onSpacePressed: open = !open
  Keys.onReturnPressed: open = !open
  Keys.onDownPressed: open = true
  Behavior on border.color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }

  // Placed when it opens. The window watches `open` (Esc and outside clicks
  // close the menu first).
  onOpenChanged: {
    if (!open || !overlay) return
    var p = dropdown.mapToItem(overlay, 0, dropdown.height + 6)
    menu.x = p.x
    menu.y = p.y
  }

  UiText {
    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter; right: chevron.left; rightMargin: 8 }
    elide: Text.ElideRight
    text: dropdown.label
    font.pixelSize: 14
    font.weight: Font.Medium
  }
  Glyph {
    id: chevron
    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
    width: 14
    height: 14
    path: Icons.chevronDown
    strokeWidth: 2
    color: Theme.muted
    rotation: dropdown.open ? 180 : 0
    Behavior on rotation { enabled: !Theme.calm; NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  }
  MouseArea {
    id: dropMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: { dropdown.forceActiveFocus(); dropdown.open = !dropdown.open }
  }

  Rectangle {
    id: menu
    parent: dropdown.overlay
    width: dropdown.width
    height: menuColumn.implicitHeight + 8
    radius: 10
    color: Theme.rail
    border.width: 1
    border.color: Theme.a(Theme.line, 0.9)
    opacity: dropdown.open ? 1 : 0
    visible: opacity > 0
    scale: Theme.calm ? 1 : 0.98 + 0.02 * opacity
    transformOrigin: Item.Top
    Behavior on opacity { NumberAnimation { duration: dropdown.open ? Theme.uiMs : Theme.fastMs; easing.type: dropdown.open ? Easing.OutCubic : Easing.InCubic } }
    RectangularShadow {
      anchors.fill: parent
      offset.y: 18
      blur: 40
      radius: parent.radius
      color: Qt.rgba(0, 0, 0, 0.5)
      z: -1
    }
    Column {
      id: menuColumn
      x: 4
      y: 4
      width: parent.width - 8
      Repeater {
        model: dropdown.options
        Rectangle {
          id: option
          required property var modelData
          width: menuColumn.width
          height: 34
          radius: 7
          color: optionMouse.containsMouse ? Theme.a(Theme.line, 0.45) : "transparent"
          UiText {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: option.modelData.label
            color: option.modelData.value === dropdown.value ? Theme.accent : Theme.fg
            font.weight: Font.Medium
          }
          Glyph {
            visible: option.modelData.value === dropdown.value
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 13; height: 13
            path: Icons.check
            strokeWidth: 2
            color: Theme.accent
          }
          MouseArea {
            id: optionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { dropdown.open = false; if (option.modelData.value !== dropdown.value) dropdown.picked(option.modelData.value) }
          }
        }
      }
    }
  }
}
