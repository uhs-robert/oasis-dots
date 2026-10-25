import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.theme
import "../../../ui/Search.js" as Search
import "fuzzy_rows.js" as FuzzyRows
import "../../../ui/frames/DrawerGeometry.js" as Drawer
import "../../../ui/frames/FrameGeometry.js" as FrameGeometry
import "../../../ui/frames/PanelCuts.js" as Cuts
import qs.styles.goldeneye.widgets as Goldeneye
import qs.ui
import qs.ui.frames
import qs.ui.menu
import qs.ui.keys
import qs.features.launcher
import qs.features.popups
import qs.features.audio
import qs.features.bar

PanelWindow {
    id: root

    property string popup_name: ""
    property real preferred_width: 260
    // Content height; the base adds the style's title tab and footer around it.
    property real body_height: 0
    // Opt-in: the surface keeps this content height while the drawn panel grows inside it, so it never resizes.
    property real reserve_height: 0
    readonly property bool reserving: root.reserve_height > 0
    // Grows to fit the key list while help is open.
    readonly property real shown_body_height: root.help_open ? Math.max(root.body_height, key_help_view.content_height) : root.body_height
    property real drawn_body_height: root.shown_body_height
    Behavior on drawn_body_height {
        enabled: root.reserving && root.visible && root.drop_progress === 1
        NumberAnimation { id: body_grow; duration: 150; easing.type: Easing.OutCubic }
    }
    // A drawer sizes its panel from the content, not from its window, which also holds the cover strip and the fillets.
    readonly property real panel_limit: root.drawer ? root.base_height : root.height
    readonly property real panel_height: root.reserving ? Math.min(root.panel_limit, root.drawn_body_height + root.header_height + root.footer_height + root.drop_room) : root.panel_limit
    property string title: popup_name.toUpperCase()
    // A live value after the style's title readout, e.g. unread counts.
    property string title_value: ""
    // Shows title_value at the right of the title; a popup can turn it on where its style does not.
    property bool title_status: root.st.title_status
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
    // Holds the keyboard while wanted (not through the close animation, which would starve the next popup of focus): Hyprland refocuses the window under the pointer whenever a layer maps, such as hyprpaper's surface on every wallpaper change, which an on-demand popup loses its keys to.
    property bool hold_keyboard: false
    property real anim_scale: root.passive ? 0.6 : 1
    // The full-width strips (Picker, HyprvimPrompt) opt out: stretched across the screen the handheld's buttons land at the screen edges.
    property bool shell_allowed: true
    // Popups inside the style's handheld shell (DeviceShell), and the room it keeps around the content.
    readonly property bool device: root.st.device_shell && root.shell_allowed && !root.passive
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
    // The popup's cursor position(s); key moves play the cursor sound only when it (or the tab) changes.
    property var cursor_state: null
    function cursor_key() {
        return JSON.stringify([current_tab, current_sub, search_cursor, cursor_state]);
    }
    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    // Opt-in: each wheel notch over the content emits wheel_stepped once, so the popup only maps a notch to its own
    // key moves. dir is 1 for later (wheel down, tilt right) and -1 for earlier. Off while help shows, and a popup
    // turns it off for views that scroll their own lists.
    property bool wheel_steps: false
    signal wheel_stepped(int dir, bool horizontal, int modifiers)

    WheelStepper {
        id: wheel_stepper
    }

    function take_wheel(wheel) {
        // Touchpads may send pixelDelta alone, so it decides the axis when present. Pixels count double, as in
        // WheelStepper.consume_event.
        const has_pixels = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0;
        const axis_delta = has_pixels ? wheel.pixelDelta : wheel.angleDelta;
        const horizontal = Math.abs(axis_delta.x) > Math.abs(axis_delta.y);
        const pixels = horizontal ? wheel.pixelDelta.x : wheel.pixelDelta.y;
        const notches = wheel_stepper.consume(pixels !== 0 ? pixels * 2 : (horizontal ? wheel.angleDelta.x : wheel.angleDelta.y));
        if (notches === 0) return;
        const before = root.cursor_key();
        // Wheel down and a rightward tilt both report negative deltas, and both mean later.
        for (let i = 0; i < Math.abs(notches); i++) root.wheel_stepped(notches < 0 ? 1 : -1, horizontal, wheel.modifiers);
        root.play_if_moved(before);
    }

    // 0/$ emit line_start/line_end only while set: the left and right ends of an h/l row.
    property bool line_ends_enabled: false
    signal line_start()
    signal line_end()

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
    // With search_starts_open, false opens in NORMAL with an empty query; `i` or `/` starts typing. Follows Settings > Input.
    property bool search_opens_typing: TypingSettings.starts_insert
    signal search_accept()
    readonly property bool search_shown: root.search_enabled && (root.search_starts_open ? root.search_typing : (root.search_typing || root.search_query !== ""))
    readonly property var search_matches: root.search_shown ? (root.search_starts_open ? FuzzyRows.fuzzy_matches(root.search_rows, root.search_query) : Search.matches(root.search_rows, root.search_query)) : []

    // The base footer is hidden in some styles; it then overlays the content's bottom edge while searching.
    readonly property bool search_overlay: root.search_shown && !root.has_footer && root.footer_hint !== ""

    property var sub_memory: ({})

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

    // wrap_index without the wrap, for the wheel: a fast spin stops at the ends instead of cycling.
    function clamp_index(i, delta, min, count) {
        if (count <= 0) return min;
        return Math.max(min, Math.min(min + count - 1, i + delta));
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

    function handle_shared_key(event) {
        keys.handle(event, content_scope.Window.activeFocusItem);
    }

    PopupKeys {
        id: keys
        popup: root
    }

    // Set by popups whose layout is fluid: from a side island they take exactly the island body's width.
    property bool fit_island: false
    // Full width along the bottom of the screen, rising from its edge; the frame loses its rounded corners.
    property bool dock_bottom: false
    readonly property real frame_radius: root.drawer ? root.drawer_fillet : root.dock_bottom ? 0 : root.st.frame_radius
    // The screen edge this popup hangs from: the bar's, or the bottom for a docked one. Drawer geometry takes it by name.
    readonly property string edge: root.dock_bottom ? "bottom" : BarSettings.position_on(root.held_screen_name)
    // Over a bottom bar the popup rises from it: everything named for the bar side ("top" below) lands on the frame's
    // bottom edge instead, and the drop room and shadow go above the frame.
    readonly property bool rises: root.edge === "bottom" && !root.dock_bottom
    // Which way the frame's corners face: a docked popup keeps its flat bottom unless the frame turned it into a drawer.
    readonly property bool frame_rises: root.drawer ? root.edge === "bottom" : root.rises
    // Beside a left or right bar the popup opens out sideways from the bar's open edge: the bar has no frame, so this is
    // the plate popup turned a quarter, its accent line and slide along x and its square corners against the bar.
    readonly property bool beside: !root.dock_bottom && Drawer.is_vertical(root.edge)
    readonly property var beside_corners: Drawer.beside_corners(root.edge)
    readonly property bool floating: root.st.frame_float > 0 && !root.dock_bottom && !root.island_capsule && !root.drawer
    readonly property real top_radius: root.floating ? root.frame_radius : 0
    // Hung flush from a capsule: square under it, rounded where the frame reaches past its ends.
    readonly property real overhang: root.island_capsule && !root.dock_bottom && !root.drawer ? root.width - root.island_width : 0
    // Beside a bar, which corners are rounded; the others touch the bar. A floating style rounds them all. The radii and
    // `bar_square` both read this.
    readonly property var beside_round: root.floating ? { top_left: true, top_right: true, bottom_left: true, bottom_right: true } : root.beside_corners
    function beside_radius(round) {
        return round ? root.frame_radius : 0;
    }
    readonly property real top_left_radius: root.beside ? root.beside_radius(root.beside_round.top_left) : root.overhang > 0 && root.side !== "left" ? Math.min(root.frame_radius, root.side === "center" ? root.overhang / 2 : root.overhang) : root.top_radius
    readonly property real top_right_radius: root.beside ? root.beside_radius(root.beside_round.top_right) : root.overhang > 0 && root.side !== "right" ? Math.min(root.frame_radius, root.side === "center" ? root.overhang / 2 : root.overhang) : root.top_radius
    readonly property real bottom_left_corner: root.beside ? root.beside_radius(root.beside_round.bottom_left) : root.frame_radius
    readonly property real bottom_right_corner: root.beside ? root.beside_radius(root.beside_round.bottom_right) : root.frame_radius
    // The frame's corners that touch the bar, for the cut-corner outlines to leave whole. A floating style rounds them instead.
    readonly property var bar_square: Cuts.bar_square(root.beside ? root.beside_round : null, !root.floating && !root.dock_bottom, root.frame_rises)
    // Where the frame's body starts inside the reveal, which grows from the bar side.
    // A drawer's content rides out with its far edge instead of staying put while the body uncovers it.
    readonly property real body_shift_x: root.beside && root.edge === "right" ? reveal.width - root.frame_width : 0
    readonly property real body_shift: root.drawer ? (root.edge === "bottom" ? 0 : reveal.height - root.panel_height) : root.rises ? reveal.height - (root.panel_height - root.line_height) : 0

    // With the screen frame on, a bar-hung popup is a drawer: DrawerShape draws it in the frame's material, grown out of
    // the seam with a concave fillet at each end, and the accent line and drop shadow give way to it.
    readonly property var screen_frame: !root.passive && root.screen ? ScreenFrames.layout_for(root.screen) : null
    readonly property bool drawer: root.screen_frame !== null
    readonly property real drop_room: root.drawer ? 0 : root.st.frame_drop
    readonly property var drawer_profile: root.drawer ? Style.screen_frame_profile : null
    readonly property real drawer_fillet: root.drawer ? Drawer.fillet_of(root.drawer_profile) : 0
    readonly property real drawer_cover: Drawer.cover_depth(Style.bar_border_width, Style.bar_inset_gap, Style.bar_inset_width)
    readonly property var drawer_hole: root.screen_frame ? FrameGeometry.hole_rect(root.screen_frame) : null
    // A side island's end against its side band is a pocket, flush down the band; its other end, like a centre popup's, a fillet.
    // A docked popup fills the whole hole width, so both its ends are pockets.
    readonly property var drawer_kinds: Drawer.end_kinds(root.side, root.dock_bottom)
    readonly property real drawer_body_width: root.drawer_hole ? Drawer.body_length(root.dock_bottom ? "dock" : root.side, root.base_width, root.drawer_hole.w, root.drawer_fillet) : 0
    function drawer_spec(extent) {
        return Object.assign({
            edge: root.edge,
            body_length: root.drawer_body_width,
            body_depth: root.base_height,
            extent: extent,
            start_kind: root.drawer_kinds.start,
            end_kind: root.drawer_kinds.end,
            cover: root.drawer_cover
        }, Drawer.profile_fields(root.drawer_profile));
    }
    // The window's size follows the full drawer, so it never resizes while the shape grows inside it.
    // None of the three is ever null, so a frame switched off under an open popup cannot leave DrawerShape without a layout.
    readonly property var drawer_full: Drawer.drawer_layout(root.drawer_spec(root.base_height))
    readonly property var drawer_layout: Drawer.drawer_layout(root.drawer_spec(root.drawer ? root.panel_height * root.drop_progress : 0))
    readonly property var drawer_body: Drawer.body_rect(root.drawer_layout)
    // Layer margins are integers; the cover absorbs the rounding.
    readonly property real drawer_seam: root.screen_frame ? FrameGeometry.seam_of(root.screen_frame, root.edge) : 0
    readonly property var drawer_place: Drawer.place(root.side, root.edge, root.drawer_hole, root.drawer_seam, root.screen ? root.screen.width : 0, root.screen ? root.screen.height : 0, root.drawer_cover, root.drawer_full.length)
    // Where the drawer's texture tiles from, so it runs on from the frame's (DrawerShape).
    readonly property var drawer_texture_origin: Drawer.texture_origin(root.side, root.edge, !!root.screen_frame && root.screen_frame.edge === "bottom", root.drawer_place, root.screen ? root.screen.width : 0, root.screen ? root.screen.height : 0, root.drawer_full.length)
    // The depth the drawer has drawn, not the window's reserved one: a popup with a reserve_height is a taller window than its shape.
    readonly property real drawn_depth: root.drawer_layout.drawn_depth
    // Translucent islands make the drawer translucent too, so the frame and the strip leave their lines out under its window.
    readonly property bool drawer_translucent: root.drawer && Style.islands_translucent
    readonly property var drawer_window: root.drawer_translucent && root.visible ? Drawer.window_rect(root.side, root.edge, root.drawer_place, root.screen.width, root.screen.height, root.width, root.drawn_depth) : null
    DrawerWindowPublisher {
        screen_name: root.held_screen_name
        rect: root.drawer_window
    }
    // Shortcuts fire before the focused item, so popups that bind h/l themselves still walk.
    function walk_allowed() {
        const f = content_scope.Window.activeFocusItem;
        return root.wanted && !root.passive && !(f && "cursorPosition" in f);
    }

    // Along a row Ctrl+H/L walk, down a column Ctrl+J/K; the pair that does not match the bar stays inert. As shortcuts they
    // beat a popup's own bare j/k handlers, which therefore need no Ctrl guard.
    readonly property var walk_keys: BarSettings.walk_keys_on(root.held_screen_name)
    readonly property bool walk_column: root.walk_keys.forward === "J"

    Shortcut {
        sequences: ["Ctrl+H"]
        enabled: root.visible && !root.walk_column && root.walk_allowed()
        onActivated: Popups.walk(-1)
    }

    Shortcut {
        sequences: ["Ctrl+L"]
        enabled: root.visible && !root.walk_column && root.walk_allowed()
        onActivated: Popups.walk(1)
    }

    Shortcut {
        sequences: ["Ctrl+K"]
        enabled: root.visible && root.walk_column && root.walk_allowed() && Popups.walkable()
        onActivated: Popups.walk(-1)
    }

    Shortcut {
        sequences: ["Ctrl+J"]
        enabled: root.visible && root.walk_column && root.walk_allowed() && Popups.walkable()
        onActivated: Popups.walk(1)
    }

    // Never narrower than the island's bottom edge (its body, between the slants); a fit_island popup adds the shell's side room on top so the content keeps the island's width.
    implicitWidth: root.drawer ? root.drawer_full.surface.width : root.base_width + root.beside_line_room
    readonly property real base_width: root.passive && !root.beside ? root.island_width : root.fit_island && !root.beside && root.island_width > 0 && root.side !== "center" ? root.island_width + root.device_side * 2 : Math.max(Style.px(preferred_width) + root.st.lcd_margin * 2 + root.device_side * 2, island_floor_width, root.st.popup_min_width)
    implicitHeight: root.drawer ? root.drawer_full.surface.height : root.base_height
    readonly property real base_height: (root.reserving ? Math.max(reserve_height, shown_body_height) : shown_body_height) + header_height + footer_height + root.drop_room
    default property alias content: content_scope.data

    // Open with every entrance animation done, including the body growing to fit late-loading content; Popups reports it
    // over IPC so a script can act on a popup only once it is fully drawn.
    readonly property bool settled: root.wanted && !root.passive && root.drop_progress === 1 && !open_anim.running && !body_grow.running
        && !(burst_loader.item && burst_loader.item.busy)
    onSettledChanged: Popups.mark_settled(root.popup_name, root.settled)
    // Still mapped while it animates out; Popups reports it so "closed" means the layer is really gone.
    readonly property bool closing: !root.passive && close_anim.running
    onClosingChanged: Popups.mark_closing(root.popup_name, root.closing)
    readonly property bool wanted: root.passive ? Tooltip.visible && Tooltip.island !== null && Popups.open_name === "" : Popups.open_name === root.popup_name && Popups.open_screen_name !== ""

    // Latched on open so the popup keeps its place and color while the close animation plays.
    property var held_anchor: null
    property string held_screen_name: ""
    property color held_color: Theme.bg_mantle

    // The anchor is the island's body; its parent is the Island, which knows which end caps it has.
    readonly property var island: held_anchor ? held_anchor.parent : null
    // Capsule islands measure by the capsule they draw, not the body between their caps.
    readonly property bool island_capsule: !root.beside && !!island && island.capsule === true
    readonly property real island_width: root.island && root.island_capsule ? root.island.capsule_width : held_anchor ? held_anchor.width : 0
    // The clock's meeting chip widens its island, but not the clock popup sized from it. Only the width floor below uses this;
    // the accent line, the island notch and the corner radii still follow the island as drawn.
    readonly property real island_floor_width: root.beside ? 0 : Math.max(0, root.island_width - (root.popup_name === "clock" && root.island && root.island.popup_trim !== undefined ? root.island.popup_trim : 0))
    readonly property bool island_cap_left: !!island && island.cap_left === true
    readonly property bool island_cap_right: !!island && island.cap_right === true
    // cap_right-only = a left island, flush with the screen's left edge; cap_left-only = a right island.
    readonly property string side: (island_cap_left && island_cap_right) ? "center" : island_cap_right ? "left" : island_cap_left ? "right" : "center"

    // The floating strip moves the side islands in by this (Bar.strip_side), so their popups and tooltips follow.
    readonly property real strip_side: Style.strip_floats ? Style.bar_strip_side : 0

    // The island's extent down the screen, which a popup beside a side bar lines up with. mapToItem is not reactive, so it
    // is read again when the island is latched, opens, moves or resizes.
    property real island_top: 0
    property real island_length: 0
    function read_island() {
        if (!root.island) return;
        root.island_top = root.island.mapToItem(null, 0, 0).y;
        root.island_length = root.island.height;
    }
    onIslandChanged: root.read_island()
    onVisibleChanged: if (root.visible) root.read_island()
    Connections {
        target: root.island
        function onHeightChanged() { root.read_island(); }
        function onYChanged() { root.read_island(); }
    }
    readonly property var beside_at: Drawer.beside_place(root.side, root.edge, root.island_top, root.island_length, root.base_height, root.screen ? root.screen.height : 0)
    // The accent line takes its thickness out of the width instead of the height.
    readonly property real beside_line_room: root.beside ? root.line_height : 0
    readonly property real frame_width: root.drawer ? root.drawer_body.width : root.width - root.beside_line_room

    // A layer surface pinned to the screen edge: xdg popups landed a few px short of it.
    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    anchors.top: root.drawer ? root.drawer_place.anchor_top : root.beside ? root.beside_at.anchor_top : !dock_bottom && !rises
    anchors.bottom: root.drawer ? root.drawer_place.anchor_bottom : root.beside ? root.beside_at.anchor_bottom : dock_bottom || rises
    anchors.left: root.drawer ? root.drawer_place.anchor_left : root.beside ? root.beside_at.anchor_left : side === "left" || dock_bottom
    anchors.right: root.drawer ? root.drawer_place.anchor_right : root.beside ? root.beside_at.anchor_right : side === "right" || dock_bottom
    // A drawer places itself against the frame's seam, so it ignores the exclusive zones the bands reserve.
    margins.top: root.drawer ? root.drawer_place.margin_top : root.beside ? root.beside_at.margin_top : root.floating && !root.rises ? root.st.frame_float : 0
    margins.bottom: root.drawer ? root.drawer_place.margin_bottom : root.floating && root.rises ? root.st.frame_float : 0
    margins.left: root.drawer ? root.drawer_place.margin_left : root.beside ? (root.floating && root.edge === "left" ? root.st.frame_float : 0) : root.island && root.island_capsule && root.side === "left" ? root.island.capsule_inset : FrameGeometry.side_popup_inset(root.strip_side, root.side, "left")
    margins.right: root.drawer ? root.drawer_place.margin_right : root.beside ? (root.floating && root.edge === "right" ? root.st.frame_float : 0) : root.island && root.island_capsule && root.side === "right" ? root.island.capsule_inset : FrameGeometry.side_popup_inset(root.strip_side, root.side, "right")
    // No explicit exclusiveZone: even 0 overrides Ignore, so the frame's zones would push a drawer inward.
    exclusionMode: root.drawer ? ExclusionMode.Ignore : ExclusionMode.Normal
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "quickshell-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.passive || root.held_hands_off ? WlrKeyboardFocus.None : root.wanted && (root.hold_keyboard || Popups.grab_keyboard) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    mask: root.passive || root.held_hands_off ? no_input : root.drawer || root.reserving || root.shadow_room > 0 ? panel_input : null
    // The soft shadow's room under the frame; it passes clicks through to the scrim like the reserve does.
    readonly property real shadow_room: !root.dock_bottom && !root.drawer && root.st.frame_shadow.a > 0 ? root.st.frame_drop : 0

    Region {
        id: no_input
    }

    // Popups.hands_off as of the open, held through the close animation because close() clears the flag first.
    property bool held_hands_off: false

    Connections {
        target: Popups
        function onHands_offChanged() {
            if (root.wanted) root.held_hands_off = Popups.hands_off;
        }
    }

    // The transparent reserve above the panel passes clicks through to the scrim below, which closes the popup.
    Region {
        id: panel_input
        item: panel_area
    }

    Item {
        id: panel_area
        x: root.drawer ? root.drawer_body.x : 0
        y: root.drawer ? root.drawer_body.y : root.dock_bottom ? root.height - root.panel_height : root.rises ? root.height - root.panel_height + root.shadow_room : 0
        width: root.drawer ? root.drawer_body.width : root.width
        height: root.drawer ? root.drawer_body.height : root.panel_height - root.shadow_room
    }

    readonly property int line_height: root.drawer ? 0 : root.st.accent_height
    // What the accent line takes out of the frame's height: none beside a side bar, where it takes width.
    readonly property real frame_line_room: root.beside ? 0 : root.line_height
    readonly property bool has_title: root.st.show_title && title !== ""
    readonly property bool has_footer: root.st.show_footer && footer_hint !== ""
    readonly property bool lcd: root.st.lcd_top.a > 0
    readonly property real title_gap: root.st.title_rule.a > 0 ? 6 : 0
    readonly property bool stripped: root.st.title_strip.a > 0
    readonly property bool banded: root.stripped
    readonly property real band_height: Math.max(26, title_block.tab_height + 4)
    readonly property real engraving_height: decor.engraving_height
    readonly property real header_height: (has_title ? (root.banded ? root.band_height + 8 : title_block.tab_height + title_gap) + root.st.inset_pad : 0) + root.st.lcd_margin * 2 + root.device_top
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

    // Whether this popup's window holds the keyboard; gaining it ends a grab, so a click on another window still takes it.
    readonly property bool keyboard_active: content_scope.Window.active
    onKeyboard_activeChanged: {
        if (root.passive || !root.wanted || !root.keyboard_active) return;
        Popups.grab_keyboard = false;
        root.focus_active_view();
    }
    // A grab asked for while the window already has the keyboard is refused at once, so focus_open reports nothing to do.
    Connections {
        target: Popups
        function onGrab_keyboardChanged() {
            if (Popups.grab_keyboard && root.wanted && root.keyboard_active) Popups.grab_keyboard = false;
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
            held_hands_off = Popups.hands_off;
            help_open = false;
            if (!root.search_starts_open || !root.search_opens_typing) clear_search();
            visible = true;
            open_anim.restart();
            if (burst_loader.item) burst_loader.item.play();
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
        running: root.st.caret_blink && !root.passive && root.visible && root.wanted && PowerSource.on_ac
        onTriggered: Style.caret_phase = !Style.caret_phase
        onRunningChanged: Style.caret_phase = true
    }

    // A bottom-docked picker slides further than a bar-hung popup drops, so it opens and closes more slowly and gently.
    readonly property bool slow_drop: root.drawer && root.dock_bottom
    readonly property real drop_open_ms: root.slow_drop ? 300 : 190
    readonly property real drop_close_ms: root.slow_drop ? 180 : 120
    readonly property int drop_open_easing: root.slow_drop ? Easing.OutQuint : Easing.OutCubic

    SequentialAnimation {
        id: open_anim
        NumberAnimation { target: root; property: "line_progress"; to: 1; duration: root.drawer ? 0 : 180 * root.anim_scale; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "drop_progress"; to: 1; duration: root.drop_open_ms * root.anim_scale; easing.type: root.drop_open_easing }
    }

    SequentialAnimation {
        id: close_anim
        NumberAnimation { target: root; property: "drop_progress"; to: 0; duration: root.drop_close_ms * root.anim_scale; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "line_progress"; to: 0; duration: root.drawer ? 0 : 90 * root.anim_scale; easing.type: Easing.InCubic }
        ScriptAction {
            script: {
                root.visible = false;
                root.held_anchor = null;
                root.held_hands_off = false;
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
            if (px >= panel_area.x && py >= panel_area.y && px < panel_area.x + panel_area.width && py < panel_area.y + panel_area.height) mouse.accepted = false;
            else if (root.wanted) Popups.close();
        }
    }

    function edge_x(w) {
        return side === "right" ? width - w : side === "left" ? 0 : (width - w) / 2;
    }

    Loader {
        active: root.drawer
        sourceComponent: DrawerShape {
            layout: root.drawer_layout
            screen_name: root.held_screen_name
            translucent: root.drawer_translucent
            texture_origin: root.drawer_texture_origin
            frame: root.screen_frame
            // The handheld shell's own edge is enough round the body.
            lines_depth: root.device ? Drawer.mouth_depth(root.drawer_layout) : -1
        }
    }

    Rectangle {
        id: accent_line
        visible: !root.drawer
        readonly property real w: (root.st.accent_full_width || root.dock_bottom ? root.width : root.island_width) * root.line_progress
        // Beside a side bar the line runs down the bar's open edge, for the island's length.
        readonly property real h: Math.min(root.st.accent_full_width ? root.height : root.island_length, root.height) * root.line_progress
        x: root.beside ? (root.edge === "right" ? root.width - root.line_height : 0) : root.edge_x(w)
        y: root.beside ? Drawer.beside_line_offset(root.island_top, root.beside_at.margin_top, h, root.height) : root.dock_bottom ? reveal.y - root.line_height : root.rises ? root.height - root.line_height : 0
        width: root.beside ? root.line_height : w
        height: root.beside ? h : root.line_height
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
        x: root.drawer ? root.drawer_body.x : root.beside ? (root.edge === "right" ? root.width - root.line_height - reveal.width : root.line_height) : 0
        y: root.drawer ? root.drawer_body.y : root.beside ? 0 : root.dock_bottom ? root.height - reveal.height : root.rises ? root.height - root.line_height - reveal.height : root.line_height
        width: root.drawer ? root.drawer_body.width : root.beside ? root.frame_width * root.drop_progress : root.width
        height: root.beside ? root.panel_height : (root.panel_height - root.line_height) * root.drop_progress
        clip: true

        Rectangle {
            visible: !root.dock_bottom && !root.drawer && root.st.frame_drop > 0 && root.st.frame_shadow.a === 0
            x: root.body_shift_x
            y: root.body_shift + (root.rises ? 0 : root.st.frame_drop)
            width: root.frame_width
            height: root.panel_height - root.frame_line_room - root.st.frame_drop
            color: Theme.bg_shadow
            topLeftRadius: root.rises ? root.frame_radius : root.beside ? root.top_left_radius : 0
            topRightRadius: root.rises ? root.frame_radius : root.beside ? root.top_right_radius : 0
            bottomLeftRadius: root.rises ? 0 : root.bottom_left_corner
            bottomRightRadius: root.rises ? 0 : root.bottom_right_corner
        }

        Loader {
            active: !root.dock_bottom && !root.drawer && root.st.frame_shadow.a > 0
            x: root.body_shift_x + root.frame_radius
            y: root.body_shift + root.st.frame_drop / 2
            width: root.frame_width - root.frame_radius * 2
            height: root.panel_height - root.frame_line_room - root.st.frame_drop
            sourceComponent: RectangularShadow {
                blur: root.st.frame_drop
                radius: root.frame_radius
                color: root.st.frame_shadow
            }
        }

        StyledFrame {
            id: frame
            st: root.st
            x: root.body_shift_x
            y: root.body_shift + (root.frame_rises ? root.drop_room : 0)
            width: root.frame_width
            height: root.panel_height - root.frame_line_room - (root.dock_bottom ? 0 : root.drop_room)
            radius: root.frame_radius
            square: root.bar_square
            top_left_radius: root.frame_rises ? root.frame_radius : root.top_left_radius
            top_right_radius: root.frame_rises ? root.frame_radius : root.top_right_radius
            bottom_radius: root.frame_rises ? 0 : root.frame_radius
            bottom_left_radius: root.frame_rises ? root.top_left_radius : root.bottom_left_corner
            bottom_right_radius: root.frame_rises ? root.top_right_radius : root.bottom_right_corner
            inner_top_radius: root.frame_rises || root.beside ? root.frame_radius : 0
            // The inner layers (inset ring, custom frame, dither) follow the outline's own corners beside a bar, so the
            // side against it stays square as the outline does.
            inner_top_left_radius: root.beside ? root.top_left_radius : root.frame_rises ? root.frame_radius : 0
            inner_top_right_radius: root.beside ? root.top_right_radius : root.frame_rises ? root.frame_radius : 0
            inner_bottom_left_radius: root.beside ? root.bottom_left_corner : root.frame_rises ? 0 : root.frame_radius
            inner_bottom_right_radius: root.beside ? root.bottom_right_corner : root.frame_rises ? 0 : root.frame_radius
            corner_radii: true
            island_color: root.held_color
            clear_fill: root.device || root.st.border_title
            clear_border: root.st.border_title
            drawer: root.drawer
            visor_top_cut: root.top_radius > 0 || root.frame_rises || root.beside ? 6 : 0
            sheen_on: root.floating
            tint_color: Theme.theme_primary_light
            device: root.device

            decor: [
                PopupDecor {
                    id: decor
                    st: root.st
                    has_title: root.has_title
                    shown_title: root.shown_title
                    title_value: root.title_value
                    title_status: root.title_status
                    chip_height: root.has_title ? title_block.tab_height : 0
                    frame_radius: root.frame_radius
                    island_capsule: root.island_capsule
                    island_width: root.island_width
                    capsule_x: root.edge_x(root.island_width)
                    dock_bottom: root.dock_bottom
                    rises: root.rises
                    device: root.device
                    room_side: root.device_side
                    room_top: root.device_top
                    room_bottom: root.device_bottom
                    lcd: root.lcd
                }
            ]

            PopupTitle {
                id: title_block
                st: root.st
                title: root.title
                shown_title: root.shown_title
                title_value: root.title_value
                title_status: root.title_status
                popup_name: root.popup_name
                passive: root.passive
                has_title: root.has_title
                banded: root.banded
                band_height: root.band_height
                lcd: root.lcd
                device_side: root.device_side
                device_top: root.device_top
                wanted: root.wanted
                layer_item: frame.layer_item
            }

            Rectangle {
                visible: root.search_overlay
                z: 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.st.frame_border_width
                height: base_footer.implicitHeight + 8
                color: root.drawer ? Style.strip_color : root.st.frame_follows_island ? root.held_color : root.st.frame_color
                bottomLeftRadius: root.drawer ? root.frame_radius : root.st.frame_radius
                bottomRightRadius: root.drawer ? root.frame_radius : root.st.frame_radius
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
                        const i = root.search_starts_open ? FuzzyRows.fuzzy_best(root.search_rows, text) : Search.best(root.search_rows, text);
                        if (i >= 0) root.search_select(i);
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        ThemeAudio.play("cancel");
                        if (root.search_starts_open) root.accept_search();
                        else root.clear_search();
                    } else if (event.key === Qt.Key_Backspace && search_input.text === "") {
                        if (!root.search_starts_open) {
                            ThemeAudio.play("cancel");
                            root.clear_search();
                        } else return;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        ThemeAudio.play("confirm");
                        if (root.search_starts_open) root.search_accept();
                        else root.accept_search();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                        const before = root.cursor_key();
                        root.step_search(event.key === Qt.Key_Down ? 1 : -1);
                        root.play_if_moved(before);
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
                    ThemeAudio.play("cancel");
                    if (root.search_query !== "") root.clear_search();
                    else Popups.close();
                }
                Keys.onPressed: event => root.handle_shared_key(event)

                // Above the popup's content, so the wheel lands here before a Flickable inside can take it.
                // A MouseArea sees both wheel axes, which a WheelHandler (vertical-only by default) does not.
                // No buttons and no hover, so clicks and hover reach the content below.
                MouseArea {
                    anchors.fill: parent
                    z: 100
                    acceptedButtons: Qt.NoButton
                    enabled: root.wheel_steps && !root.help_open
                    onWheel: wheel => {
                        root.take_wheel(wheel);
                        wheel.accepted = true;
                    }
                }
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

            overlay: Loader {
                id: burst_loader
                anchors.fill: parent
                anchors.margins: root.st.inset_pad + root.st.lcd_margin
                active: root.st.open_fx === "static" && !root.passive
                sourceComponent: Goldeneye.StaticBurst {}
            }
        }
    }

    onSuspend_grabChanged: if (!root.suspend_grab) root.focus_active_view()
}
