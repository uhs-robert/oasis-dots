// home/quickshell/.config/quickshell/components/KeyBadge.qml
import QtQuick
import "../theme"
import "KeyHints.js" as KeyHints

Rectangle {
    id: root

    readonly property var st: Style.for_item(root)

    property string key: ""
    property string desc: ""
    // Set on a filled active tab so an outline badge takes the tab's text color; keycap badges keep theirs.
    property bool on_fill: false
    // Keeps the keyboard key beside its controller buttons, as the ? help does.
    property bool with_key: false
    // A bare key with no cap, e.g. a tab's jump digit.
    property bool plain: false
    property int font_px: 0
    readonly property bool pad: root.st.controller !== "" && KeyHints.controller_parts(root.st.controller, root.key, root.desc).length > 0
    readonly property bool tinted: root.on_fill && root.st.key_bg.a === 0 && !root.orb

    implicitWidth: root.pad ? pad_loader.implicitWidth : Math.max(implicitHeight, key_text.implicitWidth + 8)
    implicitHeight: root.pad ? Math.max(key_text.implicitHeight + 2, pad_loader.implicitHeight) : key_text.implicitHeight + 2
    width: implicitWidth
    height: implicitHeight
    radius: root.st.key_round ? height / 2 : Style.radius(3)
    readonly property bool cut: root.st.key_cut > 0 && !root.pad
    readonly property bool orb: root.st.materia.key !== undefined && !root.pad
    color: root.cut || root.orb || root.pad || root.plain ? "transparent" : root.st.key_bg
    border.width: root.cut || root.orb || root.pad || root.plain ? 0 : root.st.pixel_border.a > 0 ? 2 : 1
    border.color: root.tinted ? root.st.tab_active_fg : root.st.key_border

    Sheen {
        color_top: !root.plain && !root.pad && root.st.key_bg.a > 0 ? root.st.sheen : "transparent"
        corner: root.radius
        edge: 1
    }

    CutBox {
        visible: root.cut
        anchors.fill: parent
        cut_tl: root.st.key_cut
        cut_br: root.st.key_cut
        fill: root.st.key_bg
        stroke: root.tinted ? root.st.tab_active_fg : root.st.key_border
    }

    MateriaOrb {
        visible: root.orb
        anchors.fill: parent
        color: root.orb ? root.st.materia.key : "transparent"
    }

    Loader {
        id: pad_loader
        active: root.pad
        visible: active
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Row {
            spacing: 5

            ControllerBadge {
                anchors.verticalCenter: parent.verticalCenter
                controller: root.st.controller
                key: root.key
                desc: root.desc
                size: key_text.implicitHeight + 2
                // key_fg is ink for an orb; bare letters beside buttons take the orb's own color.
                text_color: root.st.materia.key !== undefined ? root.st.materia.key : key_text.color
                font_family: key_text.font.family
                font_size: key_text.font.pixelSize
            }

            Text {
                visible: root.with_key
                anchors.verticalCenter: parent.verticalCenter
                text: KeyHints.with_glyphs(root.key)
                color: root.st.text_muted
                font: key_text.font
            }
        }
    }

    Text {
        id: key_text
        visible: !root.pad
        anchors.centerIn: parent
        text: root.key
        color: root.tinted ? root.st.tab_active_fg : root.st.key_fg
        font.family: root.st.mono_font
        font.pixelSize: root.font_px > 0 ? root.font_px : root.st.fs(-5)
        font.bold: root.orb || root.st.mono_font === root.st.font_family
    }
}
