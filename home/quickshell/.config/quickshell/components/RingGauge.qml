// home/quickshell/.config/quickshell/components/RingGauge.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

// A ticked ring gauge: a 60-tick bezel, a faint track lit clockwise from the top by `value`, and a readout inside.
Item {
    id: root

    property var st: Style.for_item(root)
    property real value: 0
    property string label: ""
    property string unit: ""
    property color color: root.st.text_strong
    property real label_size: root.width * 0.27

    readonly property real c: root.width / 2
    readonly property real r: root.width / 2 - 10

    implicitWidth: 84
    implicitHeight: root.width

    function ticks() {
        let d = "";
        for (let i = 0; i < 60; i++) {
            const a = i / 60 * Math.PI * 2 - Math.PI / 2, r1 = root.r + 4, r2 = root.r + (i % 5 ? 6.5 : 9);
            d += "M" + (root.c + r1 * Math.cos(a)).toFixed(2) + " " + (root.c + r1 * Math.sin(a)).toFixed(2)
                + "L" + (root.c + r2 * Math.cos(a)).toFixed(2) + " " + (root.c + r2 * Math.sin(a)).toFixed(2);
        }
        return d;
    }

    function dots() {
        const r = root.r - 7, n = Math.max(8, Math.floor(Math.PI * 2 * r / 4));
        let d = "";
        for (let i = 0; i < n; i++) {
            const a = i / n * Math.PI * 2, b = a + 1 / r;
            d += "M" + (root.c + r * Math.cos(a)).toFixed(2) + " " + (root.c + r * Math.sin(a)).toFixed(2)
                + "L" + (root.c + r * Math.cos(b)).toFixed(2) + " " + (root.c + r * Math.sin(b)).toFixed(2);
        }
        return d;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.color, 0.35)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.ticks() }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.color, 0.15)
            fillColor: "transparent"
            PathAngleArc { centerX: root.c; centerY: root.c; radiusX: root.r; radiusY: root.r; startAngle: 0; sweepAngle: 360 }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.color, 0.2)
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.dots() }
        }

        ShapePath {
            strokeWidth: root.value > 0 ? 1.5 : -1
            strokeColor: root.color
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: root.c
                centerY: root.c
                radiusX: root.r
                radiusY: root.r
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, root.value))
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: root.color
            font.family: root.st.number_font
            font.weight: Font.ExtraLight
            font.pixelSize: root.label_size
        }

        Text {
            visible: root.unit !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.unit
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: Math.max(8, root.width * 0.085)
            font.letterSpacing: 2.5
        }
    }
}
