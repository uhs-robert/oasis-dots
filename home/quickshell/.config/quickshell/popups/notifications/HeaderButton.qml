// home/quickshell/.config/quickshell/popups/notifications/HeaderButton.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../components/KeyHints.js" as KeyHints

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
    color: root.active ? Style.pal.primary : mouse_area.pressed ? Qt.darker(Style.pal.bg_surface, 1.3) : mouse_area.containsMouse ? Style.pal.visual_bg : Style.pill_chips ? "transparent" : Style.tab_outline.a > 0 ? Style.tab_active_bg : Style.pal.bg_surface
    border.width: 1
    border.color: Style.pill_chips || Style.tab_outline.a > 0 ? Style.chip_border : Style.pal.border

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: root.icon
            color: root.active ? Style.pal.bg_core : Style.pal.fg
            font.family: Style.font_family
            font.pixelSize: Style.font_size
        }

        Text {
            text: root.label
            color: root.active ? Style.pal.bg_core : Style.pal.fg
            font.bold: root.active
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            font.capitalization: Style.tab_caps || Style.caps_tracking > 0 ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: Style.caps_tracking > 0 ? Style.caps_tracking * 0.7 : Style.tab_caps ? Style.label_spacing * 0.6 : 0
        }

        Rectangle {
            id: key_cap
            visible: root.key_hint !== ""
            readonly property bool orb: Style.materia.key !== undefined
            readonly property bool pixel_ring: Style.pixel_border.a > 0
            readonly property int ring_width: KeyHints.cap_ring_width(Style)
            implicitWidth: key_cap.orb ? Math.max(16, key_label.implicitWidth + 8) : key_label.implicitWidth + 6 + key_cap.ring_width * 2
            // Other styles keep the fixed 16px cap; a pixel ring's 16px text needs more.
            implicitHeight: key_cap.pixel_ring ? Math.max(16, key_label.implicitHeight + key_cap.ring_width * 2) : 16
            radius: Style.key_round ? height / 2 : Style.radius(3)
            color: key_cap.orb ? "transparent" : root.active ? Style.pal.bg_core : Style.key_bg
            border.width: key_cap.orb ? 0 : key_cap.ring_width
            border.color: root.active ? Style.pal.border : Style.key_border

            MateriaOrb {
                visible: key_cap.orb
                anchors.fill: parent
                color: key_cap.orb ? Style.materia.key : "transparent"
            }

            Text {
                id: key_label
                anchors.centerIn: parent
                text: root.key_hint
                color: root.active && !key_cap.orb ? Style.pal.primary : Style.key_fg
                font.bold: key_cap.orb || Style.mono_font === Style.font_family
                font.family: KeyHints.cap_font_family(Style)
                font.pixelSize: KeyHints.cap_font_px(Style)
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
