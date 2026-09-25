// home/quickshell/.config/quickshell/components/ps1/Ps1Button.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// One DualShock-era PS1 pad button: grey domes with coloured symbols, grey shoulder and START/SELECT pills, a D-pad with the used arms lit.
Item {
    id: root

    property string button: "cross"
    property real size: 16

    readonly property bool face: ["cross", "circle", "triangle", "square"].indexOf(root.button) >= 0
    readonly property bool pad: root.button.startsWith("dpad")
    readonly property bool pill: root.button === "select" || root.button === "start"
    readonly property string label: ({ l1: "L1", r1: "R1", l2: "L2", r2: "R2", select: "SELECT", start: "START" })[root.button] || ""
    readonly property real stroke: Math.max(1.4, root.size * 0.13)
    readonly property color dome_top: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2))
    readonly property color dome_bottom: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.5))
    readonly property color rim: Theme.bg_shadow
    // Hardware symbol colours pulled halfway toward the theme's own.
    readonly property color symbol: root.button === "cross" ? Qt.tint("#8fb4f0", Qt.alpha(Theme.blue, 0.5))
        : root.button === "circle" ? Qt.tint("#f07a7a", Qt.alpha(Theme.red, 0.5))
        : root.button === "triangle" ? Qt.tint("#4fd1a8", Qt.alpha(Theme.cyan, 0.5))
        : Qt.tint("#f0a0dc", Qt.alpha(Theme.magenta, 0.5))

    implicitWidth: root.pill ? Math.round(root.size * 2.9) : root.label !== "" ? Math.round(root.size * 1.5) : root.size
    implicitHeight: root.size
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        visible: !root.pad
        anchors.fill: parent
        radius: root.face ? width / 2 : root.pill ? height / 2 : height * 0.3
        border.width: 1
        border.color: root.rim
        gradient: Gradient {
            GradientStop { position: 0; color: root.dome_top }
            GradientStop { position: 1; color: root.dome_bottom }
        }

        Rectangle {
            visible: root.face
            x: parent.width * 0.22
            y: parent.height * 0.1
            width: parent.width * 0.56
            height: parent.height * 0.3
            radius: height / 2
            color: Qt.alpha(Theme.fg_strong, 0.18)
        }
    }

    Text {
        visible: root.label !== ""
        anchors.centerIn: parent
        text: root.label
        color: Theme.fg_strong
        font.family: Style.mono_font
        font.pixelSize: Math.max(7, Math.round(root.size * (root.pill ? 0.5 : 0.62)))
        font.bold: true
        style: Text.Raised
        styleColor: root.rim
    }

    Shape {
        visible: root.face
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.stroke
            strokeColor: root.symbol
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                readonly property real s: root.size
                readonly property real a: s * 0.3
                readonly property real b: s * 0.7
                path: root.button === "cross" ? "M " + a + " " + a + " L " + b + " " + b + " M " + b + " " + a + " L " + a + " " + b
                    : root.button === "circle" ? "M " + (s / 2) + " " + (s * 0.27) + " A " + (s * 0.23) + " " + (s * 0.23) + " 0 1 1 " + (s / 2 - 0.01) + " " + (s * 0.27) + " Z"
                    : root.button === "triangle" ? "M " + (s / 2) + " " + (s * 0.26) + " L " + (s * 0.74) + " " + (s * 0.68) + " L " + (s * 0.26) + " " + (s * 0.68) + " Z"
                    : "M " + (s * 0.3) + " " + (s * 0.3) + " L " + (s * 0.7) + " " + (s * 0.3) + " L " + (s * 0.7) + " " + (s * 0.7) + " L " + (s * 0.3) + " " + (s * 0.7) + " Z"
            }
        }
    }

    Item {
        id: dpad
        visible: root.pad
        anchors.fill: parent
        readonly property real arm: Math.round(root.size * 0.36)
        readonly property real mid: (root.size - dpad.arm) / 2
        readonly property color lit: Theme.fg_strong

        Rectangle {
            x: dpad.mid
            width: dpad.arm
            height: root.size
            radius: 1
            color: root.dome_bottom
            border.width: 1
            border.color: root.rim
        }

        Rectangle {
            y: dpad.mid
            width: root.size
            height: dpad.arm
            radius: 1
            color: root.dome_bottom
            border.width: 1
            border.color: root.rim
        }

        Repeater {
            model: [["dpad_up", "dpad_v", dpad.mid, 1], ["dpad_down", "dpad_v", dpad.mid, root.size - dpad.mid], ["dpad_left", "dpad_h", 1, dpad.mid], ["dpad_right", "dpad_h", root.size - dpad.mid, dpad.mid]]

            Rectangle {
                required property var modelData
                visible: root.button === modelData[0] || root.button === modelData[1]
                x: modelData[2] + (modelData[1] === "dpad_v" ? 2 : 0)
                y: modelData[3] + (modelData[1] === "dpad_h" ? 2 : 0)
                width: modelData[1] === "dpad_v" ? dpad.arm - 4 : dpad.mid - 2
                height: modelData[1] === "dpad_v" ? dpad.mid - 2 : dpad.arm - 4
                color: dpad.lit
            }
        }
    }
}
