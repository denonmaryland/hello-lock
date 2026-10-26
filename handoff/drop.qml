import QtQuick

// Drop: the logo hops, then falls off the bottom with a slight tilt; the
// symbol settles in from above.
HandoffEffect {
  id: root
  property real fall: 0
  property real tilt: 0
  property real fade: 1
  onResetting: { fall = 0; tilt = 0; fade = 1 }

  Piece {
    effect: root
    rotation: root.tilt
    opacity: root.fade
    transform: Translate { y: root.fall * root.height }
  }

  timeline: ParallelAnimation {
    SequentialAnimation {
      NumberAnimation { target: root; property: "fall"; from: 0; to: -0.02; duration: 110; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "fall"; from: -0.02; to: 0.7; duration: 560; easing.type: Easing.InQuad }
    }
    NumberAnimation { target: root; property: "tilt"; from: 0; to: 9; duration: 670; easing.type: Easing.InQuad }
    SequentialAnimation {
      PauseAnimation { duration: 450 }
      NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 220 }
    }
    NumberAnimation { target: root; property: "emergeY"; from: -0.45; to: 0; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
  }
}
