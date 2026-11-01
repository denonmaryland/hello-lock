import QtQuick

// Slide: the logo slides out to the left, gathering speed and stretching a
// touch along its path; the symbol slides in from the right and settles.
HandoffEffect {
  id: root
  property real shift: 0
  property real fade: 1
  onResetting: { shift = 0; fade = 1 }

  Piece {
    effect: root
    opacity: root.fade
    transform: [
      Scale {
        origin.x: root.sourceRect.width / 2
        origin.y: root.sourceRect.height / 2
        xScale: 1 + 0.12 * root.shift
      },
      Translate { x: -root.shift * root.width }
    ]
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "shift"; from: 0; to: 0.36; duration: root.exitDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: root.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.moveCurve }
    NumberAnimation { target: root; property: "emergeX"; from: 0.5; to: 0; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
