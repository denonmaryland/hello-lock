import QtQuick

// Blinds: the logo is cut into horizontal slats that tilt shut and slide away
// alternately left and right, top first, each gathering speed; the symbol
// grows up from behind.
HandoffEffect {
  id: root
  readonly property int strips: 8

  Repeater {
    model: root.strips
    Piece {
      id: strip
      required property int index
      readonly property real stripTop: Math.round(root.sourceRect.height * index / root.strips)
      // Its own 0..1 progress, top slat first (about 30 ms apart).
      readonly property real q: root.clamp01((root.t - index * 0.038) / 0.62)
      readonly property real p: root.easeIn(q)
      effect: root
      py: stripTop
      ph: Math.round(root.sourceRect.height * (index + 1) / root.strips) - stripTop
      opacity: 1 - root.easeInOut(q)
      transform: [
        Scale {
          origin.y: strip.height / 2
          yScale: 1 - 0.4 * strip.p
        },
        Translate { x: (strip.index % 2 === 0 ? -1 : 1) * strip.p * root.sourceRect.width * 0.1 }
      ]
    }
  }

  timeline: ParallelAnimation {
    // t is the clock; each slat eases itself.
    NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: 800; easing.type: Easing.Linear }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.9; to: 1; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
