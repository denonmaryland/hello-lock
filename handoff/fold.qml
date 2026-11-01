import QtQuick

// Fold in: the logo squeezes sideways into a sliver at the centre, gathering
// speed and stretching a hair taller as it narrows; the symbol unfolds out of
// the sliver, picking up the motion as the logo goes.
HandoffEffect {
  id: root
  property real squeeze: 1
  property real fade: 1
  onResetting: { squeeze = 1; fade = 1 }

  Piece {
    effect: root
    opacity: root.fade
    transform: Scale {
      origin.x: root.sourceRect.width / 2
      origin.y: root.sourceRect.height / 2
      xScale: root.squeeze
      yScale: 1 + 0.04 * (1 - root.squeeze)
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "squeeze"; from: 1; to: 0.02; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    SequentialAnimation {
      PauseAnimation { duration: 270 }
      NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 80; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
      // Exactly edge-on (unseen) until it opens.
      PropertyAction { target: root; property: "emergeTurn"; value: 90 }
      PauseAnimation { duration: 290 }
      NumberAnimation { target: root; property: "emergeTurn"; from: 90; to: 0; duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
    }
  }
}
