import QtQuick

// Wipe: an accent scan line sweeps across and erases the logo behind it; the
// symbol is waiting there.
HandoffEffect {
  id: root
  property real line: 0
  property real lineGlow: 1
  onResetting: { line = 0; lineGlow = 1 }

  readonly property real edge: Math.round(sourceRect.width * line)

  // What's left of the logo, right of the line.
  Piece {
    effect: root
    px: root.edge
    pw: root.sourceRect.width - root.edge
  }

  // The line: a soft accent band with a bright core.
  Rectangle {
    x: root.sourceRect.x + root.edge - width / 2
    y: root.sourceRect.y + root.sourceRect.height * 0.12
    width: Math.max(24, root.sourceRect.height * 0.12)
    height: root.sourceRect.height * 0.76
    visible: root.active && root.lineGlow > 0
    opacity: root.lineGlow * 0.55
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 0.5; color: root.accent }
      GradientStop { position: 1; color: "transparent" }
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
    NumberAnimation { target: root; property: "line"; from: 0; to: 1; duration: 620; easing.type: Easing.OutSine }
    SequentialAnimation {
      PauseAnimation { duration: 560 }
      NumberAnimation { target: root; property: "lineGlow"; from: 1; to: 0; duration: 180; easing.type: Easing.OutQuad }
    }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.95; to: 1; duration: 700; easing.type: Easing.OutCubic }
  }
}
