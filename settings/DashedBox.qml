import QtQuick
import QtQuick.Shapes

// A dashed rounded outline (annotation boxes on the stage).
Shape {
  id: box
  property color color: Theme.a(Theme.accent, 0.75)
  property color fill: "transparent"
  property real radius: 8
  preferredRendererType: Shape.CurveRenderer
  ShapePath {
    strokeColor: box.color
    strokeWidth: 1
    fillColor: box.fill
    strokeStyle: ShapePath.DashLine
    dashPattern: [4, 3]
    PathRectangle { x: 0.5; y: 0.5; width: box.width - 1; height: box.height - 1; radius: box.radius }
  }
}
