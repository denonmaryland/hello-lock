import QtQuick
import QtQuick.Effects

// A rectangle of the logo (px, py, pw, ph in logo-texture pixels; the whole
// logo by default), drawn where it sits at rest. Move, scale, turn or fade it
// freely; transforms pivot on its centre.
Item {
  id: piece
  property var effect: null
  property real px: 0
  property real py: 0
  property real pw: effect ? effect.sourceRect.width : 0
  property real ph: effect ? effect.sourceRect.height : 0
  // Fixed per piece (changing MultiEffect features at runtime recompiles it).
  property real colorization: 0
  property color colorizationColor: "white"

  readonly property bool whole: px <= 0 && py <= 0 && effect
    && pw >= effect.sourceRect.width && ph >= effect.sourceRect.height
  x: effect ? effect.sourceRect.x + px : 0
  y: effect ? effect.sourceRect.y + py : 0
  width: pw
  height: ph
  clip: !whole
  visible: effect !== null && effect.active && opacity > 0

  MultiEffect {
    x: -piece.px
    y: -piece.py
    width: piece.effect ? piece.effect.sourceRect.width : 0
    height: piece.effect ? piece.effect.sourceRect.height : 0
    source: piece.effect ? piece.effect.source : null
    autoPaddingEnabled: false
    colorization: piece.colorization
    colorizationColor: piece.colorizationColor
  }
}
