import QtQuick
import qs.theme
import qs.ui.effects
import "KeyHints.js" as KeyHints

Rectangle {
    id: root

    readonly property var st: Style.for_item(root)

    property string key: ""
    // Set on a filled active tab so an outline badge takes the tab's text color; keycap badges keep theirs.
    property bool on_fill: false
    // Keeps the keyboard key beside its controller buttons, as the ? help does.
    property bool with_key: false
    // A bare key with no cap, e.g. a tab's jump digit.
    property bool plain: false
    property int font_px: 0
    readonly property bool pad: root.st.controller !== "" && KeyHints.controller_parts(root.st.controller, root.key).length > 0
    readonly property bool tinted: root.on_fill && root.st.key_bg.a === 0 && !root.orb

    // Pixel fonts have no internal leading, so the cap grows with its ring or the ring covers the glyph.
    readonly property int ring_width: KeyHints.cap_ring_width(root.st)

    readonly property bool drawn: root.st.key_cap !== "none" && !root.pad && !root.plain && !root.orb

    // key_cap ps2_gloss: the glossy black of the pad buttons (styles/ps2/widgets/Ps2Button.qml) with its key tokens as the top colour.
    readonly property bool glossy: root.drawn && root.st.key_cap === "ps2_gloss"

    // The other drawn caps, each painted from one row of this table: a face gradient, a rim, a top highlight, an optional bottom lip.
    readonly property bool retro: root.drawn && !root.glossy
    readonly property var look: {
        switch (root.st.key_cap) {
        case "ps1_dome": return { top: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)), bottom: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.5)), edge: Theme.bg_shadow, hi: Qt.alpha(Theme.fg_strong, 0.18), round: 4, fg: Theme.fg_strong };
        case "snes_lavender": {
            const lav = Qt.tint("#9a90cc", Qt.alpha(Theme.magenta, 0.35));
            return { top: Qt.darker(lav, 1.35), bottom: lav, edge: Qt.darker(lav, 2.2), hi: Qt.alpha(Theme.fg_strong, 0.25), round: 4, fg: Theme.fg_strong };
        }
        case "nes_black": return { top: "#161616", bottom: "#161616", edge: "#6a6a6a", hi: "transparent", round: 0, fg: Qt.tint("#c8102e", Qt.alpha(Theme.red, 0.45)) };
        }
        return { top: "transparent", bottom: "transparent", edge: "transparent", hi: "transparent", round: 0, fg: "transparent" };
    }

    implicitWidth: root.pad ? pad_loader.implicitWidth : Math.max(implicitHeight, key_text.implicitWidth + KeyHints.cap_pad_w(root.st) + root.ring_width * 2)
    implicitHeight: root.pad ? Math.max(key_text.implicitHeight + 2, pad_loader.implicitHeight) : key_text.implicitHeight + root.ring_width * 2 + KeyHints.cap_gloss_h(root.st)
    width: implicitWidth
    height: implicitHeight
    radius: root.retro ? Math.min(root.look.round, height / 2) : root.st.key_round ? height / 2 : Style.radius(3)
    readonly property bool orb: root.st.materia.key !== undefined && !root.pad
    color: root.retro ? root.look.top : root.orb || root.pad || root.plain ? "transparent" : root.st.key_bg
    border.width: root.retro ? 1 : root.orb || root.pad || root.plain ? 0 : root.ring_width
    border.color: root.retro ? root.look.edge : root.tinted ? root.st.tab_active_fg : root.st.key_border
    gradient: root.retro ? retro_gradient : root.glossy ? gloss_gradient : null

    Gradient {
        id: gloss_gradient
        GradientStop { position: 0; color: root.st.key_bg }
        GradientStop { position: 1; color: Theme.bg_shadow }
    }

    Gradient {
        id: retro_gradient
        GradientStop { position: 0; color: root.look.top }
        GradientStop { position: 1; color: root.look.bottom }
    }

    // Top highlight, inset by half the corner so it stays inside the curve.
    Rectangle {
        visible: root.retro && root.look.hi.a > 0
        x: 1 + root.radius * 0.5
        y: 1
        width: parent.width - 2 - root.radius
        height: 1
        color: root.look.hi
    }

    Rectangle {
        visible: root.glossy
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.fg_strong, 0.14)
    }

    Rectangle {
        visible: root.glossy
        x: parent.width * 0.16
        y: 1.5
        width: parent.width * 0.68
        height: parent.height * 0.42
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, 0.26) }
            GradientStop { position: 1; color: Qt.alpha(Theme.fg_strong, 0) }
        }
    }

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
        anchors.verticalCenterOffset: root.retro ? -1 : 0
        text: root.key
        color: root.retro ? root.look.fg : root.tinted ? root.st.tab_active_fg : root.st.key_fg
        font.weight: root.glossy ? Font.DemiBold : Font.Normal
        font.family: KeyHints.cap_font_family(root.st)
        font.pixelSize: root.font_px > 0 ? root.font_px : KeyHints.cap_font_px(root.st)
        font.bold: root.orb || root.st.mono_font === root.st.font_family
    }
}
