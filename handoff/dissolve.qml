import QtQuick
import QtQuick.Effects

// Dissolve: the logo blurs out and fades (a crossfade to a blurred copy, so
// no blur is switched on mid-play); the symbol grows gently in.
HandoffEffect {
  id: root
  property real blurMix: 0
  property real fade: 1
  property real grow: 1
  onResetting: { blurMix = 0; fade = 1; grow = 1 }

  Item {
    x: root.sourceRect.x
    y: root.sourceRect.y
    width: root.sourceRect.width
    height: root.sourceRect.height
    visible: root.active && root.fade > 0
    scale: root.grow
    opacity: root.fade

    Piece {
      effect: root
      x: 0
      y: 0
      opacity: 1 - root.blurMix
    }

    MultiEffect {
      anchors.fill: parent
      source: root.source
      autoPaddingEnabled: false
      opacity: root.blurMix
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      blurMultiplier: 1.0
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "blurMix"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 700; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "grow"; from: 1; to: 1.06; duration: 700; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.9; to: 1; duration: 800; easing.type: Easing.OutCubic }
  }
}
