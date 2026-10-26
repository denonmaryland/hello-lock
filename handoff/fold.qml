import QtQuick

// Fold in: the logo squeezes sideways into the centre; the symbol unfolds out
// of it.
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
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "squeeze"; from: 1; to: 0.02; duration: 380; easing.type: Easing.OutQuart }
    SequentialAnimation {
      PauseAnimation { duration: 300 }
      NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 100 }
    }
    SequentialAnimation {
      PropertyAction { target: root; property: "emergeTurn"; value: 88 }
      PauseAnimation { duration: 320 }
      NumberAnimation { target: root; property: "emergeTurn"; from: 88; to: 0; duration: 460; easing.type: Easing.OutCubic }
    }
  }
}
