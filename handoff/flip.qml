import QtQuick

// Flip: the logo turns edge-on like a card; the symbol finishes the turn into
// view.
HandoffEffect {
  id: root
  property real turn: 0
  property real shrink: 1
  onResetting: { turn = 0; shrink = 1 }

  Piece {
    effect: root
    scale: root.shrink
    opacity: root.turn < 89.5 ? 1 : 0
    transform: Rotation {
      origin.x: root.sourceRect.width / 2
      origin.y: root.sourceRect.height / 2
      axis { x: 0; y: 1; z: 0 }
      angle: root.turn
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "turn"; from: 0; to: 90; duration: 280; easing.type: Easing.Linear }
    NumberAnimation { target: root; property: "shrink"; from: 1; to: 0.94; duration: 280; easing.type: Easing.OutQuad }
    SequentialAnimation {
      PropertyAction { target: root; property: "emergeTurn"; value: -90 }
      PauseAnimation { duration: 280 }
      NumberAnimation { target: root; property: "emergeTurn"; from: -90; to: 0; duration: 420; easing.type: Easing.OutCubic }
    }
  }
}
