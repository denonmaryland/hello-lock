import QtQuick

// Lift off: the logo rises and fades upward; the symbol rises into place from
// below it.
HandoffEffect {
  id: root
  property real rise: 0
  property real grow: 1
  property real fade: 1
  onResetting: { rise = 0; grow = 1; fade = 1 }

  Piece {
    effect: root
    scale: root.grow
    opacity: root.fade
    transform: Translate { y: -root.rise * root.height }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "rise"; from: 0; to: 0.14; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "grow"; from: 1; to: 1.05; duration: 650; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 520; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "emergeY"; from: 0.35; to: 0; duration: 750; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.92; to: 1; duration: 750; easing.type: Easing.OutCubic }
  }
}
