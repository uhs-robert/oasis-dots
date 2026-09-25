// home/quickshell/.config/quickshell/components/ps1/MemBlock.qml
import QtQuick
import "../../theme"

// A memory card block holding a glyph, like the weather save blocks; lit blocks take the selection fill.
Rectangle {
    id: root

    property real size: 24
    property string glyph: ""
    property color glyph_color: Style.text_fg
    property bool lit: false

    implicitWidth: root.size
    implicitHeight: root.size
    radius: 3
    color: root.lit ? Style.selection_bg : Qt.alpha(Theme.bg_shadow, 0.45)
    border.width: 2
    border.color: root.lit ? Theme.theme_primary_light : Style.frame_border_color

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.glyph_color
        font.family: Style.font_family
        font.pixelSize: Math.round(root.size * 0.62)
    }
}
