import QtQuick
import QtQuick.Shapes

// The bar graphic: an arc filled clockwise from 12 o'clock to `value`
// (a percentage, 0-100), over a faint full-circle track.
Item {
  id: root

  property real value: 0
  property color color: "white"
  property real size: 16

  readonly property real stroke: Math.max(2, size * 0.15)
  readonly property real level: {
    var n = Number(value)
    return isFinite(n) ? Math.max(0, Math.min(100, n)) / 100 : 0
  }

  implicitWidth: size
  implicitHeight: size

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.25)
      strokeWidth: root.stroke
      PathAngleArc {
        centerX: root.size / 2; centerY: root.size / 2
        radiusX: (root.size - root.stroke) / 2; radiusY: radiusX
        startAngle: 0; sweepAngle: 360
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.stroke
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: root.size / 2; centerY: root.size / 2
        radiusX: (root.size - root.stroke) / 2; radiusY: radiusX
        startAngle: -90; sweepAngle: 360 * root.level
      }
    }
  }
}
