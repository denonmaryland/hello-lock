import QtQuick

// Scatter: the logo breaks into a grid of tiles that drift outward from the
// centre, turning as they fade; the symbol grows out of the middle.
HandoffEffect {
  id: root
  readonly property int cols: 8
  readonly property int rows: 3

  Repeater {
    model: root.cols * root.rows
    Piece {
      id: tile
      required property int index
      readonly property int col: index % root.cols
      readonly property int row: Math.floor(index / root.cols)
      readonly property real cellLeft: Math.round(root.sourceRect.width * col / root.cols)
      readonly property real cellTop: Math.round(root.sourceRect.height * row / root.rows)
      // Direction from the logo's centre; inner tiles leave first.
      readonly property real dx: (col + 0.5) / root.cols - 0.5
      readonly property real dy: (row + 0.5) / root.rows - 0.5
      readonly property real reach: Math.sqrt(dx * dx + dy * dy)
      readonly property real p: root.easeOut((root.t - reach * 0.18) / 0.75)
      effect: root
      px: cellLeft
      py: cellTop
      pw: Math.round(root.sourceRect.width * (col + 1) / root.cols) - cellLeft
      ph: Math.round(root.sourceRect.height * (row + 1) / root.rows) - cellTop
      opacity: 1 - p
      rotation: (root.prand(index, 1) * 2 - 1) * 40 * p
      scale: 1 - 0.25 * p
      transform: Translate {
        x: (tile.dx * 0.5 + (root.prand(tile.index, 2) - 0.5) * 0.12) * root.width * 0.5 * tile.p
        y: (tile.dy * 1.2 + (root.prand(tile.index, 3) - 0.5) * 0.2) * root.height * 0.3 * tile.p
      }
    }
  }

  timeline: ParallelAnimation {
    NumberAnimation { target: root; property: "t"; from: 0; to: 1; duration: 850; easing.type: Easing.Linear }
    NumberAnimation { target: root; property: "emergeScale"; from: 0.7; to: 1; duration: 800; easing.type: Easing.OutCubic }
  }
}
