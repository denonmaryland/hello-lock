import QtQuick

// Fall back: the logo shrinks back, sinks a little and fades; the symbol grows
// up from behind it.
HandoffEffect {
  id: root
  property real shrink: 1
  property real drop: 0
  property real fade: 1
  onResetting: { shrink = 1; drop = 0; fade = 1 }

  Piece {
    effect: root
    scale: root.shrink
    opacity: root.fade
    transform: Translate { y: root.drop * root.height }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "shrink"; from: 1; to: 0.74; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "drop"; from: 0; to: 0.03; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 520; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.84; to: 1; duration: 750; easing.type: Easing.OutCubic }
  }
}
