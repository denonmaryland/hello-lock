import QtQuick

// Pixelate: the logo coarsens into ever bigger pixels and breaks up; the
// symbol grows up from behind.
HandoffEffect {
  id: root
  property real fade: 1
  onResetting: { fade = 1 }

  // Pixel size in steps, already coarse on the first frame.
  readonly property var steps: [3, 6, 10, 16, 24, 34, 46]
  readonly property int block: steps[Math.min(steps.length - 1, Math.floor(t * steps.length))]

  // The logo, drawn into a texture a fraction of its size and shown with
  // nearest-neighbour scaling.
  Item {
    id: full
    x: root.sourceRect.x
    y: root.sourceRect.y
    width: root.sourceRect.width
    height: root.sourceRect.height

    Piece {
      effect: root
      x: 0
      y: 0
    }
  }

  ShaderEffectSource {
    x: full.x
    y: full.y
    width: full.width
    height: full.height
    visible: root.active && root.fade > 0
    opacity: root.fade
    sourceItem: full
    hideSource: true
    smooth: false
    textureSize: Qt.size(Math.max(1, Math.round(width / root.block)), Math.max(1, Math.round(height / root.block)))
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "t"; from: 0; to: 0.999; duration: 600; easing.type: Easing.Linear }
    SequentialAnimation {
      PauseAnimation { duration: 300 }
      NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 340; easing.type: Easing.InQuad }
    }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.85; to: 1; duration: 800; easing.type: Easing.OutCubic }
  }
}
