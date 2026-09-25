// home/quickshell/.config/quickshell/components/ps2/SaveCube.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// A memory card save icon: a translucent cube seen from above, its letter pressed into the left face.
Item {
    id: root

    property string letter: ""
    property color color: Theme.theme_primary
    property bool selected: false
    readonly property real s: root.width

    implicitWidth: 24
    implicitHeight: root.width
    scale: root.selected ? 1.12 : 1

    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Rectangle {
        visible: root.selected
        anchors.centerIn: parent
        width: root.s * 1.5
        height: width
        radius: width / 2
        color: Qt.alpha(root.color, 0.18)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.fg_strong, root.selected ? 0.5 : 0.2)
            joinStyle: ShapePath.RoundJoin
            fillColor: Qt.alpha(Qt.lighter(root.color, 1.35), root.selected ? 0.85 : 0.5)
            PathPolyline { path: [Qt.point(root.s / 2, 0), Qt.point(root.s, root.s / 4), Qt.point(root.s / 2, root.s / 2), Qt.point(0, root.s / 4), Qt.point(root.s / 2, 0)] }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.fg_strong, root.selected ? 0.35 : 0.14)
            joinStyle: ShapePath.RoundJoin
            fillColor: Qt.alpha(root.color, root.selected ? 0.75 : 0.4)
            PathPolyline { path: [Qt.point(0, root.s / 4), Qt.point(root.s / 2, root.s / 2), Qt.point(root.s / 2, root.s), Qt.point(0, root.s * 0.75), Qt.point(0, root.s / 4)] }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.fg_strong, root.selected ? 0.3 : 0.1)
            joinStyle: ShapePath.RoundJoin
            fillColor: Qt.alpha(Qt.darker(root.color, 1.6), root.selected ? 0.8 : 0.45)
            PathPolyline { path: [Qt.point(root.s / 2, root.s / 2), Qt.point(root.s, root.s / 4), Qt.point(root.s, root.s * 0.75), Qt.point(root.s / 2, root.s), Qt.point(root.s / 2, root.s / 2)] }
        }
    }

    Text {
        x: 0
        y: root.s * 0.375
        width: root.s / 2
        height: root.s / 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.letter.toUpperCase()
        color: Theme.fg_strong
        opacity: root.selected ? 1 : 0.75
        font.family: "Exo 2"
        font.pixelSize: Math.round(root.s * 0.34)
        font.weight: Font.DemiBold
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, 0, 0, 0, 0.5, 1, 0, -root.s * 0.125, 0, 0, 1, 0, 0, 0, 0, 1)
        }
    }
}
