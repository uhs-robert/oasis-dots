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
    // A footer or hint-bar key: in a style with no drawn cap it is bare text, as footers drew it before KeyBadge.
    property bool footer: false
    // Popup footers only: a style's footer_key_bg boxes the bare text; the hint bars never box.
    property bool footer_box: false
    // The boxed key is as tall as the footer's description text, not its own mono text.
    property real box_height: 0
    property color bare_color: root.st.footer_key_fg
    property bool bare_bold: false
    readonly property bool pad: root.st.controller !== "" && KeyHints.controller_parts(root.st.controller, root.key).length > 0
    readonly property bool bare: root.footer && !root.pad && !root.orb && !KeyHints.cap_is_drawn(root.st)
    readonly property bool boxed: root.bare && root.footer_box && root.st.footer_key_bg.a > 0
    readonly property bool tinted: root.on_fill && root.st.key_bg.a === 0 && !root.orb

    // Pixel fonts have no internal leading, so the cap grows with its ring or the ring covers the glyph.
    readonly property int ring_width: KeyHints.cap_ring_width(root.st)

    readonly property bool drawn: KeyHints.cap_is_drawn(root.st) && !root.pad && !root.plain && !root.orb

    // key_cap ps2_gloss: the glossy black of the pad buttons (styles/ps2/widgets/Ps2Button.qml) with its key tokens as the top colour.
    readonly property bool glossy: root.drawn && root.st.key_cap === "ps2_gloss"

    // One character on a PlayStation cap is a true circle, longer text a pill.
    readonly property bool ps_circle: root.drawn && KeyHints.cap_is_ps(root.st) && Array.from(root.key).length === 1

    // The other drawn caps, each painted from one row of this table: a face gradient, a rim, a top highlight.
    readonly property bool retro: root.drawn && !root.glossy
    readonly property var look: {
        switch (root.st.key_cap) {
        case "ps1_dome": return { top: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_core, 0.2)), bottom: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_muted, 0.5)), edge: Theme.bg_shadow, hi: Qt.alpha(Theme.fg_strong, 0.18), round: 999, fg: Theme.fg_strong };
        case "snes_pad": {
            const plastic = Qt.tint(Theme.fg_dim, Qt.alpha("#a4a4b4", 0.45));
            return { top: Qt.lighter(plastic, 1.15), bottom: plastic, edge: Qt.darker(plastic, 1.8), hi: Qt.alpha(Theme.fg_strong, 0.3), round: 999, fg: Theme.bg_crust };
        }
        case "nes_black": return { top: "#161616", bottom: "#161616", edge: "#6a6a6a", hi: "transparent", round: 0, fg: Qt.tint("#c8102e", Qt.alpha(Theme.red, 0.45)) };
        }
        return { top: "transparent", bottom: "transparent", edge: "transparent", hi: "transparent", round: 0, fg: "transparent" };
    }

    implicitWidth: root.bare ? key_text.implicitWidth + (root.boxed ? 8 : 0) : root.pad ? pad_loader.implicitWidth : root.ps_circle ? implicitHeight : Math.max(implicitHeight, key_text.implicitWidth + KeyHints.cap_pad_w(root.st) + root.ring_width * 2)
    implicitHeight: root.bare ? (root.boxed && root.box_height > 0 ? root.box_height : key_text.implicitHeight) : root.pad ? Math.max(key_text.implicitHeight + 2, pad_loader.implicitHeight) : key_text.implicitHeight + root.ring_width * 2 + KeyHints.cap_gloss_h(root.st)
    width: implicitWidth
    height: implicitHeight
    radius: root.retro ? Math.min(root.look.round, height / 2) : root.st.key_round ? height / 2 : Style.radius(3)
    readonly property bool orb: root.st.materia.key !== undefined && !root.pad
    color: root.retro ? root.look.top : root.orb || root.pad || root.plain || root.bare ? "transparent" : root.st.key_bg
    border.width: root.retro ? 1 : root.orb || root.pad || root.plain || root.bare ? 0 : root.ring_width
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

    Rectangle {
        visible: root.boxed
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: Style.radius(3)
        color: root.st.footer_key_bg
        border.width: root.st.rounded ? 1 : 0
        border.color: root.st.key_border
    }

    Sheen {
        color_top: !root.plain && !root.bare && !root.pad && root.st.key_bg.a > 0 ? root.st.sheen : "transparent"
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
        color: root.bare ? root.bare_color : root.retro ? root.look.fg : root.tinted ? root.st.tab_active_fg : root.st.key_fg
        font.weight: root.glossy ? Font.DemiBold : Font.Normal
        font.family: root.bare ? (root.boxed ? root.st.mono_font : root.st.font_family) : KeyHints.cap_font_family(root.st)
        font.pixelSize: root.font_px > 0 ? root.font_px : KeyHints.cap_font_px(root.st)
        font.bold: root.bare ? root.bare_bold : root.orb || root.st.mono_font === root.st.font_family
    }
}
