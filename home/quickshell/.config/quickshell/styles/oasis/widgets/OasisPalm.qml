import QtQuick
import QtQuick.Shapes

// A small palm drawn as strokes: a leaning trunk under five fronds. The item's bottom edge is the foot of the trunk.
Item {
    id: root

    property color color: "white"
    property real stroke: 1.6

    implicitWidth: 24
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.stroke
            strokeColor: root.color
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M12 27.5Q14 18 12 9M12 9Q12 4 12.5 1.5M12 9Q17 3 23 7M12 9Q18 8 21 14M12 9Q7 3 1 7M12 9Q6 8 3 14" }
        }
    }
}
