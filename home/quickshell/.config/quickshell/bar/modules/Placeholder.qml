// home/quickshell/.config/quickshell/bar/modules/Placeholder.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// Stand-in for a module that isn't built yet: shows its glyph and a dim label, no actions.
Item {
    id: root

    property string glyph: ""
    property string label: ""
    property string tooltip_text: ""

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.glyph
            color: Theme.theme_primary
            opacity: 0.6
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Theme.glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.label !== ""
            text: root.label
            color: Theme.fg_dim
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }
}
