// home/quickshell/.config/quickshell/components/MenuSection.qml
import QtQuick
import QtQuick.Shapes
import "../theme"

Text {
    id: root

    readonly property var st: Style.for_item(root)

    property string label: ""

    width: (root.st.section_rule || root.st.section_fade.a > 0) && parent ? parent.width : implicitWidth
    clip: root.st.section_rule
    text: root.st.section_rule ? "── " + root.label + " " + "─".repeat(160) : root.label
    color: root.st.section_fg
    font.family: root.st.label_font_family
    font.pixelSize: root.st.font_size - 3
    font.capitalization: root.st.label_caps || root.st.caps_tracking > 0 ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: root.st.caps_tracking > 0 ? root.st.caps_tracking : root.st.label_spacing
    font.bold: root.st.caps_tracking > 0
    readonly property bool orb: root.st.materia.section !== undefined
    leftPadding: root.orb ? 15 : root.st.section_marker.a > 0 ? 11 : 0

    MateriaOrb {
        visible: root.orb
        y: root.topPadding + Math.round(root.contentHeight / 2) - 4.5
        width: 9
        height: 9
        glow: false
        color: root.orb ? root.st.materia.section : "transparent"
    }

    Shape {
        visible: root.st.section_marker.a > 0
        y: root.topPadding + Math.round(root.contentHeight / 2) - 4
        width: 5
        height: 8

        ShapePath {
            strokeWidth: -1
            fillColor: root.st.section_marker
            PathPolyline { path: [Qt.point(0, 0), Qt.point(5, 4), Qt.point(0, 8), Qt.point(0, 0)] }
        }
    }

    Rectangle {
        visible: root.st.section_fade.a > 0
        x: root.leftPadding + root.contentWidth + 8
        y: root.topPadding + Math.round(root.contentHeight / 2)
        width: Math.max(0, (root.width - x) * 0.7)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.st.section_fade }
            GradientStop { position: 1; color: Qt.alpha(root.st.section_fade, 0) }
        }
    }
}
