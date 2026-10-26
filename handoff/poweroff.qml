import QtQuick

// Power off: the logo squashes to a bright line like an old CRT, the line
// shrinks to a dot and the dot goes out; the symbol grows from it.
HandoffEffect {
  id: root
  property real squashY: 1
  property real squashX: 1
  property real fade: 1
  property real dot: 0
  onResetting: { squashY = 1; squashX = 1; fade = 1; dot = 0 }

  Piece {
    effect: root
    opacity: root.fade
    transform: Scale {
      origin.x: root.sourceRect.width / 2
      origin.y: root.sourceRect.height / 2
      xScale: root.squashX
      yScale: root.squashY
    }
  }

  // The line's afterglow, then the dot.
  Rectangle {
    readonly property real size: Math.max(10, root.sourceRect.height * 0.08) * (0.4 + 0.6 * root.dot)
    x: root.cx - width / 2
    y: root.cy - height / 2
    width: size
    height: size
    radius: height / 2
    visible: root.active && root.dot > 0
    opacity: Math.min(1, root.dot * 1.5)
    color: Qt.lighter(root.accent, 1.5)
  }

  timeline: ParallelAnimation {
    SequentialAnimation {
      NumberAnimation { target: root; property: "squashY"; from: 1; to: 0.02; duration: 240; easing.type: Easing.OutCubic }
      ParallelAnimation {
        NumberAnimation { target: root; property: "squashX"; from: 1; to: 0; duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 200; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "dot"; from: 0; to: 1; duration: 200; easing.type: Easing.InQuad }
      }
      NumberAnimation { target: root; property: "dot"; from: 1; to: 0; duration: 260; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {
      PropertyAction { target: root; property: "emergeScale"; value: 0.4 }
      PauseAnimation { duration: 400 }
      NumberAnimation { target: root; property: "emergeScale"; from: 0.4; to: 1; duration: 480; easing.type: Easing.OutCubic }
    }
  }
}
