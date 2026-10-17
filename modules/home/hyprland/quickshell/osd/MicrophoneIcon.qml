import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property bool muted: false
  property color foreground: "white"

  implicitWidth: 24
  implicitHeight: 24

  Item {
    width: 24
    height: 24
    anchors.centerIn: parent
    scale: Math.min(root.width, root.height) / 24

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: root.foreground
        strokeWidth: -1
        startX: 7
        startY: 5
        PathArc { x: 13; y: 5; radiusX: 3; radiusY: 3 }
        PathLine { x: 13; y: 11 }
        PathArc { x: 7; y: 11; radiusX: 3; radiusY: 3 }
        PathLine { x: 7; y: 5 }
      }

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.foreground
        strokeWidth: 1.5
        capStyle: ShapePath.RoundCap
        startX: 4
        startY: 10
        PathLine { x: 4; y: 11 }
        PathArc { x: 16; y: 11; radiusX: 6; radiusY: 6; direction: PathArc.Counterclockwise }
        PathLine { x: 16; y: 10 }
        PathMove { x: 10; y: 17 }
        PathLine { x: 10; y: 21 }
        PathMove { x: 7; y: 21 }
        PathLine { x: 13; y: 21 }
      }
    }

    Shape {
      objectName: "microphoneMuteCross"
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: root.muted

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.foreground
        strokeWidth: 1.5
        capStyle: ShapePath.RoundCap
        startX: 17
        startY: 4
        PathLine { x: 22; y: 9 }
        PathMove { x: 22; y: 4 }
        PathLine { x: 17; y: 9 }
      }
    }
  }
}
