import QtQuick

// Slide: the logo slides out to the left; the symbol slides in from the right.
HandoffEffect {
  id: root
  property real shift: 0
  property real fade: 1
  onResetting: { shift = 0; fade = 1 }

  Piece {
    effect: root
    opacity: root.fade
    transform: Translate { x: -root.shift * root.width }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "shift"; from: 0; to: 0.4; duration: 600; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 520; easing.type: Easing.InQuad }
    NumberAnimation { target: root; property: "emergeX"; from: 0.7; to: 0; duration: 700; easing.type: Easing.OutCubic }
  }
}
