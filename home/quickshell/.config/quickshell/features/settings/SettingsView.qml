pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.core
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames
import qs.features.audio
import qs.features.bar
import qs.features.overview
import "../../ui/Search.js" as Search
import "Sections.js" as Sections

// Settings as a full-screen view on the focused monitor, in the overview's frame. It answers to Popups under the name
// "settings", so every way of opening a popup (keybind, Start menu, bar module, IPC) opens it, and it carries the slice
// of Popup's interface that PopupKeys and the section panes read.
PanelWindow {
    id: root

    readonly property string popup_name: "settings"
    readonly property var st: Style
    readonly property bool wanted: Popups.open_name === root.popup_name && Popups.open_screen_name !== ""
    readonly property bool is_open: root.wanted
    property string held_screen_name: ""
    // Popups.hands_off as of the open, held through the fade out because close() clears it first.
    property bool held_hands_off: false
    property real reveal: 0
    readonly property bool settled: root.wanted && root.reveal === 1
    onSettledChanged: Popups.mark_settled(root.popup_name, root.settled)
    readonly property bool closing: !root.wanted && root.visible
    onClosingChanged: Popups.mark_closing(root.popup_name, root.closing)

    // The panel's share of the screen in each direction, centred over a dimmed desktop.
    readonly property real panel_fraction: 0.8

    // The lock's full-screen preview (LockPreview), for the lock section's p key.
    property var previewer: null

    property int nav_index: 0
    property bool in_pane: false
    property string loaded_id: ""
    readonly property var pane: pane_loader.item
    readonly property var section: Sections.list[root.nav_index] || null
    // Where SettingsPane puts its description block: the help column beside the rows.
    readonly property Item description_host: help_column

    // PopupKeys reads these; Settings has no tabs, views, line ends or popup walk.
    readonly property var tabs: []
    readonly property var sub_views: []
    readonly property bool line_ends_enabled: false
    readonly property var walk_keys: ({ forward: "", back: "" })
    readonly property bool jumps_enabled: true
    signal jump_first()
    signal jump_last()
    onJump_first: root.jump(-1)
    onJump_last: root.jump(1)
    function set_tab(i) {}
    function step_tab(delta) {}
    function step_sub(delta) {}

    readonly property string nav_hint: "/ find · j/k move · l enter · 1-9 pick · gg/G first/last · q close"
    readonly property string footer_hint: root.in_pane && root.pane ? root.pane.shown_hint : root.nav_hint
    readonly property string key_help: root.footer_hint
    // The footer has room for every key, unlike a popup's "? help · q close"; ? help goes in before the closing q.
    readonly property string footer_with_help: root.footer_hint.replace(/ · q close$/, "") + " · ? help · q close"
    property bool help_open: false

    readonly property bool search_enabled: true
    readonly property bool search_starts_open: false
    property string search_query: ""
    property bool search_typing: false
    readonly property bool search_shown: root.search_typing || root.search_query !== ""
    readonly property var search_rows: root.in_pane && root.pane ? root.pane.search_rows : Sections.list.map(s => s.label + " " + s.group + " " + s.keywords)
    readonly property int search_cursor: root.in_pane && root.pane ? root.pane.search_cursor : root.nav_index
    readonly property var search_matches: root.search_shown ? Search.matches(root.search_rows, root.search_query) : []

    screen: Quickshell.screens.find(s => s.name === root.held_screen_name) || null
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    // The popup namespace: Popups.after_close waits for it to unmap, and the Hyprland layer rules cover it.
    WlrLayershell.namespace: "quickshell-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.wanted && !root.held_hands_off ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: root.held_hands_off ? no_input : null

    Region {
        id: no_input
    }

    // A hands-off open (`qs ipc call settings view`) stays on the screen it names; any other open follows the focus.
    function pick_screen() {
        if (Popups.hands_off) return Popups.open_screen_name;
        const mon = Hyprland.focusedMonitor;
        return mon && Quickshell.screens.some(s => s.name === mon.name) ? mon.name : Popups.open_screen_name;
    }

    onWantedChanged: {
        load_timer.stop();
        if (root.wanted) {
            root.held_screen_name = root.pick_screen();
            root.held_hands_off = Popups.hands_off;
            root.help_open = false;
            root.clear_search();
            root.visible = true;
            reveal_anim.stop();
            if (PowerSource.on_ac) {
                reveal_anim.to = 1;
                reveal_anim.start();
            } else {
                root.reveal = 1;
            }
            if (!root.apply_request()) {
                root.load_section();
                root.leave_pane();
            }
            return;
        }
        root.in_pane = false;
        root.help_open = false;
        reveal_anim.stop();
        if (PowerSource.on_ac && root.visible) {
            reveal_anim.to = 0;
            reveal_anim.start();
        } else {
            root.conceal();
        }
    }

    // Popups.open_on sets hands_off after open_name, so the open above read the previous flag; take the final one here.
    Connections {
        target: Popups
        function onHands_offChanged() {
            if (!root.wanted) return;
            root.held_hands_off = Popups.hands_off;
            root.held_screen_name = root.pick_screen();
        }
    }

    function conceal() {
        root.reveal = 0;
        root.visible = false;
        root.held_hands_off = false;
    }

    NumberAnimation {
        id: reveal_anim
        target: root
        property: "reveal"
        duration: 170
        easing.type: Easing.OutCubic
        onFinished: if (!root.wanted) root.conceal()
    }

    onNav_indexChanged: {
        if (!root.is_open) return;
        load_timer.restart();
        ThemeAudio.play("cursor");
        Qt.callLater(root.reveal_selected, nav_flick, nav_col);
    }

    Timer {
        id: load_timer
        interval: 120
        onTriggered: root.load_section()
    }

    function wrap_index(i, delta, min, count) {
        if (count <= 0) return min;
        return ((i - min + delta) % count + count) % count + min;
    }

    function clamp_index(i, delta, min, count) {
        if (count <= 0) return min;
        return Math.max(min, Math.min(min + count - 1, i + delta));
    }

    function cursor_key() {
        return root.nav_index + "|" + root.in_pane + "|" + (root.pane && typeof root.pane.cursor === "number" ? root.pane.cursor : "");
    }

    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    function is_help_key(event) {
        return event.key === Qt.Key_Question || event.text === "?";
    }

    function focus_active_view() {
        if (!root.visible) return;
        if (root.help_open) key_help_view.forceActiveFocus();
        else if (root.search_typing) search_input.forceActiveFocus();
        else if (root.in_pane && root.pane) root.pane.forceActiveFocus();
        else nav.forceActiveFocus();
    }

    onHelp_openChanged: Qt.callLater(root.focus_active_view)

    function open_search() {
        search_input.text = "";
        root.search_typing = true;
        search_input.forceActiveFocus();
    }

    function enter_search() {
        root.open_search();
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

    function step_search(delta) {
        const m = root.search_matches;
        if (m.length === 0) return;
        let target = delta > 0 ? m.find(i => i > root.search_cursor) : m.slice().reverse().find(i => i < root.search_cursor);
        if (target === undefined) target = delta > 0 ? m[0] : m[m.length - 1];
        root.search_select(target);
    }

    function search_select(index) {
        if (root.in_pane && root.pane) root.pane.search_select(index);
        else root.nav_index = index;
    }

    function jump(delta) {
        if (root.in_pane && root.pane) root.pane.jump(delta);
        else root.nav_index = delta < 0 ? 0 : Sections.list.length - 1;
    }

    function load_section() {
        const section = Sections.list[root.nav_index];
        if (!section || root.loaded_id === section.id) return;
        root.loaded_id = section.id;
        pane_loader.setSource(Qt.resolvedUrl(section.source), { popup: root });
        pane_fade.restart();
    }

    function enter_pane() {
        load_timer.stop();
        root.load_section();
        if (!root.pane) return;
        root.in_pane = true;
        root.pane.forceActiveFocus();
        ThemeAudio.play("confirm");
    }

    function leave_pane() {
        if (root.in_pane) ThemeAudio.play("cancel");
        root.in_pane = false;
        nav.forceActiveFocus();
    }

    // Selects the section SettingsNav names and enters it; false when none was asked for.
    function apply_request() {
        const index = Sections.index_of(SettingsNav.requested);
        SettingsNav.requested = "";
        if (index < 0) return false;
        root.nav_index = index;
        root.load_section();
        root.enter_pane();
        return true;
    }

    // Drives the pane the way its keys would; a pane without the matching property or function ignores the command.
    function run_pane_command(name, value) {
        const pane = root.pane;
        if (!root.is_open || !root.in_pane || !pane) return;
        if (name === "back") {
            const editing = pane.editing === true || (typeof pane.edit_key === "string" && pane.edit_key !== "");
            if (pane.picking) pane.hide_picker();
            else if (editing && typeof pane.end_edit === "function") pane.end_edit();
            else root.leave_pane();
            return;
        }
        if (pane.picking || typeof pane.cursor !== "number") return;
        if (name === "cursor") pane.cursor = value;
        else if (name === "step" && typeof pane.step === "function") pane.step(pane.cursor, value);
        else if (name === "activate" && typeof pane.activate === "function") pane.activate(pane.cursor, 1);
    }

    // The first visible row flagged selected under `item`, or null.
    function selected_under(item) {
        for (const child of item.children) {
            if (!child.visible) continue;
            if (child.selected === true) return child;
            const found = root.selected_under(child);
            if (found) return found;
        }
        return null;
    }

    // Scrolls `flick` the least that shows the selected row under `scope`; a few px of lead keep a group heading with its first row.
    function reveal_selected(flick, scope) {
        const row = root.selected_under(scope);
        if (!row) return;
        const top = row.mapToItem(flick.contentItem, 0, 0).y;
        const lead = Style.px(24);
        let target = flick.contentY;
        if (top - lead < target) target = top - lead;
        else if (top + row.height > target + flick.height) target = top + row.height - flick.height;
        flick.contentY = Math.max(0, Math.min(target, flick.contentHeight - flick.height));
    }

    Connections {
        target: root.pane
        ignoreUnknownSignals: true
        function onCursorChanged() {
            Qt.callLater(root.reveal_selected, pane_flick, pane_loader);
        }
    }

    // The open picker moves its own cursor, which the pane's does not follow.
    Connections {
        target: root.pane ? root.pane.pick_list : null
        ignoreUnknownSignals: true
        function onCursorChanged() {
            Qt.callLater(root.reveal_selected, pane_flick, pane_loader);
        }
    }

    Connections {
        target: SettingsNav
        function onRequestedChanged() {
            if (root.is_open && SettingsNav.requested !== "") root.apply_request();
        }
        function onPane_command(name, value) {
            root.run_pane_command(name, value);
        }
    }

    PopupKeys {
        id: keys
        popup: root
    }

    // With the screen frame on, the layer covers the frame's hole, whose corners are cut in the frame's profile; the
    // scrim and panel are masked to that outline as the overview's are.
    readonly property var hole_outline: Style.screen_frame_on && root.screen ? ScreenFrames.hole_outline(root.screen) : []
    readonly property bool corners_cut: root.hole_outline.length > 0 && Style.screen_frame_profile !== null && Style.screen_frame_profile.corner !== "square" && Style.screen_frame_profile.radius > 0

    Item {
        id: hole_mask
        anchors.fill: parent
        visible: false
        layer.enabled: root.corners_cut

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: "black"
                PathPolyline { path: root.hole_outline }
            }
        }
    }

    Item {
        id: surface
        // Style.for_item reads the token set, and RowLabel and MenuFooter the search, from these.
        readonly property string size_class: "large"
        readonly property var search_popup: root
        anchors.fill: parent
        layer.enabled: root.corners_cut
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: hole_mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Rectangle {
            id: scrim
            anchors.fill: parent
            color: Qt.alpha(Theme.bg_crust, 0.6)
            opacity: root.reveal

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    ThemeAudio.play("cancel");
                    Popups.close();
                }
            }
        }

        OverviewFrame {
            id: frame
            width: Math.round(parent.width * root.panel_fraction)
            height: Math.round(parent.height * root.panel_fraction)
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            opacity: root.reveal
            scale: 0.97 + 0.03 * root.reveal
            title: "SETTINGS"
            status: root.section ? root.section.group + " / " + root.section.label : ""
            footer: root.footer_with_help

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
                        const i = Search.best(root.search_rows, text);
                        if (i >= 0) root.search_select(i);
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Backspace && search_input.text === "")) {
                        ThemeAudio.play("cancel");
                        root.clear_search();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        ThemeAudio.play("confirm");
                        root.accept_search();
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
                id: body
                anchors.fill: parent
                focus: true
                opacity: root.help_open ? 0 : 1

                // Runs after the section: Esc, h and Tab it did not use go back to the sidebar; then the shared keys.
                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) return;
                    const leave = (event.key === Qt.Key_H && !(event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Escape && root.search_query === "");
                    if (root.in_pane && leave) {
                        root.leave_pane();
                    } else if (event.key === Qt.Key_Escape) {
                        ThemeAudio.play("cancel");
                        if (root.search_query !== "") root.clear_search();
                        else Popups.close();
                    } else {
                        if (root.is_help_key(event)) root.help_open = true;
                        else keys.handle(event, body.Window.activeFocusItem);
                        return;
                    }
                    event.accepted = true;
                }

                Flickable {
                    id: nav_flick
                    width: nav.width
                    height: body.height
                    clip: nav_flick.contentHeight > nav_flick.height
                    contentWidth: width
                    contentHeight: nav.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        id: nav
                        readonly property real fit: {
                            let w = 0;
                            for (let i = 0; i < nav_repeater.count; i++) {
                                const item = nav_repeater.itemAt(i);
                                if (item) w = Math.max(w, item.need);
                            }
                            return w;
                        }
                        width: Math.max(Style.px(200), Math.ceil(nav.fit))
                        implicitHeight: nav_col.implicitHeight
                        focus: true

                        Keys.onPressed: event => {
                            if (event.modifiers & Qt.ControlModifier) return;
                            const count = Sections.list.length;
                            if (event.key === Qt.Key_J) root.nav_index = root.wrap_index(root.nav_index, 1, 0, count);
                            else if (event.key === Qt.Key_K) root.nav_index = root.wrap_index(root.nav_index, -1, 0, count);
                            else if (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) root.enter_pane();
                            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.key - Qt.Key_1 < count) root.nav_index = event.key - Qt.Key_1;
                            else return;
                            event.accepted = true;
                        }

                        Column {
                            id: nav_col
                            width: parent.width
                            spacing: 4

                            Repeater {
                                id: nav_repeater
                                model: Sections.list

                                Column {
                                    id: entry
                                    required property int index
                                    required property var modelData
                                    readonly property bool first: entry.index === 0 || Sections.list[entry.index - 1].group !== entry.modelData.group
                                    readonly property real need: 16 + nav_row.inset + nav_row.key_space + nav_layout.implicitWidth

                                    width: nav_col.width
                                    spacing: 4

                                    MenuSection {
                                        visible: entry.first
                                        width: entry.width
                                        topPadding: entry.index === 0 ? 0 : 6
                                        label: entry.modelData.group
                                    }

                                    MenuRow {
                                        id: nav_row
                                        width: entry.width
                                        height: Style.px(28)
                                        base_radius: 6
                                        selected: entry.index === root.nav_index
                                        key: entry.index < 9 ? String(entry.index + 1) : ""

                                        RowLayout {
                                            id: nav_layout
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8 + nav_row.inset
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8 + nav_row.key_space
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 8

                                            Text {
                                                text: entry.modelData.glyph
                                                color: nav_row.fg(Style.text_accent)
                                                font.family: Style.font_family
                                                font.pixelSize: Style.font_size
                                            }

                                            RowLabel {
                                                Layout.fillWidth: true
                                                label: entry.modelData.label
                                                color: nav_row.fg(Style.text_fg)
                                                font.family: Style.font_family
                                                font.pixelSize: Style.font_size
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.nav_index = entry.index;
                                                root.enter_pane();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Only on the section list: panes hold sliders and fields with wheel behavior of their own.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => {
                            const dir = wheel.angleDelta.y > 0 ? -1 : wheel.angleDelta.y < 0 ? 1 : 0;
                            if (dir !== 0 && !root.in_pane) root.nav_index = root.clamp_index(root.nav_index, dir, 0, Sections.list.length);
                            wheel.accepted = true;
                        }
                    }
                }

                Rectangle {
                    id: nav_divider
                    x: nav.width + Style.px(12)
                    width: 1
                    height: body.height
                    color: Qt.alpha(Style.text_muted, 0.4)
                }

                // The pane keeps a readable measure on wide screens; the help column takes what is left, within bounds.
                readonly property real help_width: Math.max(Style.px(300), Math.min(Style.px(520), (body.width - nav_divider.x) * 0.32))
                readonly property real pane_width: Math.min(Style.px(860), body.width - nav_divider.x - body.help_width - Style.px(48))

                Flickable {
                    id: pane_flick
                    x: nav_divider.x + Style.px(24)
                    width: body.pane_width
                    height: body.height
                    clip: pane_flick.contentHeight > pane_flick.height
                    contentWidth: width
                    contentHeight: pane_loader.height
                    boundsBehavior: Flickable.StopAtBounds

                    Loader {
                        id: pane_loader
                        width: pane_flick.width
                        height: Math.max(body.height, pane_loader.implicitHeight)
                        // The flickable is reused across sections: start the new one at the top, then at its selected row.
                        onLoaded: {
                            pane_flick.contentY = 0;
                            Qt.callLater(root.reveal_selected, pane_flick, pane_loader);
                        }
                    }
                }

                Rectangle {
                    id: help_divider
                    x: body.width - body.help_width - Style.px(12)
                    width: 1
                    height: body.height
                    color: Qt.alpha(Style.text_muted, 0.4)
                }

                Item {
                    id: help_column
                    x: body.width - body.help_width
                    width: body.help_width
                    height: body.height
                }

                NumberAnimation {
                    id: pane_fade
                    target: pane_loader
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                visible: root.help_open
                anchors.fill: parent
                color: Style.frame_color.a > 0.5 ? Style.frame_color : Theme.bg_crust

                KeyHelp {
                    id: key_help_view
                    anchors.fill: parent
                    text: root.key_help
                    searchable: true
                    walks: false
                    onBack: root.help_open = false
                    onClose_requested: Popups.close()
                }
            }
        }
    }
}
