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
    // with_key already shows the key, so a label beside each button would repeat it.
    readonly property string glyphs: root.with_key && root.st.controller_glyphs === "labeled" ? "all" : root.st.controller_glyphs
    readonly property bool pad: root.st.controller !== "" && KeyHints.controller_parts(root.st.controller, root.key, root.desc, root.glyphs).length > 0
    readonly property bool tinted: root.on_fill && root.st.key_bg.a === 0 && !root.orb

    // Pixel fonts have no internal leading, so the cap grows with its ring or the ring covers the glyph.
    readonly property int ring_width: KeyHints.cap_ring_width(root.st)

    implicitWidth: root.pad ? pad_loader.implicitWidth : Math.max(implicitHeight, key_text.implicitWidth + 6 + root.ring_width * 2)
    implicitHeight: root.pad ? Math.max(key_text.implicitHeight + 2, pad_loader.implicitHeight) : key_text.implicitHeight + root.ring_width * 2
    width: implicitWidth
    height: implicitHeight
    radius: root.st.key_round ? height / 2 : Style.radius(3)
    readonly property bool orb: root.st.materia.key !== undefined && !root.pad
    color: root.orb || root.pad || root.plain ? "transparent" : root.st.key_bg
    border.width: root.orb || root.pad || root.plain ? 0 : root.ring_width
    border.color: root.tinted ? root.st.tab_active_fg : root.st.key_border

    Sheen {
        color_top: !root.plain && !root.pad && root.st.key_bg.a > 0 ? root.st.sheen : "transparent"
        corner: root.radius
        edge: 1
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
                glyphs: root.glyphs
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
        font.family: KeyHints.cap_font_family(root.st)
        font.pixelSize: root.font_px > 0 ? root.font_px : KeyHints.cap_font_px(root.st)
        font.bold: root.orb || root.st.mono_font === root.st.font_family
    }
}
