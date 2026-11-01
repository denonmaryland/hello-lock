import QtQuick
import QtQuick.Effects

// Power off: the logo squashes to a bright line like an old CRT (widening a
// touch as it flattens), the line snaps to a dot and the dot's phosphor glow
// decays; the symbol blooms out of the dot.
HandoffEffect {
  id: root
  property real squashY: 1
  property real squashX: 1
  property real fade: 1
  property real hot: 0
  property real dot: 0
  onResetting: { squashY = 1; squashX = 1; fade = 1; hot = 0; dot = 0 }

  // The logo, and over it a blurred, bright copy that takes over as it
  // flattens, smearing it into one glowing line (blur set up front).
  Item {
    x: root.sourceRect.x
    y: root.sourceRect.y
    width: root.sourceRect.width
    height: root.sourceRect.height
    visible: root.active && root.fade > 0
    opacity: root.fade
    transform: Scale {
      origin.x: root.sourceRect.width / 2
      origin.y: root.sourceRect.height / 2
      xScale: root.squashX
      yScale: root.squashY
    }

    Piece {
      effect: root
      x: 0
      y: 0
    }

    MultiEffect {
      anchors.fill: parent
      source: root.source
      autoPaddingEnabled: false
      visible: root.hot > 0
      opacity: root.hot
      colorization: 1
      colorizationColor: Qt.lighter(root.accent, 1.6)
      blurEnabled: true
      blur: 1.0
      blurMax: 48
      blurMultiplier: 0.5
      brightness: 0.4
    }
  }

  // The beam the flattened logo becomes: soft-ended, brightest mid-screen,
  // so it reads as one line whatever gaps the logo has.
  Rectangle {
    width: root.sourceRect.width * 0.9 * root.squashX
    height: 2
    x: root.cx - width / 2
    y: root.cy - 1
    visible: root.active && root.hot > 0 && root.fade > 0
    opacity: root.hot * root.hot * root.fade
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
      GradientStop { position: 0.5; color: Qt.lighter(root.accent, 1.6) }
      GradientStop { position: 1; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0) }
    }
  }

  // The dot: a soft halo and a bright core.
  Rectangle {
    readonly property real size: Math.max(10, root.sourceRect.height * 0.08) * (0.4 + 0.6 * root.dot) * 2.6
    x: root.cx - width / 2
    y: root.cy - height / 2
    width: size
    height: size
    radius: height / 2
    visible: root.active && root.dot > 0
    opacity: 0.22 * root.dot
    color: root.accent
  }

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
      ParallelAnimation {
        NumberAnimation { target: root; property: "squashY"; from: 1; to: 0.015; duration: 230; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
        NumberAnimation { target: root; property: "squashX"; from: 1; to: 1.04; duration: 230; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
        NumberAnimation { target: root; property: "hot"; from: 0; to: 1; duration: 230; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
      }
      ParallelAnimation {
        NumberAnimation { target: root; property: "squashX"; from: 1.04; to: 0; duration: 190; easing.type: Easing.BezierSpline; easing.bezierCurve: root.exitCurve }
        NumberAnimation { target: root; property: "fade"; from: 1; to: 0; duration: 190; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "dot"; from: 0; to: 1; duration: 190; easing.type: Easing.InQuad }
      }
      // Phosphor decay: fast, then a long faint tail.
      NumberAnimation { target: root; property: "dot"; from: 1; to: 0; duration: 380; easing.type: Easing.OutExpo }
    }
    SequentialAnimation {
      PropertyAction { target: root; property: "emergeScale"; value: 0.25 }
      PauseAnimation { duration: 380 }
      NumberAnimation { target: root; property: "emergeScale"; from: 0.25; to: 1; duration: root.emergeDuration - 260; easing.type: Easing.BezierSpline; easing.bezierCurve: root.emergeCurve }
    }
  }
}
