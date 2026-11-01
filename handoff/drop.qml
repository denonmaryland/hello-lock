import QtQuick

// Drop: the logo hops, then falls off the bottom under gravity with a slight
// tilt; the symbol drops in from above after it and settles with one small
// bounce.
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
      // Up and slowing at the top of the hop, then constant acceleration.
      NumberAnimation { target: root; property: "fall"; from: 0; to: -0.018; duration: 120; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "fall"; from: -0.018; to: 0.6; duration: 540; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
      PauseAnimation { duration: 60 }
      NumberAnimation { target: root; property: "tilt"; from: 0; to: 7; duration: 600; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
      PauseAnimation { duration: 400 }
      NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    }
    // Follows the logo down a beat later; one balanced overshoot to settle.
    SequentialAnimation {
      PropertyAction { target: root; property: "emergeY"; value: -0.32 }
      PauseAnimation { duration: 50 }
      NumberAnimation { target: root; property: "emergeY"; from: -0.32; to: 0; duration: 700; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
    }
  }
}
