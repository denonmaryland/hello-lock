import QtQuick

// A segmented control: options [{ value, label }], one selected. The
// highlight slides between options (it jumps with reduced motion).
Rectangle {
  id: seg
  property var options: []
  property string value: ""
  property int itemPadding: 7
  property int fontSize: 12
  // Size options by their labels (for many options) instead of equally.
  property bool proportional: false
  signal picked(string value)
  readonly property int count: options.length
  readonly property int selectedIndex: {
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
    return -1
  }
  readonly property real span: width - 8 - 4 * Math.max(0, count - 1)
  readonly property var weights: options.map(function(o) { return proportional ? String(o.label).length + 4 : 1 })
  readonly property real weightSum: weights.reduce(function(a, b) { return a + b }, 0)
  function itemX(i) {
    var x = 4
    for (var k = 0; k < i; k++) x += itemW(k) + 4
    return x
  }
  function itemW(i) { return weightSum > 0 ? span * weights[i] / weightSum : 0 }

  width: parent ? parent.width : 0
  implicitHeight: 16 + itemPadding * 2 + 8
  radius: 9
  color: Theme.deepest
  border.width: 1
  border.color: Theme.a(Theme.line, 0.6)
  opacity: enabled ? 1 : 0.45

  Rectangle {
    visible: seg.selectedIndex >= 0
    x: seg.itemX(Math.max(0, seg.selectedIndex))
    y: 4
    width: seg.itemW(Math.max(0, seg.selectedIndex))
    height: seg.height - 8
    radius: 6
    color: Theme.line
    Behavior on x { enabled: !Theme.calm; NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !Theme.calm; NumberAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
  }
  Repeater {
    model: seg.options
    Item {
      id: option
      required property var modelData
      required property int index
      readonly property bool selected: index === seg.selectedIndex
      x: seg.itemX(index)
      y: 4
      width: seg.itemW(index)
      height: seg.height - 8
      activeFocusOnTab: true
      Keys.onSpacePressed: seg.picked(modelData.value)
      Keys.onReturnPressed: seg.picked(modelData.value)
      Rectangle {
        anchors.fill: parent
        radius: 6
        color: !option.selected && optionMouse.containsMouse ? Theme.a(Theme.line, 0.35) : "transparent"
        border.width: option.activeFocus ? 1 : 0
        border.color: Theme.a(Theme.accent, 0.7)
        Behavior on color { ColorAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
      }
      UiText {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 6)
        elide: Text.ElideRight
        text: option.modelData.label
        font.pixelSize: seg.fontSize
        font.weight: option.selected ? Font.DemiBold : Font.Medium
        color: option.selected ? Theme.fg : Theme.muted
        Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
      }
      MouseArea {
        id: optionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: seg.picked(option.modelData.value)
      }
    }
  }
}
