import QtQuick

// A group heading: a mono caps label on the left and an optional value or
// item on the right (the design's "label row").
Item {
  id: group
  property string text: ""
  property string value: ""
  property color valueColor: Theme.fg
  default property alias trailing: trailingSlot.data
  width: parent ? parent.width : 0
  implicitHeight: 18

  MonoText {
    anchors.verticalCenter: parent.verticalCenter
    text: group.text
    tracking: 0.2
  }
  UiText {
    visible: group.value !== ""
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    width: Math.min(implicitWidth, group.width * 0.62)
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    text: group.value
    color: group.valueColor
    font.weight: Font.Medium
  }
  Row {
    id: trailingSlot
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    spacing: 7
  }
}
