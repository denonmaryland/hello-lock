import QtQuick

// Split: a hairline of light opens along the logo's middle and its top and
// bottom halves part from it, gathering speed as they fade; the symbol grows
// out of the gap.
HandoffEffect {
  id: root
  property real part: 0
  property real fade: 1
  property real seam: 0
  onResetting: { part = 0; fade = 1; seam = 0 }

  readonly property real half: Math.round(sourceRect.height / 2)

  Piece {
    effect: root
    ph: root.half
    opacity: root.fade
    transform: Translate { y: -root.part * root.height }
  }

  Piece {
    effect: root
    py: root.half
    ph: root.sourceRect.height - root.half
    opacity: root.fade
    transform: Translate { y: root.part * root.height }
  }

  // The seam: an accent hairline that widens with the gap and dies away.
  Rectangle {
    width: root.sourceRect.width * (0.5 + 0.35 * root.easeOut(root.part / 0.12))
    height: 2
    x: root.cx - width / 2
    y: root.sourceRect.y + root.half - 1
    radius: 1
    visible: root.active && root.seam > 0
    opacity: 0.7 * root.seam
    color: Qt.lighter(root.accent, 1.3)
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "part"; from: 0; to: 0.12; duration: root.exitDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: root.fadeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.moveCurve }
    SequentialAnimation {
      NumberAnimation { target: root; property: "seam"; from: 0; to: 1; duration: 110; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "seam"; from: 1; to: 0; duration: 480; easing.type: Easing.OutExpo }
    }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.8; to: 1; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
