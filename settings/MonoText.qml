import QtQuick

// Share Tech Mono labels: eyebrows, group labels, readouts. `tracking` is
// letter spacing in em and `size` the pixel size, as in the design.
Text {
  property real tracking: 0
  property real size: 12
  color: Theme.muted
  font.family: Theme.mono
  font.pixelSize: size
  font.letterSpacing: size * tracking
  textFormat: Text.PlainText
}
