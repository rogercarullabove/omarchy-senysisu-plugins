import QtQuick
import QtQuick.Shapes

// The bar graphic. `mode` picks what is drawn:
//   "columns"   one column per value, filled bottom-up
//   "sparkline" the same columns, but only a 2 px cap at each value's level
//   "ring"      an arc filled clockwise from 12 o'clock to `value`
// Values are percentages (0-100).
Item {
  id: root

  property string mode: "sparkline"
  property var values: []
  property real value: 0
  property color color: "white"
  property real size: 16

  readonly property real columnWidth: Math.max(2, Math.round(size * 0.19))
  readonly property real columnGap: Math.max(1, Math.round(size * 0.1))
  readonly property int count: values ? values.length : 0
  readonly property real ringStroke: Math.max(2, size * 0.15)

  implicitHeight: size
  implicitWidth: mode === "ring"
    ? size
    : Math.max(columnWidth, count * columnWidth + Math.max(0, count - 1) * columnGap)

  function level(v) {
    var n = Number(v)
    return isFinite(n) ? Math.max(0, Math.min(100, n)) / 100 : 0
  }

  Row {
    visible: root.mode === "columns" || root.mode === "sparkline"
    anchors.fill: parent
    spacing: root.columnGap

    Repeater {
      model: root.count

      Item {
        required property int index
        readonly property real fill: Math.max(1, Math.round(root.level(root.values[index]) * root.height))

        width: root.columnWidth
        height: root.height

        Rectangle {
          anchors.fill: parent
          color: root.color
          opacity: root.mode === "sparkline" ? 0.12 : 0.2
        }

        Rectangle {
          visible: root.mode === "columns"
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.fill
          color: root.color
        }

        Rectangle {
          visible: root.mode === "sparkline"
          width: parent.width
          height: 2
          y: Math.max(0, Math.min(parent.height - height, parent.height - parent.fill))
          color: root.color
        }
      }
    }
  }

  Shape {
    visible: root.mode === "ring"
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.25)
      strokeWidth: root.ringStroke
      PathAngleArc {
        centerX: root.size / 2; centerY: root.size / 2
        radiusX: (root.size - root.ringStroke) / 2; radiusY: radiusX
        startAngle: 0; sweepAngle: 360
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.ringStroke
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        centerX: root.size / 2; centerY: root.size / 2
        radiusX: (root.size - root.ringStroke) / 2; radiusY: radiusX
        startAngle: -90; sweepAngle: 360 * root.level(root.value)
      }
    }
  }
}
