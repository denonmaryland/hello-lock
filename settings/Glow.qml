import QtQuick
import QtQuick.Shapes

// A soft radial glow filling its box (an ellipse in a non-square box):
// `color` at `strength` in the middle, `midStrength` at `mid`, nothing from
// `reach` on (fractions of the half-size). `outer` keeps a floor beyond it,
// and `bleed` extends the painted area past the box for full-cover washes.
Item {
  id: glow
  property color color: Theme.accent
  property real strength: 0.22
  property real mid: 0.54
  property real midStrength: strength * 0.32
  property real reach: 0.96
  property real outer: 0
  property real bleed: 0

  Shape {
    width: 100
    height: 100
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: glow.width / 100; yScale: glow.height / 100 }
    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: 50; centerY: 50; centerRadius: 50
        focalX: 50; focalY: 50
        GradientStop { position: 0; color: Theme.a(glow.color, glow.strength) }
        GradientStop { position: glow.mid; color: Theme.a(glow.color, glow.midStrength) }
        GradientStop { position: glow.reach; color: Theme.a(glow.color, glow.outer) }
        GradientStop { position: 1; color: Theme.a(glow.color, glow.outer) }
      }
      PathRectangle { x: -glow.bleed; y: -glow.bleed; width: 100 + glow.bleed * 2; height: 100 + glow.bleed * 2 }
    }
  }
}
