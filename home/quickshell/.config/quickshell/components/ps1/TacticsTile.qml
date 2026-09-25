// home/quickshell/.config/quickshell/components/ps1/TacticsTile.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// A Final Fantasy Tactics map tile: a 2:1 isometric slab that stretches for its units; selected wears the blue move grid.
Item {
    id: root

    property bool selected: false
    property bool empty: false
    property bool hovered: false
    // x positions of the joins between stood-on cells, drawn as grid seams across the top face.
    property var seams: []
    property int face: 10
    property int depth: 3

    readonly property real half: face / 2
    readonly property real run: face
    readonly property real w: width

    readonly property color top_fill: root.empty ? Qt.alpha(Theme.bg_surface, root.hovered ? 0.55 : 0.35) : Qt.tint(Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_inlay, 0.35)), Qt.alpha(Theme.fg_core, root.hovered ? 0.1 : 0))
    readonly property color left_fill: root.empty ? Qt.alpha(Theme.bg_shadow, 0.45) : Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.fg_inlay, 0.3))
    readonly property color front_fill: root.empty ? Qt.alpha(Theme.bg_shadow, 0.55) : Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.fg_inlay, 0.16))
    readonly property color right_fill: root.empty ? Qt.alpha(Theme.bg_shadow, 0.65) : Qt.tint(Theme.bg_crust, Qt.alpha(Theme.fg_inlay, 0.16))
    readonly property color outline: root.empty ? Qt.alpha(Theme.fg_dim, 0.3) : Qt.alpha(Theme.bg_shadow, 0.7)
    readonly property color rim: root.empty ? "transparent" : Qt.alpha(Theme.fg_core, 0.2)
    readonly property color seam: Qt.alpha(Theme.bg_shadow, root.empty ? 0 : 0.45)

    implicitHeight: face + depth

    Shape {
        anchors.fill: parent

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.left_fill
            PathSvg { path: "M0 " + root.half + "L" + root.run + " " + root.face + "V" + (root.face + root.depth) + "L0 " + (root.half + root.depth) + "Z" }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.front_fill
            PathSvg { path: "M" + root.run + " " + root.face + "H" + (root.w - root.run) + "V" + (root.face + root.depth) + "H" + root.run + "Z" }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.right_fill
            PathSvg { path: "M" + (root.w - root.run) + " " + root.face + "L" + root.w + " " + root.half + "V" + (root.half + root.depth) + "L" + (root.w - root.run) + " " + (root.face + root.depth) + "Z" }
        }
        ShapePath {
            strokeColor: root.outline
            strokeWidth: 1
            fillColor: root.top_fill
            PathSvg { path: "M0 " + root.half + "L" + root.run + " 0H" + (root.w - root.run) + "L" + root.w + " " + root.half + "L" + (root.w - root.run) + " " + root.face + "H" + root.run + "Z" }
        }
        ShapePath {
            strokeColor: root.rim
            strokeWidth: 1
            fillColor: "transparent"
            PathSvg { path: "M1 " + root.half + "L" + root.run + " 1H" + (root.w - root.run) }
        }
    }

    Repeater {
        model: root.seams

        Shape {
            id: seam_line
            required property real modelData
            anchors.fill: parent

            ShapePath {
                strokeColor: root.seam
                strokeWidth: 1
                fillColor: "transparent"
                PathSvg { path: "M" + (seam_line.modelData - root.face + 2) + " " + (root.face - 1) + "L" + (seam_line.modelData + root.face - 2) + " 1" }
            }
        }
    }

    Shape {
        visible: root.selected
        anchors.fill: parent

        ShapePath {
            strokeColor: Theme.bright_blue
            strokeWidth: 1
            fillColor: Qt.alpha(Theme.blue, 0.42)
            PathSvg { path: "M4 " + root.half + "L" + root.run + " 2H" + (root.w - root.run) + "L" + (root.w - 4) + " " + root.half + "L" + (root.w - root.run) + " " + (root.face - 2) + "H" + root.run + "Z" }
        }
    }
}
