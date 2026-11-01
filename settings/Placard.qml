import QtQuick

// The caption under the stage: what is shown (title and a mono subtitle) on
// the left, a legend of up to three facts on the right. A legend item is
// { label, value, lit }; lit labels take the accent.
Item {
  id: placard
  property string title: ""
  property string subtitle: ""
  property var legend: []
  default property alias extra: extraRow.data
  width: 758
  implicitHeight: Math.max(titleColumn.implicitHeight, legendRow.implicitHeight)

  Column {
    id: titleColumn
    x: 4
    width: placard.width - legendRow.width - 40
    spacing: 4
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: placard.title
      color: Theme.fg
      font.family: Theme.display
      font.pixelSize: 24
      font.weight: Font.Medium
      textFormat: Text.PlainText
    }
    MonoText {
      width: parent.width
      elide: Text.ElideRight
      text: placard.subtitle
      tracking: 0.18
      size: 11
    }
  }
  Row {
    id: legendRow
    anchors { right: parent.right; rightMargin: 4 }
    y: 4
    spacing: 28
    Repeater {
      model: placard.legend
      Column {
        id: legendItem
        required property var modelData
        required property int index
        width: Math.max(110, Math.min(176, Math.max(legendLabel.implicitWidth, legendValue.implicitWidth)))
        spacing: 5
        MonoText {
          id: legendLabel
          width: parent.width
          elide: Text.ElideRight
          text: modelData.label
          tracking: 0.18
          size: 11
          color: modelData.lit ? Theme.accent : Theme.muted
          Behavior on color { ColorAnimation { duration: Theme.uiMs; easing.type: Easing.OutCubic } }
        }
        UiText {
          id: legendValue
          width: parent.width
          elide: Text.ElideRight
          text: modelData.value
        }
      }
    }
    Row {
      id: extraRow
      spacing: 28
    }
  }
}
