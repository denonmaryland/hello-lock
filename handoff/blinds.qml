import QtQuick

// Blinds: the logo is cut into horizontal strips that slide away alternately
// left and right, top first; the symbol grows up from behind.
HandoffEffect {
  id: root
  readonly property int strips: 8

  Repeater {
    model: root.strips
    Piece {
      id: strip
      required property int index
      readonly property real stripTop: Math.round(root.sourceRect.height * index / root.strips)
      readonly property real p: root.easeOut((root.t - index * 0.035) / 0.6)
      effect: root
      py: stripTop
      ph: Math.round(root.sourceRect.height * (index + 1) / root.strips) - stripTop
      opacity: 1 - p
      transform: Translate { x: (strip.index % 2 === 0 ? -1 : 1) * strip.p * root.sourceRect.width * 0.14 }
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: 820; easing.type: Easing.Linear }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.88; to: 1; duration: 800; easing.type: Easing.OutCubic }
  }
}
