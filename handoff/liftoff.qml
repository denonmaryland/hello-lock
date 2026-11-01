import QtQuick

// Lift off: the logo crouches a hair, then rises and fades upward, gathering
// speed; the symbol rises into place from below it.
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
    SequentialAnimation {
      // Anticipation: a slight dip, already moving on the first frame.
      NumberAnimation { target: root; property: "rise"; from: 0; to: -0.006; duration: 90; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "rise"; from: -0.006; to: 0.13; duration: root.exitDuration - 90; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    }
    NumberAnimation { target: root; property: "grow"; from: 1; to: 1.04; duration: root.exitDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: root.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.moveCurve }
    NumberAnimation { target: root; property: "emergeY"; from: 0.24; to: 0; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.94; to: 1; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
