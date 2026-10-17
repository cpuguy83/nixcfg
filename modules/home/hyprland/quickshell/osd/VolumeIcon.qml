pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property real volumePercent: 0
  property bool muted: false
  property color foreground: "white"

  readonly property real clampedVolume: isNaN(volumePercent) ? 0 : Math.max(0, Math.min(100, volumePercent))

  implicitWidth: 24
  implicitHeight: 24

  // A fixed view box: neither the speaker nor the layout follows the volume.
  Item {
    id: drawing
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
        PathPolyline {
          path: [Qt.point(2, 9), Qt.point(6, 9), Qt.point(10, 5), Qt.point(10, 19), Qt.point(6, 15), Qt.point(2, 15), Qt.point(2, 9)]
        }
      }
    }

    Repeater {
      model: 3

      Shape {
        id: wave
        required property int index
        readonly property real radius: 5 + index * 4
        readonly property real offset: radius / Math.sqrt(2)

        objectName: "wave" + index
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // Each third of the range continuously lights the next arc.
        opacity: root.muted ? 0 : Math.max(0, Math.min(1, root.clampedVolume * 3 / 100 - index))

        ShapePath {
          fillColor: "transparent"
          strokeColor: root.foreground
          strokeWidth: 1.5
          capStyle: ShapePath.RoundCap
          startX: 9 + wave.offset
          startY: 12 - wave.offset
          PathArc {
            x: 9 + wave.offset
            y: 12 + wave.offset
            radiusX: wave.radius
            radiusY: wave.radius
            direction: PathArc.Clockwise
          }
        }
      }
    }

    Shape {
      objectName: "muteCross"
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      visible: root.muted

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.foreground
        strokeWidth: 1.5
        capStyle: ShapePath.RoundCap
        startX: 14
        startY: 9
        PathLine {
          x: 20
          y: 15
        }
        PathMove {
          x: 20
          y: 9
        }
        PathLine {
          x: 14
          y: 15
        }
      }
    }
  }
}
