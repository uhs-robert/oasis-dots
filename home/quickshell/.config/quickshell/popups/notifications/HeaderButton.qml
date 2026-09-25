// home/quickshell/.config/quickshell/popups/notifications/HeaderButton.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"

// A pill button for the notifications header: icon + label + a keycap-style key hint.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string key_hint: ""
    property bool active: false

    signal activated()

    implicitWidth: row.implicitWidth + 28
    implicitHeight: row.implicitHeight + 16
    radius: Style.pill_chips ? height / 2 : Style.radius(8)
    readonly property bool cut: Style.key_cut > 0
    color: root.cut ? "transparent" : root.active ? Theme.theme_primary : mouse_area.pressed ? Qt.darker(Theme.bg_surface, 1.3) : mouse_area.containsMouse ? Theme.ui_visual_bg : Style.pill_chips ? "transparent" : Style.tab_outline.a > 0 ? Style.tab_active_bg : Theme.bg_surface
    border.width: root.cut ? 0 : 1
    border.color: Style.pill_chips || Style.tab_outline.a > 0 ? Style.chip_border : Theme.ui_border

    CutBox {
        visible: root.cut
        anchors.fill: parent
        cut_tl: 6
        cut_br: 6
        fill: root.active ? Theme.theme_primary : mouse_area.containsMouse ? Style.chip_border : Style.chip_bg
        stroke: Style.chip_border
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: root.icon
            color: root.active ? Theme.bg_core : Theme.fg_core
            font.family: Style.font_family
            font.pixelSize: Style.font_size
        }

        Text {
            text: root.label
            color: root.active ? Theme.bg_core : Theme.fg_core
            font.bold: root.active || root.cut
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 2
            font.capitalization: Style.tab_caps || Style.caps_tracking > 0 ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: Style.caps_tracking > 0 ? Style.caps_tracking * 0.7 : Style.tab_caps ? Style.label_spacing * 0.6 : 0
        }

        Rectangle {
            id: key_cap
            visible: root.key_hint !== ""
            readonly property bool orb: Style.materia.key !== undefined
            implicitWidth: key_cap.orb ? Math.max(16, key_label.implicitWidth + 8) : key_label.implicitWidth + 8
            implicitHeight: 16
            radius: Style.key_round ? height / 2 : Style.radius(3)
            color: key_cap.orb ? "transparent" : root.active ? Theme.bg_core : Style.key_bg
            border.width: key_cap.orb ? 0 : 1
            border.color: root.active ? Theme.ui_border : Style.key_border

            MateriaOrb {
                visible: key_cap.orb
                anchors.fill: parent
                color: key_cap.orb ? Style.materia.key : "transparent"
            }

            Text {
                id: key_label
                anchors.centerIn: parent
                text: root.key_hint
                color: root.active && !key_cap.orb ? Theme.theme_primary : Style.key_fg
                font.bold: key_cap.orb || Style.mono_font === Style.font_family
                font.family: Style.mono_font
                font.pixelSize: Style.font_size - 5
            }
        }
    }

    MouseArea {
        id: mouse_area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.activated()
    }
}
