// home/quickshell/.config/quickshell/components/Popup.qml
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services"
import "Search.js" as Search
import "../picker/Fuzzy.js" as Fuzzy
import "neovim" as Neovim

PanelWindow {
    id: root

    property string popup_name: ""
    property real preferred_width: 260
    // Content height; the base adds the style's title tab and footer around it.
    property real body_height: 0
    // Opt-in for dock_bottom: the surface keeps this content height while the drawn panel grows inside it, so it never resizes.
    property real reserve_height: 0
    readonly property bool reserving: root.dock_bottom && root.reserve_height > 0
    property real drawn_body_height: root.body_height
    Behavior on drawn_body_height {
        enabled: root.reserving && root.visible && root.drop_progress === 1
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    readonly property real panel_height: root.reserving ? Math.min(root.height, root.drawn_body_height + root.header_height + root.footer_height + root.st.frame_drop) : root.height
    property string title: popup_name.toUpperCase()
    // A live value after the style's title readout, e.g. unread counts.
    property string title_value: ""
    // Passive popups (the tooltip shelf) show app text as it is.
    readonly property string shown_title: root.passive ? root.title : Style.title_text(root.title, root.st)
    property string footer_hint: ""
    // The full key list behind `?`; while set, the footer shows only help_hint.
    property string key_help: footer_hint
    readonly property string help_hint: "? help · q close"
    // Overrides help_hint/footer_hint outright when non-empty, for popups whose ? and q are typed rather than pressed.
    property string footer_override: ""
    property bool help_open: false
    // Styles with a `small` block draw "small" popups apart from "large" ones (notifications, weather, media).
    property string size_class: "small"
    readonly property var st: root.size_class === "small" ? Style.small : Style
    // A hover shelf: follows Tooltip instead of Popups, never takes focus or input, and plays faster.
    property bool passive: false
    property real anim_scale: root.passive ? 0.6 : 1
    // Small popups inside the style's handheld shell (DeviceShell), and the room it keeps around the content.
    readonly property bool device: root.st.device_shell && !root.passive
    readonly property int device_side: root.device ? 20 : 0
    readonly property int device_top: root.device ? 30 : 0
    readonly property int device_bottom: root.device ? 80 : 0
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

    // `/` search: search_rows is each j/k row's text by index; search_select(i) must select row i like j/k would.
    property bool search_enabled: false
    property var search_rows: []
    property int search_cursor: -1
    signal search_select(int index)
    property string search_query: ""
    property bool search_typing: false
    // Opt-in: the popup opens straight into typing (INSERT), fuzzy-matches search_rows like the HyprVim
    // prompt, and Esc leaves typing (NORMAL) without clearing the query rather than canceling the search.
    property bool search_starts_open: false
    // With search_starts_open, false opens in NORMAL with an empty query; `i` or `/` starts typing.
    property bool search_opens_typing: true
    signal search_accept()
    readonly property bool search_shown: root.search_enabled && (root.search_starts_open ? root.search_typing : (root.search_typing || root.search_query !== ""))
    readonly property var search_matches: root.search_shown ? (root.search_starts_open ? root.fuzzy_matches(root.search_rows, root.search_query) : Search.matches(root.search_rows, root.search_query)) : []

    function fuzzy_matches(rows, query) {
        const terms = Fuzzy.terms_of(query);
        if (terms.length === 0) return [];
        const found = [];
        for (let i = 0; i < rows.length; i++) if (Fuzzy.score_item(terms, { label: rows[i] })) found.push(i);
        return found;
    }

    // Highest-scoring row, or -1 when nothing matches.
    function fuzzy_best(rows, query) {
        const terms = Fuzzy.terms_of(query);
        if (terms.length === 0) return -1;
        let best = -1;
        let best_score = -Infinity;
        for (let i = 0; i < rows.length; i++) {
            const m = Fuzzy.score_item(terms, { label: rows[i] });
            if (m && m.score > best_score) {
                best_score = m.score;
                best = i;
            }
        }
        return best;
    }
    // The base footer is hidden in some styles; it then overlays the content's bottom edge while searching.
    readonly property bool search_overlay: root.search_shown && !root.has_footer && root.footer_hint !== ""

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

    // Wraps a j/k list index by delta within `count` items starting at `min` (e.g. min -1 for a switch row above the list).
    function wrap_index(i, delta, min, count) {
        if (count <= 0) return min;
        return ((i - min + delta) % count + count) % count + min;
    }

    function is_help_key(event) {
        return event.key === Qt.Key_Question || event.text === "?";
    }

    function focus_active_view() {
        if (!root.visible) return;
        if (root.help_open) key_help_view.forceActiveFocus();
        else if (root.search_typing) search_input.forceActiveFocus();
        else content_scope.forceActiveFocus();
    }

    function open_search() {
        search_input.text = "";
        root.search_typing = true;
        search_input.forceActiveFocus();
    }

    // Resumes typing without losing the query, for `i`/`/` back into INSERT on a search_starts_open popup.
    function enter_search() {
        root.search_typing = true;
        search_input.forceActiveFocus();
        search_input.cursorPosition = search_input.text.length;
    }

    function clear_search() {
        const refocus = search_input.activeFocus;
        root.search_typing = false;
        search_input.text = "";
        if (refocus) root.focus_active_view();
    }

    function accept_search() {
        root.search_typing = false;
        root.focus_active_view();
    }

    // Next or previous match from the popup's selection, wrapping.
    function step_search(delta) {
        const m = root.search_matches;
        if (m.length === 0) return;
        let target = delta > 0 ? m.find(i => i > root.search_cursor) : m.slice().reverse().find(i => i < root.search_cursor);
        if (target === undefined) target = delta > 0 ? m[0] : m[m.length - 1];
        root.search_select(target);
    }

    onSearch_enabledChanged: if (!root.search_enabled) root.clear_search()

    // Deferred so the help view's visibility has already followed help_open.
    onHelp_openChanged: Qt.callLater(root.focus_active_view)

    // Runs after the popup's own handlers: keys reach it only when nothing deeper accepted them.
    function handle_shared_key(event) {
        const focus_item = content_scope.Window.activeFocusItem;
        if (focus_item && "cursorPosition" in focus_item) return;
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
        if (root.key_help !== "" && root.is_help_key(event)) {
            help_open = true;
        } else if (root.search_enabled && (event.key === Qt.Key_Slash || event.text === "/")) {
            if (root.search_starts_open) root.enter_search(); else root.open_search();
        } else if (root.search_starts_open && event.key === Qt.Key_I) {
            root.enter_search();
        } else if (root.search_enabled && root.search_query !== "" && event.key === Qt.Key_N) {
            root.step_search(back ? -1 : 1);
        } else if (event.key === Qt.Key_Backspace && Popups.back_name !== "") {
            Popups.back();
        } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_H || event.key === Qt.Key_L)) {
            Popups.walk(event.key === Qt.Key_L ? 1 : -1);
        } else if (event.key === Qt.Key_Q) {
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

    // Set by popups whose layout is fluid: from a side island they take exactly the island body's width.
    property bool fit_island: false
    // Full width along the bottom of the screen, rising from its edge; the frame loses its rounded corners.
    property bool dock_bottom: false
    readonly property real frame_radius: root.dock_bottom ? 0 : root.st.frame_radius
    readonly property bool floating: root.st.frame_float > 0 && !root.dock_bottom && !root.island_capsule
    readonly property real top_radius: root.floating ? root.frame_radius : 0
    // Hung flush from a capsule: square under it, rounded where the frame reaches past its ends.
    readonly property real overhang: root.island_capsule && !root.dock_bottom ? root.width - root.island_width : 0
    readonly property real top_left_radius: root.overhang > 0 && root.side !== "left" ? Math.min(root.frame_radius, root.side === "center" ? root.overhang / 2 : root.overhang) : root.top_radius
    readonly property real top_right_radius: root.overhang > 0 && root.side !== "right" ? Math.min(root.frame_radius, root.side === "center" ? root.overhang / 2 : root.overhang) : root.top_radius
    // Shortcuts fire before the focused item, so popups that bind h/l themselves still walk.
    function walk_allowed() {
        const f = content_scope.Window.activeFocusItem;
        return root.wanted && !root.passive && !(f && "cursorPosition" in f);
    }

    Shortcut {
        sequences: ["Ctrl+H"]
        enabled: root.visible && root.walk_allowed()
        onActivated: Popups.walk(-1)
    }

    Shortcut {
        sequences: ["Ctrl+L"]
        enabled: root.visible && root.walk_allowed()
        onActivated: Popups.walk(1)
    }

    // Never narrower than the island's bottom edge (its body, between the slants).
    implicitWidth: root.passive ? root.island_width : root.fit_island && root.island_width > 0 && root.side !== "center" ? root.island_width : Math.max(Style.px(preferred_width) + root.st.lcd_margin * 2 + root.device_side * 2, island_width, root.st.popup_min_width)
    implicitHeight: (root.reserving ? Math.max(reserve_height, body_height) : body_height) + header_height + footer_height + root.st.frame_drop
    default property alias content: content_scope.data

    readonly property bool wanted: root.passive ? Tooltip.visible && Tooltip.island !== null && Popups.open_name === "" : Popups.open_name === root.popup_name && Popups.open_screen_name !== ""

    // Latched on open so the popup keeps its place and color while the close animation plays.
    property var held_anchor: null
    property string held_screen_name: ""
    property color held_color: Theme.bg_mantle

    // The anchor is the island's body; its parent is the Island, which knows which end caps it has.
    readonly property var island: held_anchor ? held_anchor.parent : null
    // Capsule islands measure by the capsule they draw, not the body between their caps.
    readonly property bool island_capsule: !!island && island.capsule === true
    readonly property real island_width: root.island && root.island_capsule ? root.island.capsule_width : held_anchor ? held_anchor.width : 0
    readonly property bool island_cap_left: !!island && island.cap_left === true
    readonly property bool island_cap_right: !!island && island.cap_right === true
    // cap_right-only = a left island, flush with the screen's left edge; cap_left-only = a right island.
    readonly property string side: (island_cap_left && island_cap_right) ? "center" : island_cap_right ? "left" : island_cap_left ? "right" : "center"

    // A layer surface pinned to the screen edge: xdg popups landed a few px short of it.
    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    anchors.top: !dock_bottom
    anchors.bottom: dock_bottom
    anchors.left: side === "left" || dock_bottom
    anchors.right: side === "right" || dock_bottom
    margins.top: root.floating ? root.st.frame_float : 0
    margins.left: root.island && root.island_capsule && root.side === "left" ? root.island.capsule_inset : 0
    margins.right: root.island && root.island_capsule && root.side === "right" ? root.island.capsule_inset : 0
    exclusiveZone: 0
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "quickshell-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.passive ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    mask: root.passive ? no_input : root.reserving || root.shadow_room > 0 ? panel_input : null
    // The soft shadow's room under the frame; it passes clicks through to the scrim like the reserve does.
    readonly property real shadow_room: !root.dock_bottom && root.st.frame_shadow.a > 0 ? root.st.frame_drop : 0

    Region {
        id: no_input
    }

    // The transparent reserve above the panel passes clicks through to the scrim below, which closes the popup.
    Region {
        id: panel_input
        item: panel_area
    }

    Item {
        id: panel_area
        y: root.height - root.panel_height
        width: root.width
        height: root.panel_height - root.shadow_room
    }

    readonly property int line_height: root.st.accent_height
    readonly property bool has_title: root.st.show_title && title !== ""
    readonly property bool has_footer: root.st.show_footer && footer_hint !== ""
    readonly property bool lcd: root.st.lcd_top.a > 0
    readonly property real title_gap: root.st.title_rule.a > 0 ? 6 : 0
    readonly property bool stripped: root.st.title_strip.a > 0
    readonly property bool banded: root.st.title_band.a > 0 || root.stripped
    readonly property real band_height: Math.max(26, title_tab.height + 4)
    readonly property real engraving_height: root.st.frame_engraving !== "" ? Math.ceil(engraving_metrics.height) + 4 : 0
    readonly property real header_height: (has_title ? (root.banded ? root.band_height + 8 : title_tab.height + title_gap) + root.st.inset_pad : 0) + root.st.lcd_margin * 2 + root.device_top
    // Console inset rings also clear a content-drawn footer.
    readonly property real footer_height: (has_footer ? base_footer.implicitHeight + 10 + root.st.inset_pad : root.st.console_views !== "" && root.st.frame_inset_width > 0 ? root.st.inset_pad : 0) + root.st.lcd_margin * 2 + engraving_height + root.device_bottom + Style.slant_room
    property real line_progress: 0
    property real drop_progress: 0

    // Same island: title and text follow Tooltip in place; another island replays the drop from there.
    function latch_tooltip() {
        const moved = root.held_anchor !== Tooltip.island;
        if (moved) {
            open_anim.stop();
            line_progress = 0;
            drop_progress = 0;
            if (held_screen_name !== Tooltip.screen_name) visible = false;
        }
        held_anchor = Tooltip.island;
        held_screen_name = Tooltip.screen_name;
        held_color = Tooltip.island_color;
        visible = true;
        if (moved || drop_progress < 1) open_anim.restart();
    }

    Connections {
        target: Tooltip
        enabled: root.passive
        function onIslandChanged() {
            if (root.wanted) root.latch_tooltip();
        }
    }

    onWantedChanged: {
        if (wanted && passive) {
            close_anim.stop();
            latch_tooltip();
        } else if (wanted) {
            close_anim.stop();
            held_anchor = Popups.open_anchor;
            held_screen_name = Popups.open_screen_name;
            held_color = Popups.open_color;
            help_open = false;
            if (!root.search_starts_open || !root.search_opens_typing) clear_search();
            visible = true;
            open_anim.restart();
            if (root.search_starts_open && root.search_opens_typing) root.open_search();
            else content_scope.forceActiveFocus();
        } else if (visible && passive && Popups.open_name !== "") {
            open_anim.stop();
            close_anim.stop();
            line_progress = 0;
            drop_progress = 0;
            visible = false;
            held_anchor = null;
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
        running: root.st.caret_blink && !root.passive && root.visible && root.wanted && Power.on_ac
        onTriggered: Style.caret_phase = !Style.caret_phase
        onRunningChanged: Style.caret_phase = true
    }

    SequentialAnimation {
        id: open_anim
        NumberAnimation { target: root; property: "line_progress"; to: 1; duration: 180 * root.anim_scale; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "drop_progress"; to: 1; duration: 190 * root.anim_scale; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: close_anim
        NumberAnimation { target: root; property: "drop_progress"; to: 0; duration: 120 * root.anim_scale; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "line_progress"; to: 0; duration: 90 * root.anim_scale; easing.type: Easing.InCubic }
        ScriptAction {
            script: {
                root.visible = false;
                root.held_anchor = null;
                root.help_open = false;
            }
        }
    }

    // Hyprland moves pointer focus to this layer when it maps, so an unmoved re-click on the bar lands here, off the surface.
    MouseArea {
        id: outside_catch
        enabled: !root.passive
        x: -100000
        y: -100000
        width: 200000
        height: 200000
        z: -1
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            const px = mouse.x + outside_catch.x;
            const py = mouse.y + outside_catch.y;
            if (px >= 0 && py >= root.height - root.panel_height && px < root.width && py < root.height - root.shadow_room) mouse.accepted = false;
            else if (root.wanted) Popups.close();
        }
    }

    function edge_x(w) {
        return side === "right" ? width - w : side === "left" ? 0 : (width - w) / 2;
    }

    Rectangle {
        id: accent_line
        readonly property real w: (root.st.accent_full_width || root.dock_bottom ? root.width : root.island_width) * root.line_progress
        x: root.edge_x(w)
        y: root.dock_bottom ? reveal.y - root.line_height : 0
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
        // Lets MenuFooter and RowLabel inside draw this popup's search.
        readonly property var search_popup: root
        y: root.dock_bottom ? root.height - reveal.height : root.line_height
        width: root.width
        height: (root.panel_height - root.line_height) * root.drop_progress
        clip: true

        Rectangle {
            visible: !root.dock_bottom && root.st.frame_drop > 0 && root.st.frame_shadow.a === 0
            y: root.st.frame_drop
            width: root.width
            height: root.height - root.line_height - root.st.frame_drop
            color: Theme.bg_shadow
            bottomLeftRadius: root.frame_radius
            bottomRightRadius: root.frame_radius
        }

        Loader {
            active: !root.dock_bottom && root.st.frame_shadow.a > 0
            x: root.frame_radius
            y: root.st.frame_drop / 2
            width: root.width - root.frame_radius * 2
            height: root.height - root.line_height - root.st.frame_drop
            sourceComponent: RectangularShadow {
                blur: root.st.frame_drop
                radius: root.frame_radius
                color: root.st.frame_shadow
            }
        }

        Item {
            width: root.width
            height: root.panel_height - root.line_height - (root.dock_bottom ? 0 : root.st.frame_drop)

            // Reads as the island unfolding downward: its color, joined flush under the accent line.
            Rectangle {
                anchors.fill: parent
                color: root.st.frame_chamfer > 0 || root.st.frame_visor || root.st.custom_frame || root.device || root.st.border_title ? "transparent" : root.st.frame_follows_island ? root.held_color : root.st.frame_color
                topLeftRadius: root.top_left_radius
                topRightRadius: root.top_right_radius
                bottomLeftRadius: root.frame_radius
                bottomRightRadius: root.frame_radius
                border.width: root.st.frame_visor || root.st.frame_chamfer > 0 || root.st.custom_frame || root.st.border_title ? 0 : root.st.frame_border_width
                border.color: root.st.frame_border_color
            }

            Loader {
                anchors.fill: parent
                active: root.st.border_title
                sourceComponent: Neovim.FloatFrame {
                    st: root.st
                    title: root.has_title ? root.shown_title : ""
                    status: root.st.title_status ? root.title_value : ""
                    chip_height: root.has_title ? title_tab.height : 0
                    radius: root.frame_radius
                }
            }

            VisorGlass {
                anchors.fill: parent
                top_cut: root.top_radius > 0 ? 6 : 0
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
                top_left_radius: Math.max(0, root.top_left_radius - root.st.frame_border_width)
                top_right_radius: Math.max(0, root.top_right_radius - root.st.frame_border_width)
                bottom_radius: Math.max(0, root.frame_radius - root.st.frame_border_width)
                chamfer: root.st.frame_chamfer
            }

            // Under a capsule the top border gives way, so the capsule's fill runs straight into the frame's.
            Rectangle {
                visible: root.island_capsule && !root.dock_bottom && root.st.frame_border_width > 0
                x: root.edge_x(root.island_width) + root.st.frame_border_width
                width: root.island_width - root.st.frame_border_width * 2
                height: root.st.frame_border_width
                color: root.st.frame_shade.a > 0 ? root.st.frame_shade : root.st.frame_color
            }

            Sheen {
                color_top: root.floating ? root.st.sheen : "transparent"
                corner: root.top_radius
                edge: root.st.frame_border_width
            }

            CustomFrame {
                anchors.fill: parent
                device: root.device
                top_radius: 0
                bottom_radius: root.frame_radius
            }

            Loader {
                anchors.fill: parent
                active: root.device
                sourceComponent: DeviceShell {
                    room_side: root.device_side
                    room_top: root.device_top
                    room_bottom: root.device_bottom
                }
            }

            FrameInset {
                bottom_radius: root.frame_radius
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
                radius: root.st.lcd_radius
                border.width: 1
                border.color: root.st.lcd_border
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

                CornerBrackets {
                    anchors.fill: parent
                    color: root.st.lcd_brackets
                    inset: 5
                    arm: 14
                    all_corners: true
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

            FontMetrics {
                id: engraving_metrics
                font: engraving.font
            }

            // Everything drawn on the frame; styles with a glow or text shadow render it as one layer.
            Item {
                id: glow_layer
                readonly property bool layered: root.st.glow || root.st.text_shadow.a > 0
                anchors.fill: parent
                layer.enabled: glow_layer.layered
                opacity: glow_layer.layered ? 0 : 1


                Loader {
                    active: root.has_title && root.banded
                    x: root.st.inset_pad + root.st.frame_border_width
                    y: x
                    width: parent.width - x * 2
                    height: root.band_height
                    sourceComponent: root.stripped ? title_strip : tab_header

                    Component {
                        id: tab_header
                        TabHeader {
                            readonly property var ids: root.st.title_ids[root.popup_name] || []
                            title: root.title
                            panel_id: ids[0] || ""
                            readout: ids[1] || ""
                            readout_value: root.title_value
                        }
                    }

                    Component {
                        id: title_strip
                        TitleStrip {
                            title: root.title
                            readout_value: root.title_value
                            closable: !root.passive
                        }
                    }
                }

                Rectangle {
                    id: title_tab
                    visible: root.has_title && !root.banded && !root.st.border_title
                    x: (root.st.fade_fills ? root.st.frame_border_width : 0) + root.st.inset_pad + root.st.lcd_margin * 2 + root.device_side
                    y: (root.st.fade_fills ? root.st.frame_border_width : 0) + root.st.inset_pad + root.st.lcd_margin * 2 + root.device_top
                    readonly property real reticle_space: root.st.title_reticle.a > 0 ? title_text.implicitHeight + 4 : 0
                    readonly property real lead_space: title_tab.reticle_space + title_index.space
                    width: root.st.fade_fills ? parent.width - root.st.frame_border_width * 2 : Math.min(Math.ceil(Math.max(title_metrics.width, title_metrics.advanceWidth)) + 20 + title_tab.lead_space, parent.width - title_tab.x * 2)
                    height: Math.max(title_text.implicitHeight, title_index.space > 0 ? title_index.implicitHeight : 0) + 4
                    color: root.st.fade_fills ? "transparent" : root.st.title_bg

                    Reticle {
                        visible: title_tab.reticle_space > 0
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: title_tab.reticle_space - 4
                        height: width
                        color: root.st.title_reticle
                        center_color: root.st.caret_color
                    }

                    FadeFill {
                        visible: root.st.fade_fills
                        fill: root.st.title_bg
                    }

                    TitleIndex {
                        id: title_index
                        x: 10 + title_tab.reticle_space
                        anchors.verticalCenter: parent.verticalCenter
                        st: root.st
                        name: root.popup_name
                    }

                    TextMetrics {
                        id: title_metrics
                        font: title_text.font
                        text: title_text.text
                    }

                    Text {
                        id: title_text
                        anchors.centerIn: root.st.fade_fills ? undefined : parent
                        anchors.horizontalCenterOffset: title_tab.lead_space / 2
                        x: 10 + title_tab.lead_space
                        y: (parent.height - height) / 2
                        width: Math.min(Math.ceil(Math.max(title_metrics.width, title_metrics.advanceWidth)), parent.width - 20 - title_tab.lead_space)
                        elide: Text.ElideRight
                        text: root.st.title_prefix + root.shown_title + (Style.caret_phase ? root.st.title_suffix : " ".repeat(root.st.title_suffix.length))
                        color: root.st.title_fg
                        font.family: root.st.title_font_family
                        font.pixelSize: root.st.title_size > 0 ? root.st.title_size : root.st.fs(-2)
                        font.weight: root.st.title_weight > 0 ? root.st.title_weight : root.st.title_font_family === root.st.font_family ? Font.Bold : Font.Normal
                        font.letterSpacing: root.st.title_spacing
                    }
                }

                Text {
                    id: title_readout
                    // Dropped on narrow popups rather than drawn over the title.
                    visible: root.has_title && root.st.title_readout !== "" && title_tab.x + (root.st.fade_fills ? 10 + title_tab.lead_space + title_text.implicitWidth : title_tab.width) + 12 <= parent.width - anchors.rightMargin - implicitWidth
                    anchors.right: parent.right
                    anchors.rightMargin: (root.lcd ? root.st.lcd_margin * 2 : 12) + root.st.inset_pad + root.device_side
                    y: title_tab.y + (title_tab.height - height) / 2
                    text: root.st.title_readout.replace("{code}", root.title.slice(0, 3))
                    color: root.st.title_readout_fg.a > 0 ? root.st.title_readout_fg : root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-5)
                    font.letterSpacing: 1
                }

                // Plain sentence-case titles carry the live title value at the right, like a status line.
                Text {
                    visible: root.has_title && !root.banded && root.st.title_status && !root.st.border_title && root.st.title_readout === "" && root.title_value !== "" && title_tab.x + title_tab.width + 12 <= parent.width - anchors.rightMargin - implicitWidth
                    anchors.right: parent.right
                    anchors.rightMargin: title_readout.anchors.rightMargin + 4
                    y: title_tab.y + (title_tab.height - height) / 2
                    text: root.title_value
                    color: root.st.text_muted
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-3)
                }

                Loader {
                    active: root.has_title && !root.banded && !root.passive && root.st.console_views === "ps2"
                    visible: title_tab.x + title_tab.width + 10 <= x
                    anchors.right: parent.right
                    anchors.rightMargin: title_readout.anchors.rightMargin
                    y: title_tab.y + (title_tab.height - height) / 2
                    source: active ? "ps2/AnalogLed.qml" : ""
                    onLoaded: item.lit = Qt.binding(() => root.wanted && glow_layer.Window.active)
                }

                Rectangle {
                    visible: root.has_title && root.st.title_trail.a > 0 && width > 8
                    x: title_tab.x + (root.st.fade_fills ? 10 + title_tab.lead_space + title_text.implicitWidth + 12 : title_tab.width)
                    y: title_tab.y + Math.round(title_tab.height / 2)
                    width: (title_readout.visible ? title_readout.x - 12 : parent.width - title_readout.anchors.rightMargin) - x
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.st.title_trail }
                        GradientStop { position: 1; color: Qt.alpha(root.st.title_trail, 0) }
                    }
                }

                Rectangle {
                    visible: root.has_title && root.st.title_rule.a > 0
                    x: title_tab.x
                    y: title_tab.y + title_tab.height + 2
                    width: parent.width - title_tab.x * 2
                    height: 1
                    color: root.st.title_rule
                }

                Rectangle {
                    visible: root.search_overlay
                    z: 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: root.st.frame_border_width
                    height: base_footer.implicitHeight + 8
                    color: root.st.frame_follows_island ? root.held_color : root.st.frame_color
                    bottomLeftRadius: root.st.frame_radius
                    bottomRightRadius: root.st.frame_radius
                }

                MenuFooter {
                    id: base_footer
                    visible: root.has_footer || root.search_overlay
                    z: root.search_overlay ? 2 : 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12 + root.st.lcd_margin + root.device_side
                    anchors.rightMargin: 12 + root.st.lcd_margin + root.device_side
                    anchors.bottomMargin: (root.search_overlay ? 4 : 8) + root.st.inset_pad + root.st.lcd_margin * 2 + root.engraving_height + root.device_bottom + Style.slant_room
                    text: root.footer_override !== "" ? root.footer_override : (root.key_help !== "" ? root.help_hint : root.footer_hint)
                }

                // Takes the typed query off screen; MenuFooter draws it in the footer line.
                TextInput {
                    id: search_input
                    width: 0
                    height: 0
                    opacity: 0
                    maximumLength: 64
                    onTextChanged: {
                        root.search_query = text;
                        if (root.search_typing && text !== "") {
                            const i = root.search_starts_open ? root.fuzzy_best(root.search_rows, text) : Search.best(root.search_rows, text);
                            if (i >= 0) root.search_select(i);
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (root.search_starts_open) root.accept_search();
                            else root.clear_search();
                        } else if (event.key === Qt.Key_Backspace && search_input.text === "") {
                            if (!root.search_starts_open) root.clear_search();
                            else return;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.search_starts_open) root.search_accept();
                            else root.accept_search();
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                            root.step_search(event.key === Qt.Key_Down ? 1 : -1);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }

                FocusScope {
                    id: content_scope
                    anchors.fill: parent
                    anchors.topMargin: root.header_height
                    anchors.bottomMargin: root.footer_height
                    anchors.leftMargin: root.st.lcd_margin + root.device_side
                    anchors.rightMargin: root.st.lcd_margin + root.device_side
                    focus: true
                    opacity: root.help_open ? 0 : 1

                    Keys.onEscapePressed: {
                        if (root.search_query !== "") root.clear_search();
                        else Popups.close();
                    }
                    Keys.onPressed: event => root.handle_shared_key(event)
                }

                KeyHelp {
                    id: key_help_view
                    anchors.fill: content_scope
                    visible: root.help_open
                    text: root.key_help
                    tab_count: root.tabs.length
                    has_views: root.sub_views.length > 0
                    searchable: root.search_enabled
                    onBack: root.help_open = false
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
                visible: root.st.scanlines && root.st.frame_octagon <= 0
                anchors.fill: parent
                anchors.margins: root.frame_radius > 0 ? root.st.frame_border_width : 0

                Repeater {
                    model: root.st.scanlines && root.st.frame_octagon <= 0 ? Math.max(0, Math.ceil(parent.height / root.st.scanline_period)) : 0

                    Rectangle {
                        required property int index
                        y: index * root.st.scanline_period
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
                radius: root.frame_radius
            }
        }
    }

    onSuspend_grabChanged: if (!root.suspend_grab) root.focus_active_view()
}
