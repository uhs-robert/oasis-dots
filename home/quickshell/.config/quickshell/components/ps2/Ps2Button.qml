// home/quickshell/.config/quickshell/components/ps2/Ps2Button.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"

// One DualShock 2 button as a glossy black badge: face symbols, shoulders, START/SELECT, R3 or the D-pad.
Item {
    id: root

    property string button: "cross"
    property real size: 16

    readonly property bool face: ["cross", "circle", "triangle", "square"].indexOf(root.button) >= 0
    readonly property bool shoulder: ["l1", "r1", "l2", "r2"].indexOf(root.button) >= 0
    readonly property bool dpad: root.button === "dpad_v" || root.button === "dpad_h"
    readonly property bool pill: root.button === "select" || root.button === "start"
    readonly property string label: root.shoulder ? root.button.toUpperCase() : root.pill ? root.button.toUpperCase() : root.button === "r3" ? "R3" : ""
    // Hardware symbol colours, pulled toward the palette.
    readonly property color symbol_color: {
        const hw = { cross: "#7BA7E8", circle: "#F0736B", triangle: "#5FD0A0", square: "#E891C8" }[root.button] || "#FFFFFF";
        const pull = { cross: Theme.blue, circle: Theme.red, triangle: Theme.green, square: Theme.magenta }[root.button] || Theme.fg_strong;
        return Qt.tint(hw, Qt.alpha(pull, 0.45));
    }
    readonly property color body_top: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_strong, 0.06))
    readonly property color body_bottom: Theme.bg_shadow

    implicitHeight: root.size
    implicitWidth: root.shoulder ? Math.round(root.size * 1.55) : root.pill ? label_text.implicitWidth + root.size * 0.7 : root.size
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        visible: !root.dpad
        anchors.fill: parent
        radius: root.shoulder ? root.size * 0.3 : height / 2
        border.width: 1
        border.color: Theme.bg_shadow
        gradient: Gradient {
            GradientStop { position: 0; color: root.body_top }
            GradientStop { position: 1; color: root.body_bottom }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.fg_strong, 0.14)
        }

        Rectangle {
            x: parent.width * 0.16
            y: 1.5
            width: parent.width * 0.68
            height: parent.height * 0.42
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, 0.26) }
                GradientStop { position: 1; color: Qt.alpha(Theme.fg_strong, 0) }
            }
        }

        Rectangle {
            visible: root.button === "r3"
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.fg_strong, 0.22)
        }
    }

    Text {
        id: label_text
        visible: root.label !== ""
        anchors.centerIn: parent
        text: root.label
        color: Theme.fg_core
        font.family: "Exo 2"
        font.pixelSize: Math.max(7, Math.round(root.size * (root.pill ? 0.42 : 0.5)))
        font.weight: Font.DemiBold
        font.letterSpacing: root.pill ? 0.6 : 0
    }

    Shape {
        visible: root.face
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: Math.max(1.3, root.size / 10)
            strokeColor: root.face ? root.symbol_color : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: {
                    const s = root.size * 0.44, o = (root.size - s) / 2, e = o + s, c = root.size / 2;
                    if (root.button === "cross") return "M" + o + " " + o + "L" + e + " " + e + "M" + e + " " + o + "L" + o + " " + e;
                    if (root.button === "triangle") return "M" + c + " " + (o - s * 0.06) + "L" + (e + s * 0.04) + " " + (e - s * 0.08) + "L" + (o - s * 0.04) + " " + (e - s * 0.08) + "Z";
                    if (root.button === "square") return "M" + (o + s * 0.06) + " " + (o + s * 0.06) + "L" + (e - s * 0.06) + " " + (o + s * 0.06) + "L" + (e - s * 0.06) + " " + (e - s * 0.06) + "L" + (o + s * 0.06) + " " + (e - s * 0.06) + "Z";
                    if (root.button === "circle") return "M" + e + " " + c + "A" + s / 2 + " " + s / 2 + " 0 1 1 " + (e - 0.01) + " " + (c - 0.5) + "Z";
                    return "";
                }
            }
        }
    }

    // The D-pad: a black cross whose lit arms show the keys' axis.
    Shape {
        visible: root.dpad
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Theme.bg_shadow
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.size
                GradientStop { position: 0; color: root.body_top }
                GradientStop { position: 1; color: root.body_bottom }
            }
            PathPolyline {
                path: {
                    const a = root.size * 0.34, b = root.size * 0.66, e = root.size - 0.5, z = 0.5;
                    return [Qt.point(a, z), Qt.point(b, z), Qt.point(b, a), Qt.point(e, a), Qt.point(e, b), Qt.point(b, b), Qt.point(b, e), Qt.point(a, e), Qt.point(a, b), Qt.point(z, b), Qt.point(z, a), Qt.point(a, a), Qt.point(a, z)];
                }
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.theme_primary_light
            PathSvg {
                path: {
                    const s = root.size, c = s / 2, w = s * 0.1, n = s * 0.07, f = s * 0.24;
                    if (root.button === "dpad_v") return "M" + (c - w) + " " + f + "L" + c + " " + n + "L" + (c + w) + " " + f + "Z" + "M" + (c - w) + " " + (s - f) + "L" + c + " " + (s - n) + "L" + (c + w) + " " + (s - f) + "Z";
                    return "M" + f + " " + (c - w) + "L" + n + " " + c + "L" + f + " " + (c + w) + "Z" + "M" + (s - f) + " " + (c - w) + "L" + (s - n) + " " + c + "L" + (s - f) + " " + (c + w) + "Z";
                }
            }
        }
    }
}
