import QtQuick

// Fly through: the logo rushes toward you and past, fading; the symbol comes
// in from far away.
HandoffEffect {
  id: root
  property real grow: 1
  property real fade: 1
  onResetting: { grow = 1; fade = 1 }

  Piece {
    effect: root
    scale: root.grow
    opacity: root.fade
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "grow"; from: 1; to: 2.8; duration: 560; easing.type: Easing.Linear }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 480; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.55; to: 1; duration: 800; easing.type: Easing.OutCubic }
  }
}
