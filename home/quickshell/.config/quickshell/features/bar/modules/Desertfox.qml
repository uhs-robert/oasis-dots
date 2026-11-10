import QtQuick
import qs.theme
import qs.features.bar
import qs.features.desertfox

// "DF <mode>" for the DesertFox mode in Firefox, beside the workspaces. HyprVim's own mode stays where it is (the
// submap tab or lualine chip): the two modes are different things and both show.
BarModule {
    id: root
    module_name: "desertfox"
    has_popup: false
    has_tooltip: false
    wash: false

    // DesertFox mode ids; any other keeps the secondary colour.
    readonly property var color_map: ({
        "normal": Theme.theme_primary,
        "insert": Theme.syntax_parameter,
        "ignore": Theme.fg_dim,
        "hint": Theme.syntax_macro,
        "cmdline": Theme.syntax_statement,
        "caret": Theme.syntax_type,
        "visual": Theme.syntax_special,
        "visual_line": Theme.syntax_constant,
    })
    readonly property color tint: color_map[DesertfoxState.mode_id] || Theme.theme_secondary

    // A side bar's column is too narrow for the text.
    shown: !root.vertical && DesertfoxState.chip_label !== ""
    implicitWidth: root.shown ? chip.width : 0
    implicitHeight: chip.height

    Rectangle {
        id: chip
        anchors.verticalCenter: parent.verticalCenter
        width: label.implicitWidth + 12
        height: label.implicitHeight + 4
        radius: Style.bar_radius(4)
        color: Qt.alpha(root.tint, 0.2)
        border.width: 1
        border.color: Qt.alpha(root.tint, 0.6)

        Text {
            id: label
            anchors.centerIn: parent
            text: "DF " + DesertfoxState.chip_label
            color: root.tint
            font.family: Style.font_family
            font.pixelSize: Style.bar_font_size
            font.bold: true
        }
    }
}
