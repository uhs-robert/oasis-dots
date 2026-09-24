// home/quickshell/.config/quickshell/components/MenuSection.qml
import QtQuick
import "../theme"

Text {
    id: root

    property string label: ""

    width: Style.section_rule && parent ? parent.width : implicitWidth
    clip: Style.section_rule
    text: Style.section_rule ? "── " + root.label + " " + "─".repeat(160) : root.label
    color: Style.section_fg
    font.family: Style.font_family
    font.pixelSize: Style.font_size - 3
}
