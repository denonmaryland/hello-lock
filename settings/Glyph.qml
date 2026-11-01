import QtQuick
import QtQuick.Shapes

// A line icon from SVG path data in a 24×24 box (the Paper design's icons),
// stroked with round caps and joins, or filled.
Item {
  id: glyph
  property string path: ""
  property color color: Theme.fg
  property real strokeWidth: 1.6
  property bool filled: false
  property real box: 24
  implicitWidth: 20
  implicitHeight: 20

  Shape {
    width: glyph.box
    height: glyph.box
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: glyph.width / glyph.box; yScale: glyph.height / glyph.box }
    ShapePath {
      strokeColor: glyph.filled ? "transparent" : glyph.color
      strokeWidth: glyph.filled ? -1 : glyph.strokeWidth
      fillColor: glyph.filled ? glyph.color : "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: glyph.path }
    }
  }
}
