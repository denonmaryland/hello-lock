import QtQuick

// Flip: one card turn carries the logo edge-on and the symbol on round into
// view, so the two halves share a single, unbroken motion; the card dips back
// a little as it turns.
HandoffEffect {
  id: root
  // 0..180 degrees: the logo's face until 90, the symbol's after.
  property real turn: 0
  readonly property real dip: 1 - 0.05 * Math.sin(turn * Math.PI / 180)
  onResetting: { turn = 0 }
  onTurnChanged: {
    if (!active) return
    emergeTurn = turn < 90 ? -90 : turn - 180
    emergeScale = dip
  }

  Piece {
    effect: root
    scale: root.dip
    opacity: root.turn < 90 ? 1 : 0
    transform: Rotation {
      origin.x: root.sourceRect.width / 2
      origin.y: root.sourceRect.height / 2
      axis { x: 0; y: 1; z: 0 }
      angle: Math.min(90, root.turn)
    }
  }

  timeline: ParallelAnimation {
    PropertyAction { target: root; property: "emergeTurn"; value: -90 }
    NumberAnimation { target: root; property: "turn"; from: 0; to: 180; duration: 780; easing.type: Easing.BezierSpline; easing.bezierCurve: root.moveCurve }
  }
}
