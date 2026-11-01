import QtQuick

// Wipe: an accent scan line lights up at the logo's left edge, sweeps across
// erasing the logo behind it with a fading tail, and goes out at the far
// edge; the symbol is waiting there.
HandoffEffect {
  id: root
  property real line: 0
  property real lineGlow: 0
  onResetting: { line = 0; lineGlow = 0 }

  readonly property real edge: Math.round(sourceRect.width * line)

  // What's left of the logo, right of the line.
  Piece {
    effect: root
    px: root.edge
    pw: root.sourceRect.width - root.edge
  }

  // The tail: a soft accent band trailing the line over the erased side.
  Rectangle {
    readonly property real span: Math.max(48, root.sourceRect.height * 0.3)
    x: root.sourceRect.x + root.edge - span
    y: root.sourceRect.y + root.sourceRect.height * 0.12
    width: span + 6
    height: root.sourceRect.height * 0.76
    visible: root.active && root.lineGlow > 0
    opacity: root.lineGlow * 0.22
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
      GradientStop { position: 0.9; color: root.accent }
      GradientStop { position: 1; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
    }
  }

  Rectangle {
    x: root.sourceRect.x + root.edge - 1
    y: root.sourceRect.y + root.sourceRect.height * 0.08
    width: 2
    height: root.sourceRect.height * 0.84
    visible: root.active && root.lineGlow > 0
    opacity: root.lineGlow
    color: Qt.lighter(root.accent, 1.4)
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "line"; from: 0; to: 1; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: root.moveCurve }
    SequentialAnimation {
      NumberAnimation { target: root; property: "lineGlow"; from: 0; to: 1; duration: 90; easing.type: Easing.OutQuad }
      // Goes out as it clears the logo, not in the empty margin after it.
      PauseAnimation { duration: 350 }
      NumberAnimation { target: root; property: "lineGlow"; from: 1; to: 0; duration: 300; easing.type: Easing.OutExpo }
    }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.94; to: 1; duration: root.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
  }
}
