import QtQuick

// Fly through: the logo rushes toward you and past, fading as it goes; the
// symbol comes in from far away. The logo's scale is a perspective one
// (1 / distance), so the rush builds naturally.
HandoffEffect {
  id: root
  // Distance covered toward the viewer, speeding up from the first frame.
  readonly property real travel: 0.55 * t + 0.45 * t * t

  Piece {
    effect: root
    scale: 1 / (1 - 0.62 * root.travel)
    opacity: 1 - root.easeInOut((root.t - 0.08) / 0.84)
  }

  timeline: ParallelAnimation {
    // t is the clock; travel and fade are shaped from it.
    NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: 600; easing.type: Easing.Linear }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.6; to: 1; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
