pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.theme
import "../../ui/frames/DrawerGeometry.js" as Drawer
import "../../ui/frames/FrameGeometry.js" as FrameGeometry
import qs.styles.neovim.widgets as Neovim
import qs.styles.goldeneye.widgets as Goldeneye
import qs.ui.effects
import qs.ui.frames
import qs.ui.keys
import qs.features.bar
import qs.features.popups.frames

// HyprVim's which-key HUD over its `hyprvim_whichkey` IPC target, drawn in the active style. With the screen frame on it
// is a drawer: it grows out of the frame edge its position names and folds back on hide (a plain "center" names no edge
// and hangs from the bottom, as "bottom-center").
PanelWindow {
    id: root

    property var payload: ({})
    property bool wanted: false

    readonly property var items: root.payload.items || []
    readonly property string position: root.payload.position || "bottom-right"
    readonly property string title: {
        const t = root.payload.title || "";
        return Style.show_title ? t.toUpperCase() : t;
    }
    readonly property string footer_hint: (root.payload.footer || []).map(f => ({ ESC: "Esc", BS: "Backspace", RET: "Enter", TAB: "Tab", SPACE: "space" }[f.key] || f.key) + " " + f.desc).join(" · ")
    // goldeneye draws the HUD as a watch panel with boxed keys.
    readonly property bool watch: Style.frame_watch
    readonly property bool has_footer: Style.show_footer && root.footer_hint !== ""

    readonly property int gap: root.drawer ? 0 : Style.px(18)
    readonly property int text_size: Style.whichkey_size > 0 ? Style.whichkey_size : Style.fs(-2)
    readonly property int key_size: Style.whichkey_size > 0 ? Style.whichkey_size : Style.fs(-5)
    readonly property int row_height: Math.max(Style.px(22), root.text_size + Style.px(8))
    readonly property real key_box: root.watch ? Math.max(key_metrics.height + 10, key_metrics.advanceWidth + 16) : 0
    readonly property real screen_width: root.screen ? root.screen.width : 1920
    readonly property real screen_height: root.screen ? root.screen.height : 1080

    // The payload's columns assume eww's row height, so add columns when this style's rows run taller.
    readonly property int columns: {
        const rows_fit = Math.max(1, Math.floor((root.screen_height * 0.85 - Style.px(120)) / root.row_height));
        const wanted_cols = Math.max(root.payload.columns || 1, Math.ceil(root.items.length / rows_fit));
        return Math.max(1, Math.min(4, wanted_cols));
    }
    readonly property string longest_key: root.items.reduce((a, item) => item.key.length > a.length ? item.key : a, "")
    readonly property real key_width: root.watch ? root.key_box : Style.controller !== "" ? Math.max(key_metrics.height + 2, key_measure.implicitWidth) : Math.max(key_metrics.height + 2, key_metrics.advanceWidth + 8)
    readonly property real arrow_space: Style.whichkey_arrow !== "" ? arrow_metrics.advanceWidth + Style.px(6) : 0
    readonly property real desc_max_width: Math.max(Style.px(80), (root.screen_width * 0.9 - frame.pad_x * 2) / root.columns - root.key_width - root.arrow_space - Style.px(24))

    screen: {
        const by_payload = Quickshell.screens.find(s => s.name === root.payload.screen);
        if (by_payload) return by_payload;
        const mon = Hyprland.focusedMonitor;
        return (mon && Quickshell.screens.find(s => s.name === mon.name)) || null;
    }
    visible: false
    color: "transparent"
    // No explicit exclusiveZone: even 0 overrides Ignore, so the frame's zones would push a drawer inward.
    exclusionMode: root.drawer ? ExclusionMode.Ignore : ExclusionMode.Normal
    anchors.top: root.drawer ? root.drawer_place.anchor_top : root.position.startsWith("top")
    anchors.bottom: root.drawer ? root.drawer_place.anchor_bottom : root.position.startsWith("bottom")
    anchors.left: root.drawer ? root.drawer_place.anchor_left : root.position.endsWith("left")
    anchors.right: root.drawer ? root.drawer_place.anchor_right : root.position.endsWith("right")
    margins.top: root.drawer ? root.drawer_place.margin_top : root.gap - root.shadow_pad
    margins.bottom: root.drawer ? root.drawer_place.margin_bottom : root.gap - root.shadow_pad
    margins.left: root.drawer ? root.drawer_place.margin_left : root.gap - root.shadow_pad
    margins.right: root.drawer ? root.drawer_place.margin_right : root.gap - root.shadow_pad
    // Room on every side for a soft shadow, taken out of the gap so the frame stays put.
    readonly property int shadow_pad: !root.drawer && Style.frame_shadow.a > 0 ? Math.min(Style.frame_drop, root.gap) : 0
    implicitWidth: root.drawer ? root.drawer_full.surface.width : frame.width + root.shadow_pad * 2
    // The header takes the bar's submap colour: fills get it under dark ink, plain titles take it as text.
    readonly property bool tinted: SubmapState.active || Style.bar_lualine
    readonly property color header_color: SubmapState.bar_color
    readonly property bool filled_title: Style.show_title && Style.title_bg.a > 0

    // Floating frames set the title chip into the top border, half of it above the frame.
    readonly property bool float_title: !root.drawer && Style.border_title && Style.show_title
    readonly property real float_top: root.float_title ? Math.round(title_tab.height / 2) : 0
    implicitHeight: root.drawer ? root.drawer_full.surface.height : frame.height + (root.shadow_pad > 0 ? root.shadow_pad * 2 : Style.frame_drop) + root.float_top

    // With the frame on, the payload's vertical part names the edge the drawer hangs from and its horizontal part the end
    // that is a pocket against the side band (the other end is a fillet; "center" fillets at both).
    readonly property string drawer_position: root.position === "center" ? "bottom-center" : root.position
    readonly property var screen_frame: root.screen && (root.drawer_position.startsWith("top") || root.drawer_position.startsWith("bottom")) ? ScreenFrames.layout_for(root.screen) : null
    readonly property bool drawer: root.screen_frame !== null
    readonly property bool from_bottom: root.drawer_position.startsWith("bottom")
    readonly property string side: root.drawer_position.endsWith("left") ? "left" : root.drawer_position.endsWith("right") ? "right" : "center"
    readonly property var drawer_profile: root.drawer ? Style.screen_frame_profile : null
    readonly property real drawer_fillet: root.drawer ? Drawer.fillet_of(root.drawer_profile) : 0
    readonly property real drawer_cover: Drawer.cover_depth(Style.bar_border_width, Style.bar_inset_gap, Style.bar_inset_width)
    readonly property var drawer_hole: root.screen_frame ? FrameGeometry.hole_rect(root.screen_frame) : null
    readonly property var drawer_kinds: Drawer.end_kinds(root.side, false)
    readonly property real panel_width: frame.natural_width
    readonly property real panel_height: frame.natural_height
    function drawer_spec(extent) {
        return Object.assign({
            edge: root.from_bottom ? "bottom" : "top",
            body_length: root.drawer_hole ? Drawer.body_length(root.side, root.panel_width, root.drawer_hole.w, root.drawer_fillet) : root.panel_width,
            body_depth: root.panel_height,
            extent: extent,
            start_kind: root.drawer_kinds.start,
            end_kind: root.drawer_kinds.end,
            cover: root.drawer_cover
        }, Drawer.profile_fields(root.drawer_profile));
    }
    // The window follows the full drawer, so it never resizes while the shape grows inside it. Never null, so a frame
    // switched off under an open window cannot leave DrawerShape without a layout.
    readonly property var drawer_full: Drawer.drawer_layout(root.drawer_spec(root.panel_height))
    readonly property var drawer_layout: Drawer.drawer_layout(root.drawer_spec(root.drawer ? root.panel_height * root.progress : 0))
    readonly property var drawer_body: Drawer.body_rect(root.drawer_layout)
    readonly property var drawer_place: Drawer.place(root.side, root.from_bottom, root.drawer_hole, root.screen_frame ? FrameGeometry.seam_of(root.screen_frame, root.from_bottom ? "bottom" : "top") : 0, root.screen_width, root.screen_height, root.drawer_cover, root.drawer_full.length)
    // Where the drawer's texture tiles from, so it runs on from the frame's (DrawerShape).
    readonly property var drawer_texture_origin: Drawer.texture_origin(root.side, root.from_bottom, !!root.screen_frame && root.screen_frame.edge === "bottom", root.drawer_place, root.screen_width, root.screen_height, root.drawer_full.length)
    readonly property bool drawer_translucent: root.drawer && Style.islands_translucent
    // Lets the frame and the strip leave their lines out under the window, while it is mapped.
    DrawerWindowPublisher {
        screen_name: root.screen ? root.screen.name : ""
        rect: root.drawer_translucent && root.visible ? Drawer.window_rect(root.side, root.from_bottom, root.drawer_place, root.screen_width, root.screen_height, root.width, root.drawer_layout.drawn_depth) : null
    }

    // How far the drawer has grown out of the frame, 0 to 1.
    property real progress: 0
    // The place the drawer hangs from; a change of any part restarts it from closed rather than sliding across.
    readonly property string place_key: root.drawer ? (root.screen ? root.screen.name : "") + "/" + root.drawer_position : ""
    // Set while a payload is applied, whose open_now follows; any other change of place (focus moving the screen under a
    // payload that names none) is handled here.
    property bool loading_payload: false
    onPlace_keyChanged: {
        if (root.place_key === "" || !root.visible) return;
        open_anim.stop();
        close_anim.stop();
        root.progress = 0;
        if (root.loading_payload) return;
        // A drawer folding back has nothing to reopen for.
        if (root.wanted) root.open_now();
        else root.visible = false;
    }
    mask: Region {}
    WlrLayershell.namespace: "quickshell-whichkey"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function show_payload(path: string): void {
        root.wanted = true;
        payload_file.path = path;
        payload_file.reload();
    }

    // Instant without the frame; with it the drawer folds back, and a show arriving first reverses it.
    function hide_now(): void {
        root.wanted = false;
        open_anim.stop();
        if (root.drawer && root.visible) {
            close_anim.restart();
        } else {
            close_anim.stop();
            root.progress = 0;
            root.visible = false;
        }
    }

    function open_now(): void {
        const was_open = root.visible && !close_anim.running;
        close_anim.stop();
        root.visible = true;
        if (root.drawer) open_anim.restart();
        else root.progress = 1;
        if (!was_open && burst_loader.item) burst_loader.item.play();
    }

    // Starts from the payload's load, not from show_payload, which would flash the previous payload.
    FileView {
        id: payload_file
        printErrors: false
        onLoaded: {
            if (!root.wanted) return;
            try {
                const next = JSON.parse(text());
                if ((next.items || []).length === 0) {
                    root.hide_now();
                    return;
                }
                root.loading_payload = true;
                root.payload = next;
                root.loading_payload = false;
                root.open_now();
            } catch (e) {
                console.warn("WhichKey: invalid payload (" + e + ")");
            }
        }
        onLoadFailed: root.hide_now()
    }

    NumberAnimation {
        id: open_anim
        target: root
        property: "progress"
        to: 1
        duration: 190
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: close_anim
        NumberAnimation { target: root; property: "progress"; to: 0; duration: 120; easing.type: Easing.InCubic }
        ScriptAction { script: if (!root.wanted) root.visible = false }
    }

    TextMetrics {
        id: arrow_metrics
        font.family: Style.font_family
        font.pixelSize: root.text_size
        text: Style.whichkey_arrow
    }

    TextMetrics {
        id: key_metrics
        font.family: Style.mono_font
        font.pixelSize: root.key_size
        font.bold: Style.mono_font === Style.font_family
        text: root.longest_key
    }

    // Controller buttons change a badge's width, so the key column sizes from the badges as drawn.
    Column {
        id: key_measure
        opacity: 0
        enabled: false

        Repeater {
            model: Style.controller !== "" ? root.items : []

            KeyBadge {
                required property var modelData
                key: modelData.key
                desc: modelData.desc || ""
                font_px: Style.whichkey_size
            }
        }
    }

    Loader {
        active: root.drawer
        sourceComponent: DrawerShape {
            layout: root.drawer_layout
            screen_name: root.screen ? root.screen.name : ""
            translucent: root.drawer_translucent
            texture_origin: root.drawer_texture_origin
            frame: root.screen_frame
        }
    }

    // The drawer's body uncovers the content as it grows; floating, this is the whole window and clips nothing.
    Item {
        id: reveal
        x: root.drawer ? root.drawer_body.x : 0
        y: root.drawer ? root.drawer_body.y : 0
        width: root.drawer ? root.drawer_body.width : root.width
        height: root.drawer ? root.drawer_body.height : root.height
        clip: root.drawer

        Rectangle {
            visible: !root.drawer && Style.frame_drop > 0 && Style.frame_shadow.a === 0
            y: frame.y + Style.frame_drop
            width: frame.width
            height: frame.height
            radius: frame.radius
            color: Style.pal.bg_shadow
        }

        Loader {
            active: !root.drawer && Style.frame_shadow.a > 0
            x: frame.x + 4
            y: frame.y + 4
            width: frame.width - 8
            height: frame.height
            sourceComponent: RectangularShadow {
                blur: root.shadow_pad
                radius: frame.radius
                color: Style.frame_shadow
            }
        }

        StyledFrame {
            id: frame
            st: Style
            // A drawer's content rides out with its far edge instead of staying put while the body uncovers it.
            x: root.drawer ? 0 : root.shadow_pad
            y: root.drawer ? (root.from_bottom ? 0 : reveal.height - root.panel_height) : root.shadow_pad + root.float_top
            drawer: root.drawer

            readonly property int pad_x: Style.px(14)
            readonly property int pad_y: Style.px(8)
            readonly property real top_edge: Math.max(Style.accent_height, Style.frame_border_width)
            readonly property real title_x: Style.fade_fills || Style.rounded && !Style.title_case ? frame.radius : 0
            // The watch panel's corner bevels; header text stays inside them.
            readonly property real watch_room: root.watch ? 12 : 0
            // The inner ring's room below the accent line, which already covers the border.
            readonly property real ring_pad: Style.inset_pad > 0 ? Style.inset_pad - Style.frame_border_width : 0
            readonly property bool banded: Style.show_title && Style.title_strip.a > 0
            readonly property real band_height: Math.max(26, title_tab.height + 4)
            readonly property real header_height: frame.banded ? frame.band_height + 4 + Style.inset_pad : root.float_title ? root.float_top : title_tab.height + frame.ring_pad

            // Wide enough for the whole title in the header variant the style draws.
            readonly property real header_min: frame.banded ? (band_loader.item ? band_loader.item.min_width : 0) + (Style.inset_pad + Style.frame_border_width) * 2
                : root.float_title ? (border_loader.item ? border_loader.item.implicitWidth : 0) + 24
                : title_text.implicitWidth + 20 + title_x * 2 + Style.inset_pad * 2 + frame.watch_room * 2 + (readout.visible ? readout.implicitWidth + 16 : 0)
            readonly property real natural_width: Math.max(body.implicitWidth + pad_x * 2, frame.header_min) + Style.slant_room
            readonly property real natural_height: top_edge + header_height + body.implicitHeight + pad_y * 2 + Style.slant_room
            width: root.drawer ? root.drawer_body.width : frame.natural_width
            height: frame.natural_height
            radius: Style.frame_radius
            island_color: Style.pal.bg_mantle
            inset_top_offset: frame.top_edge - Style.frame_border_width

            decor: [
                Rectangle {
                    visible: !root.drawer
                    x: frame.radius
                    width: frame.width - frame.radius * 2
                    height: Style.accent_height
                    color: Style.accent_color
                },

                Loader {
                    anchors.fill: parent
                    active: root.watch
                    sourceComponent: Goldeneye.PopupPanel {
                        st: Style
                        edge: 5
                        cut: frame.watch_room
                    }
                }
            ]

            Loader {
                id: band_loader
                active: frame.banded
                x: Style.inset_pad + Style.frame_border_width
                y: x
                width: frame.width - x * 2
                height: frame.band_height
                sourceComponent: TitleStrip {
                    title: root.title
                    title_color: root.tinted ? root.header_color : "transparent"
                    closable: false
                }
            }

            Rectangle {
                id: title_tab
                opacity: frame.banded || root.float_title ? 0 : 1
                x: frame.title_x + Style.inset_pad + frame.watch_room
                y: frame.top_edge + frame.ring_pad
                width: Style.fade_fills ? frame.width - frame.title_x * 2 : title_text.width + 20
                height: title_text.implicitHeight + 4
                color: !Style.show_title || Style.fade_fills ? "transparent" : root.tinted && root.filled_title ? root.header_color : Style.title_bg

                FadeFill {
                    visible: Style.show_title && Style.fade_fills
                    fill: root.tinted && root.filled_title ? Qt.alpha(root.header_color, Style.title_bg.a) : Style.title_bg
                }

                Text {
                    id: title_text
                    x: 10
                    y: (parent.height - height) / 2
                    width: Math.max(0, Math.min(implicitWidth, frame.width - title_tab.x - x - frame.title_x - frame.watch_room - 10 - (readout.visible ? readout.implicitWidth + 16 : 0)))
                    elide: Text.ElideRight
                    text: Style.title_prefix + Style.title_text(root.title) + (Style.caret_phase ? Style.title_suffix : " ".repeat(Style.title_suffix.length))
                    color: !root.tinted ? (Style.show_title ? Style.title_fg : Style.accent_color) : !Style.show_title || !root.filled_title ? root.header_color : Style.fade_fills ? Style.title_fg : Style.pal.bg_crust
                    font.family: Style.title_font_family
                    font.pixelSize: Style.title_size > 0 ? Style.title_size : Style.fs(-2)
                    font.weight: Style.title_weight > 0 ? Style.title_weight : Style.title_font_family === Style.font_family ? Font.Bold : Font.Normal
                    font.letterSpacing: Style.show_title ? Style.title_spacing : 0
                }
            }

            Loader {
                id: border_loader
                active: root.float_title
                x: 12
                y: -root.float_top
                sourceComponent: Neovim.BorderTitle {
                    title: Style.title_text(root.title)
                    fill: root.tinted ? root.header_color : Style.title_bg
                    ink: root.tinted ? Style.pal.bg_crust : Style.title_fg
                }
            }

            Text {
                id: readout
                visible: Style.show_title && Style.title_readout !== ""
                anchors.right: parent.right
                anchors.rightMargin: frame.title_x + 10 + frame.watch_room
                y: title_tab.y + (title_tab.height - height) / 2
                text: Style.title_readout.replace("{code}", root.title.slice(0, 3))
                color: Style.title_readout_fg.a > 0 ? Style.title_readout_fg : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1
            }

            ColumnLayout {
                id: body
                x: frame.pad_x
                y: frame.top_edge + frame.header_height + frame.pad_y
                spacing: Style.px(6)

                GridLayout {
                    columns: root.columns
                    columnSpacing: Style.px(24)
                    rowSpacing: 0

                    Repeater {
                        model: root.items

                        Item {
                            id: row
                            required property var modelData

                            Layout.preferredWidth: root.key_width + Style.px(8) + root.arrow_space + desc_text.width
                            Layout.preferredHeight: root.row_height

                            Rectangle {
                                visible: root.watch
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.key_box
                                height: root.row_height - Style.px(4)
                                color: row.modelData.group ? Style.pal.fg_strong : Style.selection_bg
                                border.width: 1
                                border.color: row.modelData.destructive ? Style.pal.error : Style.selection_border

                                Text {
                                    anchors.centerIn: parent
                                    text: row.modelData.key
                                    color: row.modelData.group ? Style.pal.bg_core : row.modelData.destructive ? Style.pal.error : Style.pal.fg_strong
                                    font.family: Style.mono_font
                                    font.pixelSize: root.key_size
                                    font.bold: true
                                }
                            }

                            KeyBadge {
                                visible: !root.watch
                                anchors.verticalCenter: parent.verticalCenter
                                key: row.modelData.key
                                desc: row.modelData.desc || ""
                                font_px: Style.whichkey_size
                            }

                            Text {
                                visible: root.arrow_space > 0
                                x: root.key_width + Style.px(5)
                                anchors.verticalCenter: parent.verticalCenter
                                text: Style.whichkey_arrow
                                color: Style.text_muted
                                font.family: Style.font_family
                                font.pixelSize: root.text_size
                            }

                            Text {
                                id: desc_text
                                x: root.key_width + Style.px(8) + root.arrow_space
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, root.desc_max_width)
                                elide: Text.ElideRight
                                text: row.modelData.desc
                                color: root.watch && row.modelData.destructive ? Style.pal.error : row.modelData.group ? Style.accent_color : Style.pal.fg
                                font.family: root.watch && row.modelData.group ? Style.title_font_family : Style.font_family
                                font.pixelSize: root.watch && row.modelData.group ? Style.fs(-6) : root.text_size
                                font.capitalization: root.watch && row.modelData.group ? Font.AllUppercase : Font.MixedCase
                                font.bold: row.modelData.group === true && !root.watch
                            }
                        }
                    }
                }

                MenuFooter {
                    visible: root.has_footer
                    Layout.fillWidth: true
                    centered: true
                    text: root.footer_hint
                }
            }

            overlay: Loader {
                id: burst_loader
                anchors.fill: parent
                anchors.margins: 5
                active: Style.open_fx === "static"
                sourceComponent: Goldeneye.StaticBurst {}
            }
        }
    }
}
