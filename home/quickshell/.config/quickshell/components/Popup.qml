// home/quickshell/.config/quickshell/components/Popup.qml
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"

PanelWindow {
    id: root

    property string popup_name: ""
    property real preferred_width: 260
    // Content height; the base adds the style's title tab and footer around it.
    property real body_height: 0
    property string title: popup_name.toUpperCase()
    property string footer_hint: ""
    // Styles with a `small` block draw "small" popups apart from "large" ones (notifications, weather, media).
    property string size_class: "small"
    readonly property var st: root.size_class === "small" ? Style.small : Style
    // Set while a native menu from this popup is open; focus returns to the popup when it closes.
    property bool suspend_grab: false

    property var tabs: []
    property int current_tab: 0
    // The current tab's sub-view names; each tab keeps its own current_sub across tab switches.
    property var sub_views: []
    property int current_sub: 0
    // gg/G emit jump_first/jump_last only while set; the popup owns what first and last mean.
    property bool jumps_enabled: false
    signal jump_first()
    signal jump_last()

    property var sub_memory: ({})
    property double last_g_ms: 0

    onTabsChanged: if (current_tab >= tabs.length) current_tab = 0
    onCurrent_tabChanged: current_sub = sub_memory[current_tab] || 0
    onCurrent_subChanged: sub_memory[current_tab] = current_sub

    function set_tab(i) {
        if (tabs.length > 0) current_tab = Math.max(0, Math.min(tabs.length - 1, i));
    }

    function step_tab(delta) {
        if (tabs.length > 0) current_tab = (current_tab + delta + tabs.length) % tabs.length;
    }

    function step_sub(delta) {
        if (sub_views.length > 0) current_sub = (current_sub + delta + sub_views.length) % sub_views.length;
    }

    // Runs after the popup's own handlers: keys reach it only when nothing deeper accepted them.
    function handle_shared_key(event) {
        const focus_item = content_scope.Window.activeFocusItem;
        if (focus_item && "cursorPosition" in focus_item) return;
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
        if (event.key === Qt.Key_Q) {
            Popups.close();
        } else if (tabs.length > 0 && event.key === Qt.Key_BracketLeft) {
            step_tab(-1);
        } else if (tabs.length > 0 && event.key === Qt.Key_BracketRight) {
            step_tab(1);
        } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + Math.min(9, tabs.length)) {
            set_tab(event.key - Qt.Key_1);
        } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (tabs.length > 0 || sub_views.length > 0)) {
            step_sub(back ? -1 : 1);
        } else if (jumps_enabled && event.key === Qt.Key_G) {
            if (event.modifiers & Qt.ShiftModifier) {
                jump_last();
            } else {
                const now_ms = Date.now();
                if (now_ms - last_g_ms < 500) {
                    last_g_ms = 0;
                    jump_first();
                } else {
                    last_g_ms = now_ms;
                }
            }
        } else {
            return;
        }
        event.accepted = true;
    }

    // Never narrower than the island's bottom edge (its body, between the slants).
    implicitWidth: Math.max(Style.px(preferred_width) + root.st.lcd_margin * 2, island_width, root.st.popup_min_width)
    implicitHeight: body_height + header_height + footer_height + root.st.frame_drop
    default property alias content: content_scope.data

    readonly property bool wanted: Popups.open_name === root.popup_name && Popups.open_screen_name !== ""

    // Latched on open so the popup keeps its place and color while the close animation plays.
    property var held_anchor: null
    property string held_screen_name: ""
    property color held_color: Theme.bg_mantle

    // The anchor is the island's body; its parent is the Island, which knows which end caps it has.
    readonly property var island: held_anchor ? held_anchor.parent : null
    readonly property real island_width: held_anchor ? held_anchor.width : 0
    readonly property bool island_cap_left: !!island && island.cap_left === true
    readonly property bool island_cap_right: !!island && island.cap_right === true
    // cap_right-only = a left island, flush with the screen's left edge; cap_left-only = a right island.
    readonly property string side: (island_cap_left && island_cap_right) ? "center" : island_cap_right ? "left" : island_cap_left ? "right" : "center"

    // A layer surface pinned to the screen edge: xdg popups landed a few px short of it.
    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    anchors.top: true
    anchors.left: side === "left"
    anchors.right: side === "right"
    exclusiveZone: 0
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "quickshell-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property int line_height: root.st.accent_height
    readonly property bool has_title: root.st.show_title && title !== ""
    readonly property bool has_footer: root.st.show_footer && footer_hint !== ""
    // Room kept clear of the corner brackets around the title.
    readonly property real bracket_pad: root.st.frame_brackets.a > 0 ? 4 : 0
    readonly property bool lcd: root.st.lcd_top.a > 0
    readonly property real title_gap: root.st.title_rule.a > 0 ? 6 : 0
    readonly property real engraving_height: root.st.frame_engraving !== "" ? engraving.implicitHeight + 4 : 0
    readonly property real header_height: (has_title ? title_tab.height + bracket_pad + root.st.inset_pad + title_gap : 0) + root.st.lcd_margin * 2
    readonly property real footer_height: (has_footer ? base_footer.implicitHeight + 10 + root.st.inset_pad : 0) + root.st.lcd_margin * 2 + engraving_height
    property real line_progress: 0
    property real drop_progress: 0

    onWantedChanged: {
        if (wanted) {
            close_anim.stop();
            held_anchor = Popups.open_anchor;
            held_screen_name = Popups.open_screen_name;
            held_color = Popups.open_color;
            visible = true;
            open_anim.restart();
            content_scope.forceActiveFocus();
        } else if (visible) {
            open_anim.stop();
            close_anim.restart();
        }
    }

    // Plays once per open or close: the accent line draws out to the island's width from the screen edge (center: the middle),
    // then the body drops from it; closing folds back the same way.
    Timer {
        interval: 530
        repeat: true
        running: root.st.caret_blink && root.visible && root.wanted && Power.on_ac
        onTriggered: Style.caret_phase = !Style.caret_phase
        onRunningChanged: Style.caret_phase = true
    }

    SequentialAnimation {
        id: open_anim
        NumberAnimation { target: root; property: "line_progress"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "drop_progress"; to: 1; duration: 190; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: close_anim
        NumberAnimation { target: root; property: "drop_progress"; to: 0; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "line_progress"; to: 0; duration: 90; easing.type: Easing.InCubic }
        ScriptAction {
            script: {
                root.visible = false;
                root.held_anchor = null;
            }
        }
    }

    function edge_x(w) {
        return side === "right" ? width - w : side === "left" ? 0 : (width - w) / 2;
    }

    Rectangle {
        id: accent_line
        readonly property real w: (root.st.accent_full_width ? root.width : root.island_width) * root.line_progress
        x: root.edge_x(w)
        width: w
        height: root.line_height
        color: root.st.accent_color
        opacity: root.line_progress > 0 ? 1 : 0
        z: 1
    }

    Item {
        id: reveal
        // Tells the components inside which token set to read (Style.for_item).
        readonly property string size_class: root.size_class
        y: root.line_height
        width: root.width
        height: (root.height - root.line_height) * root.drop_progress
        clip: true

        Rectangle {
            visible: root.st.frame_drop > 0
            y: root.st.frame_drop
            width: root.width
            height: root.height - root.line_height - root.st.frame_drop
            color: Theme.bg_shadow
            bottomLeftRadius: root.st.frame_radius
            bottomRightRadius: root.st.frame_radius
        }

        Item {
            width: root.width
            height: root.height - root.line_height - root.st.frame_drop

            // Reads as the island unfolding downward: its color, joined flush under the accent line.
            Rectangle {
                anchors.fill: parent
                color: root.st.frame_chamfer > 0 || root.st.frame_visor ? "transparent" : root.st.frame_follows_island ? root.held_color : root.st.frame_color
                bottomLeftRadius: root.st.frame_radius
                bottomRightRadius: root.st.frame_radius
                border.width: root.st.frame_visor || root.st.frame_chamfer > 0 ? 0 : root.st.frame_border_width
                border.color: root.st.frame_border_color
            }

            VisorGlass {
                anchors.fill: parent
            }

            Shape {
                id: frame_glow
                visible: root.st.frame_glow.a > 0
                anchors.fill: parent
                anchors.margins: root.st.frame_border_width

                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: frame_glow.width / 2
                        centerY: 0
                        focalX: frame_glow.width / 2
                        focalY: 0
                        centerRadius: Math.max(frame_glow.width * 0.6, Math.min(frame_glow.height, 420))
                        focalRadius: 0
                        GradientStop { position: 0; color: root.st.frame_glow }
                        GradientStop { position: 0.72; color: root.st.frame_color }
                    }
                    PathRectangle { width: frame_glow.width; height: frame_glow.height }
                }
            }

            FrameShade {
                anchors.fill: parent
                anchors.margins: root.st.frame_border_width
                bottom_radius: Math.max(0, root.st.frame_radius - root.st.frame_border_width)
                chamfer: root.st.frame_chamfer
            }

            CornerBrackets {
                anchors.fill: parent
            }

            FrameInset {
                bottom_radius: root.st.frame_radius
            }

            // The watch face: a shaded panel with static scan rows, and the engraving on the bezel below it.
            Rectangle {
                id: lcd_panel
                readonly property real edge: root.st.inset_pad + root.st.lcd_margin
                visible: root.lcd
                x: lcd_panel.edge
                y: lcd_panel.edge
                width: parent.width - lcd_panel.edge * 2
                height: parent.height - lcd_panel.edge * 2 - root.engraving_height
                radius: 8
                border.width: 1
                border.color: Qt.alpha(Theme.bg_shadow, 0.6)
                clip: true
                gradient: Gradient {
                    GradientStop { position: 0; color: root.st.lcd_top }
                    GradientStop { position: 1; color: root.st.lcd_bottom }
                }

                Repeater {
                    model: root.lcd ? Math.max(0, Math.ceil(lcd_panel.height / 3)) : 0

                    Rectangle {
                        required property int index
                        y: index * 3
                        width: lcd_panel.width
                        height: 1
                        color: root.st.lcd_scan
                    }
                }
            }

            Text {
                id: engraving
                visible: root.st.frame_engraving !== ""
                x: lcd_panel.edge + 6
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.st.inset_pad + 2
                text: root.st.frame_engraving
                color: root.st.frame_border_color
                font.family: Style.title_font_family
                font.pixelSize: 9
                font.letterSpacing: 2.5
            }

            // Everything drawn on the frame; styles with a glow or text shadow render it as one layer.
            Item {
                id: glow_layer
                readonly property bool layered: root.st.glow || root.st.text_shadow.a > 0
                anchors.fill: parent
                layer.enabled: glow_layer.layered
                opacity: glow_layer.layered ? 0 : 1


                Rectangle {
                    id: title_tab
                    visible: root.has_title
                    x: (root.st.fade_fills ? root.st.frame_border_width : root.bracket_pad * 1.5) + root.st.inset_pad + root.st.lcd_margin * 2
                    y: (root.st.fade_fills ? root.st.frame_border_width : root.bracket_pad) + root.st.inset_pad + root.st.lcd_margin * 2
                    width: root.st.fade_fills ? parent.width - root.st.frame_border_width * 2 : title_text.implicitWidth + 20
                    height: title_text.implicitHeight + 4
                    color: root.st.fade_fills ? "transparent" : root.st.title_bg

                    FadeFill {
                        visible: root.st.fade_fills
                        fill: root.st.title_bg
                    }

                    Text {
                        id: title_text
                        anchors.centerIn: root.st.fade_fills ? undefined : parent
                        x: 10
                        y: (parent.height - height) / 2
                        text: root.st.title_prefix + root.title + (Style.caret_phase ? root.st.title_suffix : " ".repeat(root.st.title_suffix.length))
                        color: root.st.title_fg
                        font.family: root.st.title_font_family
                        font.pixelSize: root.st.font_size - 2
                        font.bold: root.st.title_font_family === root.st.font_family
                        font.letterSpacing: root.st.title_spacing
                        style: root.st.title_glow.a > 0 ? Text.Outline : Text.Normal
                        styleColor: root.st.title_glow
                    }
                }

                Text {
                    visible: root.has_title && root.st.title_readout !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: (root.lcd ? root.st.lcd_margin * 2 : 12) + root.bracket_pad + root.st.inset_pad
                    y: title_tab.y + (title_tab.height - height) / 2
                    text: root.st.title_readout.replace("{code}", root.title.slice(0, 3))
                    color: root.st.title_readout_fg.a > 0 ? root.st.title_readout_fg : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 5
                    font.letterSpacing: 1
                }

                Rectangle {
                    visible: root.has_title && root.st.title_rule.a > 0
                    x: title_tab.x
                    y: title_tab.y + title_tab.height + 2
                    width: parent.width - title_tab.x * 2
                    height: 1
                    color: root.st.title_rule
                }

                MenuFooter {
                    id: base_footer
                    visible: root.has_footer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12 + root.st.lcd_margin
                    anchors.rightMargin: 12 + root.st.lcd_margin
                    anchors.bottomMargin: 8 + root.st.inset_pad + root.st.lcd_margin * 2 + root.engraving_height
                    text: root.footer_hint
                }

                FocusScope {
                    id: content_scope
                    anchors.fill: parent
                    anchors.topMargin: root.header_height
                    anchors.bottomMargin: root.footer_height
                    anchors.leftMargin: root.st.lcd_margin
                    anchors.rightMargin: root.st.lcd_margin
                    focus: true

                    Keys.onEscapePressed: Popups.close()
                    Keys.onPressed: event => root.handle_shared_key(event)
                }
            }

            // Phosphor bloom: a blurred copy in the glow color under a lightly tinted sharp copy.
            // Loaders rebuild the effects per style; MultiEffects left hidden across a style switch stopped drawing.
            Loader {
                anchors.fill: glow_layer
                active: root.st.glow
                sourceComponent: Item {
                    MultiEffect {
                        anchors.fill: parent
                        source: glow_layer
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blur: 0.5
                        blurMax: 12
                        brightness: 0.2
                        colorization: 1
                        colorizationColor: root.st.glow_color
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: glow_layer
                        autoPaddingEnabled: false
                        colorization: root.st.glow_tint
                        colorizationColor: Theme.theme_primary_light
                    }
                }
            }

            Loader {
                anchors.fill: glow_layer
                active: !root.st.glow && root.st.text_shadow.a > 0
                sourceComponent: MultiEffect {
                    source: glow_layer
                    autoPaddingEnabled: false
                    shadowEnabled: true
                    shadowBlur: 0
                    shadowOpacity: 1
                    shadowColor: root.st.text_shadow
                    shadowHorizontalOffset: 2
                    shadowVerticalOffset: 2
                }
            }

            // Static scanlines; nothing animates them.
            Item {
                visible: root.st.scanlines
                anchors.fill: parent

                Repeater {
                    model: root.st.scanlines ? Math.max(0, Math.ceil(parent.height / 3)) : 0

                    Rectangle {
                        required property int index
                        y: index * 3
                        width: parent.width
                        height: 1
                        color: root.st.scanline_color
                    }
                }
            }

            Dither {
                anchors.fill: parent
                anchors.margins: root.st.frame_border_width
                color: root.st.dither
                radius: root.st.frame_radius
            }
        }
    }

    onSuspend_grabChanged: if (!root.suspend_grab && root.visible) content_scope.forceActiveFocus()
}
