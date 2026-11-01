import QtQuick

// Fall back: the logo recedes into the dark, sinking a little as it fades;
// the symbol grows up from behind it.
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
    NumberAnimation { target: root; property: "shrink"; from: 1; to: 0.8; duration: root.exitDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    NumberAnimation { target: root; property: "drop"; from: 0; to: 0.025; duration: root.exitDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: root.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.moveCurve }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.86; to: 1; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
