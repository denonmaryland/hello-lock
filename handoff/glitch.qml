import QtQuick

// Glitch out: the logo splits into colour ghosts, jitters and tears into
// slices, flickers and cuts away; the symbol snaps in.
HandoffEffect {
  id: root
  property real fade: 1
  property real tear: 0
  property real jitter: 0
  property var offsets: [0, 0, 0, 0, 0]
  onResetting: { fade = 1; tear = 0; jitter = 0; offsets = [0, 0, 0, 0, 0] }

  readonly property real amp: sourceRect.height * 0.12

  Timer {
    interval: 45
    repeat: true
    running: root.active && root.busy
    triggeredOnStart: true
    onTriggered: {
      var next = []
      for (var i = 0; i < 5; i++) next.push(Math.random() * 2 - 1)
      root.offsets = next
    }
  }

  // Colour ghosts either side.
  Piece {
    effect: root
    colorization: 1
    colorizationColor: root.alertColor
    opacity: root.fade * 0.6 * root.jitter
    transform: Translate { x: -root.amp * (0.4 + 0.6 * Math.abs(root.offsets[0])) * root.jitter }
  }

  Piece {
    effect: root
    colorization: 1
    colorizationColor: root.accent
    opacity: root.fade * 0.5 * root.jitter
    transform: Translate { x: root.amp * (0.4 + 0.6 * Math.abs(root.offsets[1])) * root.jitter }
  }

  // The logo, shifting a little.
  Piece {
    effect: root
    opacity: root.fade * (1 - 0.6 * root.tear)
    transform: Translate { x: root.amp * 0.25 * root.offsets[2] * root.jitter }
  }

  // Torn slices, displaced sideways.
  Repeater {
    model: 3
    Piece {
      id: slice
      required property int index
      readonly property real band: Math.round(root.sourceRect.height * (0.2 + 0.25 * index))
      effect: root
      py: band
      ph: Math.round(root.sourceRect.height * 0.12)
      opacity: root.fade * root.tear
      transform: Translate { x: root.amp * 2.2 * root.offsets[slice.index + 2] * root.tear }
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "jitter"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
    SequentialAnimation {
      PauseAnimation { duration: 140 }
      NumberAnimation { target: root; property: "tear"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {
      PauseAnimation { duration: 260 }
      NumberAnimation { target: root; property: "fade"; to: 0.3; duration: 50 }
      NumberAnimation { target: root; property: "fade"; to: 0.9; duration: 40 }
      NumberAnimation { target: root; property: "fade"; to: 0.15; duration: 60 }
      NumberAnimation { target: root; property: "fade"; to: 0.6; duration: 40 }
      NumberAnimation { target: root; property: "fade"; to: 0; duration: 90 }
    }
    SequentialAnimation {
      PropertyAction { target: root; property: "emergeScale"; value: 0.86 }
      PauseAnimation { duration: 280 }
      NumberAnimation { target: root; property: "emergeScale"; from: 0.86; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.8 }
    }
  }
}
