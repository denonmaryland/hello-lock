import QtQuick

// Split: the logo's top and bottom halves part vertically; the symbol grows
// out of the gap.
HandoffEffect {
  id: root
  property real part: 0
  property real fade: 1
  onResetting: { part = 0; fade = 1 }

  readonly property real half: Math.round(sourceRect.height / 2)

  Piece {
    effect: root
    ph: root.half
    opacity: root.fade
    transform: Translate { y: -root.part * root.height }
  }

  Piece {
    effect: root
    py: root.half
    ph: root.sourceRect.height - root.half
    opacity: root.fade
    transform: Translate { y: root.part * root.height }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "part"; from: 0; to: 0.14; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 600; easing.type: Easing.InQuad }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.78; to: 1; duration: 750; easing.type: Easing.OutCubic }
  }
}
