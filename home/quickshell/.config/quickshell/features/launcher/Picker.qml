import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.ui.menu
import qs.theme
import qs.features.popups
import qs.features.popups.frames
import qs.features.audio
import qs.ui.scroll
import "../../ui/scroll/ScrollCue.js" as Cue
import "../../core/Fuzzy.js" as Fuzzy
import "BrowseLayout.js" as BrowseLayout

// The shared picker over Pickers.provider: docked at the bottom from IPC, or dropped from an island when opened with an
// anchor. A browse provider always drops from the center island, with a preview above a grid of cards.
Popup {
    id: root

    popup_name: "picker"
    size_class: "large"
    shell_allowed: false
    dock_bottom: root.held_anchor === null && !root.browse
    fit_island: !root.dock_bottom && !root.browse
    anim_scale: 0.3
    // Settings' size: most of the screen's width up to a cap, and a fixed share of its height.
    preferred_width: root.browse ? (root.screen ? Math.min(root.screen.width * 0.9, Style.px(1600)) : Style.px(1200)) / Style.scale : 320
    title: root.provider ? root.provider.title.toUpperCase() : "PICKER"
    footer_hint: "Enter " + root.verb + root.nesting_hint + " · Esc normal · q close"
    // NORMAL mode spells out the provider's actions and the browse preview keys; with neither the frame shows its own "? help · q close".
    footer_override: root.insert ? "Enter " + root.verb + root.nesting_hint + " · Esc normal" : root.action_hint !== "" || root.browse ? "Enter " + root.verb + root.nesting_hint + (root.action_hint !== "" ? " · " + root.action_hint : "") + root.browse_hint + " · ? help · q close" : ""
    key_help: ["Enter " + root.verb, "Up/Down move", "Ctrl+j/k move"].concat(root.tab_help).concat(root.provider && root.provider.can_go_back ? ["Backspace on an empty search back"] : []).concat(root.tabs.length > 0 ? ["Ctrl+Tab/Ctrl+Shift+Tab tabs"] : []).concat(["Ctrl+u clear", "Esc normal mode", "j/k rows", "h/l columns", "0/$ row ends", "gg/G first/last", "i/a insert", "/ search"]).concat(root.browse ? ["=/+ bigger preview, past large to max", "- smaller preview", "p preview on/off", "v grid/list", "1-9 select the numbered item on screen (Enter opens)"] : []).concat(root.action_hint !== "" ? [root.action_hint] : []).concat(["q/Esc close"]).join(" · ")
    jumps_enabled: !root.insert
    cursor_state: root.selected
    tabs: root.provider ? root.provider.tabs : []

    readonly property var provider: Pickers.provider
    readonly property string verb: root.provider ? root.provider.verb : "open"
    readonly property string nesting_hint: !root.provider ? "" : root.provider.expands ? " · Tab expand" : root.provider.can_go_back ? " · Backspace back" : ""
    readonly property string action_hint: root.provider ? root.provider.actions.map(a => a.key + " " + a.desc).join(" · ") : ""
    readonly property bool is_open: Popups.open_name === "picker"
    readonly property bool browse: !!root.provider && root.provider.layout === "browse"
    readonly property string browse_hint: root.browse ? (root.has_alt_preview ? " · Tab " + (root.showing_alt ? "back" : root.provider.alt_preview_name) : "") + " · =/- p preview · v view · 1-9 pick" : ""
    // A browse picker leaves rows to hjkl, so Tab is free for its alternate preview.
    readonly property var tab_help: root.browse ? (root.has_alt_preview ? ["Tab/Shift+Tab preview or " + root.provider.alt_preview_name] : []) : [root.provider && root.provider.expands ? "Tab expand, Shift+Tab prev" : "Tab/Shift+Tab next/prev"]
    readonly property bool has_alt_preview: root.browse && root.provider.alt_preview !== null
    readonly property int columns: root.browse_list ? 1 : root.browse ? BrowseLayout.columns(list_area.width - 2 * root.cue_gutter, root.card_width, root.card_gap) : root.dock_bottom && root.provider ? Math.max(1, root.provider.columns) : 1
    readonly property real cell_height: Style.px(30)
    readonly property real card_gap: Style.px(8)
    readonly property real card_width: Style.px(root.provider ? root.provider.card_size.width : 280)
    readonly property real card_height: Style.px(root.provider ? root.provider.card_size.height : 112)
    readonly property real screen_height: root.screen ? root.screen.height : 1080
    readonly property real tabs_space: tab_rows.visible ? tab_rows.height + 8 : 0
    readonly property real anchored_height: root.tabs_space + query_bar.height + 8 + root.cell_height * Math.max(1, Math.min(10, root.results.length)) + detail.height + 6 + 24

    body_height: root.browse ? (root.screen ? Math.round(root.screen_height * 0.8) - root.header_height - root.footer_height : 600) : root.dock_bottom ? Math.round(root.screen_height * 0.4) - root.header_height - root.footer_height - root.drop_room : root.anchored_height

    // Preview size in the browse layout (BrowseLayout.sizes), reset to the provider's default on every open.
    property string preview_size: "m"
    // What p brings the preview back to.
    property string last_preview_size: "m"
    // Tab swaps the provider's alt_preview in; every open starts on the selected item's preview.
    property bool alt_preview_shown: false
    readonly property bool showing_alt: root.has_alt_preview && root.alt_preview_shown
    // "grid" of cards or one-line "list" rows; v flips it, and every open starts on the grid.
    property string browse_view: "grid"
    readonly property bool browse_list: root.browse && root.browse_view === "list"
    // At the max preview size the cards or rows are hidden, so the scroll cue and the number hints go too.
    readonly property bool items_hidden: root.browse && root.preview_size === "max"
    readonly property real list_row_height: Style.px(34)
    readonly property real browse_gap: root.browse_list ? Style.px(4) : root.card_gap
    readonly property real browse_cell_height: root.browse_list ? root.list_row_height + root.browse_gap : root.card_height + root.card_gap
    // The scroll cue's fade, and the room right of the cards for its caret.
    readonly property real cue_fade: Style.px(20)
    readonly property real cue_gutter: Style.px(16)
    // The cards or rows wholly on screen, which the 1-9 hints number; they renumber as the view scrolls.
    readonly property var shown_items: root.items_hidden ? { first: 0, end: 0 } : BrowseLayout.on_screen(grid.contentY, grid.height, grid.contentHeight, grid.cellHeight, grid.cellHeight - root.browse_gap, root.browse_split.overflows ? root.cue_fade : 0, root.columns, root.results.length)
    readonly property var browse_split: BrowseLayout.fit(list_area.height, body.height, root.preview_size, root.browse_cell_height, root.card_gap, root.results.length, root.columns, root.cue_fade)

    property string query: ""
    property int selected: 0
    property bool insert: true
    // { query, id } of each item Tab expanded, so going back restores the search and the row.
    property var expanded_from: []

    readonly property var results: root.rank(root.provider ? root.provider.items : [], root.query)
    readonly property var selected_item: root.results.length > 0 ? root.results[Math.min(root.selected, root.results.length - 1)].item : null

    property string ranked_query: ""
    property var shown_results: []

    // A new query starts over; new items under the same query keep the selected item, or its row once it is gone.
    onResultsChanged: {
        root.sync_slots();
        const old = root.shown_results[root.selected];
        root.shown_results = root.results;
        if (root.query !== root.ranked_query) {
            root.ranked_query = root.query;
            root.selected = root.first_index();
            grid.positionViewAtBeginning();
            return;
        }
        const same = old ? root.results.findIndex(r => r.item.id === old.item.id) : -1;
        root.selected = same >= 0 ? same : Math.max(0, Math.min(root.selected, root.results.length - 1));
    }
    onSelectedChanged: root.reveal_selected()
    onJump_first: root.selected = 0
    onJump_last: root.selected = Math.max(0, root.results.length - 1)

    // Reset once hidden so an open finds the empty-query results already laid out.
    onVisibleChanged: if (!visible) root.reset()
    onIs_openChanged: if (is_open) {
        const recalled = root.provider ? TypingSettings.recall("picker:" + root.provider.name) : "";
        if (root.provider) root.current_tab = root.provider.tab;
        const preview_size = BrowseLayout.size_of(root.provider ? root.provider.default_preview_size : "");
        root.preview_size = preview_size;
        root.last_preview_size = preview_size;
        root.browse_view = "grid";
        root.alt_preview_shown = false;
        root.reset();
        query_input.text = recalled;
        // Reads Popups.open_anchor, not dock_bottom: held_anchor may still be stale when this handler runs first.
        // A browse picker has an anchor even when opened from a keybind, so it always takes the keybind start mode.
        const opened_by_key = Popups.open_anchor === null || root.browse;
        const mode_insert = opened_by_key ? TypingSettings.docked_starts_insert(root.provider) : TypingSettings.starts_insert;
        root.set_insert(mode_insert && (!root.provider || root.provider.starts_insert));
    }
    Component.onCompleted: root.sync_slots()

    onCurrent_tabChanged: if (root.provider && root.provider.tab !== root.current_tab) {
        root.provider.select_tab(root.current_tab);
        root.selected = 0;
        grid.positionViewAtBeginning();
    }

    Connections {
        target: root.provider

        function onTabChanged() {
            root.current_tab = root.provider.tab;
        }

        function onExpand_requested(item) {
            root.expand_item(item);
        }
    }

    Connections {
        target: Pickers

        function onStep_requested(delta) {
            root.step(delta);
        }
    }

    function reset() {
        root.expanded_from = [];
        query_input.text = "";
        root.selected = root.first_index();
        grid.positionViewAtBeginning();
    }

    function first_index() {
        if (root.query !== "" || !root.provider) return 0;
        return Math.max(0, Math.min(root.provider.initial_index, root.results.length - 1));
    }

    // One row per result, grown or shrunk at the tail, so delegates outlive a new ranking and just rebind.
    function sync_slots() {
        const n = root.results.length;
        if (slots.count > n) {
            slots.remove(n, slots.count - n);
        } else if (slots.count < n) {
            const add = [];
            for (let i = slots.count; i < n; i++) add.push({ slot: i });
            slots.append(add);
        }
    }

    function rank(items, query) {
        const terms = Fuzzy.terms_of(query);
        const name = root.provider ? root.provider.name : "";
        const use_usage = !!root.provider && root.provider.rank_by_usage;
        const keep_order = !!root.provider && root.provider.keep_order;
        const cap = root.provider ? root.provider.max_results : 0;
        const usage = use_usage ? Pickers.frecencies(name) : ({});
        const out = [];
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const f = usage[item.id] || 0;
            const bonus = f > 0 ? 12 * Math.log2(1 + f) : 0;
            if (terms.length === 0) {
                out.push({ item: item, positions: [], score: bonus, order: i });
                continue;
            }
            const m = Fuzzy.score_item(terms, item);
            if (m) out.push({ item: item, positions: m.positions, score: m.score + bonus, order: i });
        }
        if (cap > 0 && out.length > cap && !(keep_order && terms.length === 0)) {
            const cutoff = out.map(r => r.score).sort((a, b) => b - a)[cap - 1];
            return root.sort_ranked(out.filter(r => r.score >= cutoff), terms, keep_order).slice(0, cap);
        }
        if (!(keep_order && terms.length === 0)) root.sort_ranked(out, terms, keep_order);
        return cap > 0 ? out.slice(0, cap) : out;
    }

    function sort_ranked(out, terms, keep_order) {
        return out.sort((a, b) => b.score - a.score || (keep_order ? a.order - b.order : (terms.length > 0 ? a.item.label.length - b.item.label.length : 0) || a.item.label.localeCompare(b.item.label)));
    }

    function set_insert(on) {
        root.insert = on;
        if (on) {
            query_input.forceActiveFocus();
        } else {
            query_input.focus = false;
            body.forceActiveFocus();
        }
    }

    function activate() {
        const item = root.selected_item;
        if (!item || !root.provider) return;
        const p = root.provider;
        if (p.rank_by_usage) Pickers.record(p.name, item.id);
        ThemeAudio.play("confirm");
        Pickers.close();
        p.activate(item);
    }

    // Like Tab completing a command in HyprVim's prompt: the list narrows to what lies under the item.
    function expand_selected() {
        const item = root.selected_item;
        if (!item || !root.provider) return;
        root.expand_item(item);
    }

    // Also a voice "expand N" (PickerProvider.expand_requested), so the search clears for it as it does for Tab.
    function expand_item(item) {
        const from = { query: query_input.text, id: item.id };
        if (!root.provider.expand(item)) return;
        root.expanded_from = root.expanded_from.concat([from]);
        query_input.text = "";
        root.selected = 0;
        grid.positionViewAtBeginning();
        ThemeAudio.play("confirm");
    }

    function go_back() {
        const from = root.expanded_from[root.expanded_from.length - 1] || { query: "", id: "" };
        root.expanded_from = root.expanded_from.slice(0, -1);
        root.provider.go_back();
        query_input.text = from.query;
        const row = root.results.findIndex(r => r.item.id === from.id);
        if (row >= 0) root.selected = row;
        ThemeAudio.play("cancel");
    }

    // j/k keep the column and wrap top to bottom; a short last row lands on its last item.
    function line_ends(to_end) {
        const n = root.results.length;
        if (n === 0) return;
        const cols = root.columns;
        const start = cols === 1 ? 0 : root.selected - root.selected % cols;
        root.selected = to_end ? (cols === 1 ? n - 1 : Math.min(n - 1, start + cols - 1)) : start;
    }
    line_ends_enabled: true
    onLine_start: root.line_ends(false)
    onLine_end: root.line_ends(true)

    function move_row(delta) {
        const n = root.results.length;
        if (n === 0) return;
        const before = root.selected;
        const cols = root.columns;
        if (cols === 1) {
            root.selected = root.wrap_index(root.selected, delta, 0, n);
        } else {
            const rows = Math.ceil(n / cols);
            const col = root.selected % cols;
            const row = (Math.floor(root.selected / cols) + delta + rows) % rows;
            root.selected = Math.min(n - 1, row * cols + col);
        }
        if (root.selected !== before) ThemeAudio.play("cursor");
    }

    function set_preview_size(size) {
        if (size === root.preview_size) return;
        if (size !== "off") root.last_preview_size = size;
        root.preview_size = size;
        ThemeAudio.play("cursor");
        Qt.callLater(root.reveal_selected);
    }

    function swap_alt_preview() {
        if (!root.has_alt_preview) return;
        const next = BrowseLayout.alt_swapped(root.preview_size, root.last_preview_size, root.alt_preview_shown);
        root.alt_preview_shown = next.alt;
        if (next.size !== root.preview_size) root.set_preview_size(next.size);
        else ThemeAudio.play("cursor");
    }

    function set_browse_view(view) {
        root.browse_view = view;
        ThemeAudio.play("cursor");
        Qt.callLater(root.reveal_selected);
    }

    // A browse view keeps the selected card clear of the scroll cue's fades, which Contain alone would leave it under.
    function reveal_selected() {
        if (!root.browse) {
            grid.positionViewAtIndex(root.selected, GridView.Contain);
            return;
        }
        if (root.items_hidden || root.results.length === 0) return;
        const row_top = Math.floor(root.selected / root.columns) * grid.cellHeight;
        const fade = root.browse_split.overflows ? root.cue_fade : 0;
        grid.contentY = Cue.reveal_target(row_top, grid.cellHeight - root.browse_gap, grid.contentY, grid.height, grid.contentHeight, 0, fade);
    }

    function step(delta) {
        if (root.results.length === 0) return;
        const before = root.selected;
        root.selected = root.wrap_index(root.selected, delta, 0, root.results.length);
        if (root.selected !== before) ThemeAudio.play("cursor");
    }

    function icon_source(item) {
        if (item.icon_path !== undefined) return item.icon_path;
        const icon = item.icon;
        if (!icon) return Quickshell.iconPath("application-x-executable", true);
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    function handle_key(event) {
        const before = root.cursor_key();
        const ctrl = event.modifiers & Qt.ControlModifier;
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.activate();
        } else if (k === Qt.Key_Down || (ctrl && (k === Qt.Key_J || k === Qt.Key_N))) {
            root.move_row(1);
        } else if (k === Qt.Key_Up || (ctrl && (k === Qt.Key_K || k === Qt.Key_P))) {
            root.move_row(-1);
        } else if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab) && root.tabs.length > 0) {
            root.step_tab(k === Qt.Key_Tab ? 1 : -1);
            root.play_if_moved(before);
        } else if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && root.browse) {
            root.swap_alt_preview();
        } else if (k === Qt.Key_Tab && root.provider && root.provider.expands) {
            root.expand_selected();
        } else if (k === Qt.Key_Tab) {
            root.step(1);
        } else if (k === Qt.Key_Backtab) {
            root.step(-1);
        } else if (ctrl && k === Qt.Key_U) {
            query_input.text = "";
        } else if (root.insert || ctrl || (event.modifiers & Qt.AltModifier)) {
            return;
        } else if (k === Qt.Key_Backspace && root.provider && root.provider.can_go_back) {
            root.go_back();
        } else if (k === Qt.Key_Backspace && Popups.back_name !== "") {
            Popups.back();
        } else if (k === Qt.Key_J) {
            root.move_row(1);
        } else if (k === Qt.Key_K) {
            root.move_row(-1);
        } else if (k === Qt.Key_H || k === Qt.Key_Left) {
            root.step(-1);
        } else if (k === Qt.Key_L || k === Qt.Key_Right) {
            root.step(1);
        } else if (k === Qt.Key_I || event.text === "/") {
            root.set_insert(true);
        } else if (k === Qt.Key_A) {
            root.set_insert(true);
            query_input.cursorPosition = query_input.text.length;
        } else if (root.provider && root.provider.actions.some(a => a.key === event.text && (root.selected_item || a.needs_item === false))) {
            root.provider.run_action(event.text, root.selected_item);
            ThemeAudio.play("confirm");
        } else if (root.browse && (event.text === "=" || event.text === "+")) {
            root.set_preview_size(BrowseLayout.grown(root.preview_size));
        } else if (root.browse && event.text === "-") {
            root.set_preview_size(BrowseLayout.shrunk(root.preview_size));
        } else if (root.browse && event.text === "p") {
            root.set_preview_size(BrowseLayout.toggled(root.preview_size, root.last_preview_size));
        } else if (root.browse && event.text === "v") {
            root.set_browse_view(BrowseLayout.toggled_view(root.browse_view));
        } else if (root.browse && BrowseLayout.digit_index(event.text, root.shown_items) >= 0) {
            // Selects only: Enter opens, so a mistyped digit costs nothing.
            const before = root.selected;
            root.selected = BrowseLayout.digit_index(event.text, root.shown_items);
            if (root.selected !== before) ThemeAudio.play("cursor");
        } else {
            return;
        }
        event.accepted = true;
    }

    ListModel {
        id: slots
    }

    FocusScope {
        id: body
        anchors.fill: parent
        anchors.margins: 12
        focus: true

        Keys.onPressed: event => root.handle_key(event)

        TabRows {
            id: tab_rows
            visible: root.tabs.length > 0
            width: parent.width
            height: visible ? implicitHeight : 0
            labels: root.tabs
            current: root.current_tab
            onPicked: index => root.set_tab(index)
        }

        Rectangle {
            id: query_bar
            y: root.tabs_space
            width: parent.width
            height: Style.px(30)
            radius: Style.radius(4)
            color: Style.pal.bg_surface
            border.width: root.insert ? 1 : 0
            border.color: root.st.caret_color

            Text {
                id: search_glyph
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f002}"
                color: root.st.text_primary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: root.st.fs(-2)
            }

            TextInput {
                id: query_input
                anchors.left: search_glyph.right
                anchors.leftMargin: 10
                anchors.right: status_label.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                color: root.st.text_fg
                selectionColor: root.st.selection_bg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
                onTextChanged: {
                    root.query = text;
                    if (root.is_open && root.provider) TypingSettings.remember("picker:" + root.provider.name, text);
                }
                // A static caret: the default one blinks for as long as the picker is open.
                cursorDelegate: Rectangle {
                    width: 2
                    visible: query_input.activeFocus
                    color: root.st.caret_color
                }

                Keys.onEscapePressed: root.set_insert(false)
                // Runs before TextInput's own handling, so Ctrl+K never falls through to delete-to-end-of-line.
                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const k = event.key;
                    if (k === Qt.Key_Backspace && query_input.text === "" && root.provider && root.provider.can_go_back) {
                        root.go_back();
                        event.accepted = true;
                        return;
                    }
                    if (k === Qt.Key_Backspace && query_input.text === "" && Popups.back_name !== "") {
                        Popups.back();
                        event.accepted = true;
                        return;
                    }
                    const nav = k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_Backtab
                        || k === Qt.Key_Return || k === Qt.Key_Enter
                        || (ctrl && (k === Qt.Key_J || k === Qt.Key_K || k === Qt.Key_N || k === Qt.Key_P || k === Qt.Key_U));
                    if (nav) root.handle_key(event);
                }

                Text {
                    visible: query_input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: query_input.width
                    elide: Text.ElideRight
                    text: root.provider ? root.provider.placeholder : ""
                    color: root.st.text_muted
                    font: query_input.font
                }
            }

            Text {
                id: status_label
                anchors.right: mode_text.left
                anchors.rightMargin: text !== "" ? 10 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.provider ? root.provider.status_text : ""
                color: root.provider && root.provider.status_active ? root.st.text_accent : root.st.text_muted
                font: mode_text.font
            }

            Text {
                id: mode_text
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: (root.insert ? "INSERT" : "NORMAL") + (query_bar.width < Style.px(260) ? "" : "  " + root.results.length + "/" + (root.provider ? root.provider.items.length : 0))
                color: root.insert ? root.st.text_accent : root.st.text_primary
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-4)
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.set_insert(true)
            }
        }

        Item {
            id: list_area
            y: query_bar.y + query_bar.height + 8
            width: parent.width
            height: parent.height - y - (detail.visible ? detail.height + 6 : 0)

            // Browse: the cards sit under the preview, centered, in whole rows; the list's rows span the width, short
            // of the scroll cue's caret.
            GridView {
                id: grid
                x: root.browse && !root.browse_list ? Math.round((parent.width - root.columns * (root.card_width + root.card_gap) + root.card_gap) / 2) : 0
                y: root.browse && root.browse_split.preview_height > 0 ? root.browse_split.preview_height + root.card_gap : 0
                height: root.browse ? root.browse_split.view_height : parent.height
                width: root.browse_list ? parent.width - root.cue_gutter : root.browse ? root.columns * (root.card_width + root.card_gap) : preview_loader.active ? parent.width * 0.62 : parent.width
                visible: !root.items_hidden
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: root.browse_list ? width : root.browse ? root.card_width + root.card_gap : Math.floor(width / root.columns)
                cellHeight: root.browse ? root.browse_cell_height : root.cell_height
                model: slots
                reuseItems: true
                delegate: root.browse_list ? list_delegate : root.browse ? card_delegate : row_delegate
            }

            // Only a browse view: the docked and island lists keep their plain look.
            Loader {
                active: root.browse && !root.items_hidden
                sourceComponent: Component {
                    ScrollCue {
                        target: grid
                        fade_height: root.cue_fade
                        gutter: root.cue_gutter
                    }
                }
            }

            // Framed like the workspace overview's tiles; the provider's card, or generic_card, draws inside.
            Component {
                id: card_delegate

                Item {
                    id: card
                    required property int index
                    readonly property var result: root.results[card.index] || ({ item: {}, positions: [] })
                    readonly property bool is_selected: card.index === root.selected

                    width: root.card_width
                    height: root.card_height

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radius(6)
                        color: card.is_selected ? Qt.tint(Theme.bg_crust, Qt.alpha(root.st.caret_color, 0.08)) : Theme.bg_crust
                        border.width: card.is_selected ? 2 : 1
                        border.color: card.is_selected ? root.st.caret_color : Theme.ui_border
                    }

                    EntryBody {
                        anchors.fill: parent
                        anchors.margins: Style.px(8)
                        sourceComponent: root.provider && root.provider.card ? root.provider.card : generic_card
                        result: card.result
                        is_selected: card.is_selected
                    }

                    QuickHint {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.px(3)
                        index: card.index
                        shown: root.shown_items
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = card.index;
                            root.activate();
                        }
                    }
                }
            }

            // One line per item in the browse list view; the provider's row, or generic_row, draws inside.
            Component {
                id: list_delegate

                Item {
                    id: line
                    required property int index
                    readonly property var result: root.results[line.index] || ({ item: {}, positions: [] })
                    readonly property bool is_selected: line.index === root.selected

                    width: grid.cellWidth
                    height: root.list_row_height

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radius(4)
                        color: line.is_selected ? Qt.tint(Theme.bg_crust, Qt.alpha(root.st.caret_color, 0.08)) : Theme.bg_crust
                        border.width: line.is_selected ? 2 : 1
                        border.color: line.is_selected ? root.st.caret_color : Qt.alpha(Theme.ui_border, 0.5)
                    }

                    EntryBody {
                        anchors.fill: parent
                        anchors.leftMargin: Style.px(8)
                        anchors.rightMargin: Style.px(14) + line_hint.width
                        anchors.topMargin: Style.px(3)
                        anchors.bottomMargin: Style.px(3)
                        sourceComponent: root.provider && root.provider.row ? root.provider.row : generic_row
                        result: line.result
                        is_selected: line.is_selected
                    }

                    QuickHint {
                        id: line_hint
                        anchors.right: parent.right
                        anchors.rightMargin: Style.px(8)
                        anchors.verticalCenter: parent.verticalCenter
                        index: line.index
                        shown: root.shown_items
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = line.index;
                            root.activate();
                        }
                    }
                }
            }

            Component {
                id: generic_row

                Item {
                    id: generic_line
                    property var entry: ({})
                    property var positions: []
                    property bool selected: false

                    IconImage {
                        id: generic_line_icon
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !generic_line.entry.glyph
                        implicitSize: Style.px(20)
                        asynchronous: true
                        source: generic_line.entry.glyph ? "" : root.icon_source(generic_line.entry)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!generic_line.entry.glyph
                        width: Style.px(20)
                        horizontalAlignment: Text.AlignHCenter
                        text: generic_line.entry.glyph || ""
                        textFormat: Text.PlainText
                        color: root.st.text_fg
                        font.family: generic_line.entry.glyph_font || (root.provider && root.provider.glyph_font !== "" ? root.provider.glyph_font : root.st.font_family)
                        font.pixelSize: root.st.fs(1)
                    }

                    Text {
                        id: generic_line_label
                        anchors.left: generic_line_icon.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width * 0.6)
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: Fuzzy.highlight(generic_line.entry.label || "", generic_line.positions, String(root.st.text_accent))
                        color: generic_line.entry.accent ? root.st.text_accent : root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }

                    Text {
                        anchors.left: generic_line_label.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: generic_line.entry.description || ""
                        textFormat: Text.PlainText
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }

            Component {
                id: generic_card

                Item {
                    id: generic
                    property var entry: ({})
                    property var positions: []
                    property bool selected: false

                    IconImage {
                        id: generic_icon
                        visible: !generic.entry.glyph
                        implicitSize: Style.px(20)
                        asynchronous: true
                        source: generic.entry.glyph ? "" : root.icon_source(generic.entry)
                    }

                    Text {
                        visible: !!generic.entry.glyph
                        width: Style.px(20)
                        horizontalAlignment: Text.AlignHCenter
                        text: generic.entry.glyph || ""
                        textFormat: Text.PlainText
                        color: root.st.text_fg
                        font.family: generic.entry.glyph_font || (root.provider && root.provider.glyph_font !== "" ? root.provider.glyph_font : root.st.font_family)
                        font.pixelSize: root.st.fs(2)
                    }

                    Text {
                        id: generic_label
                        anchors.left: generic_icon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.verticalCenter: generic_icon.verticalCenter
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: Fuzzy.highlight(generic.entry.label || "", generic.positions, String(root.st.text_accent))
                        color: generic.entry.accent ? root.st.text_accent : root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }

                    Text {
                        anchors.top: generic_icon.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        text: generic.entry.description || ""
                        textFormat: Text.PlainText
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }

            Component {
                id: row_delegate

                MenuRow {
                    id: row
                    required property int index
                    readonly property var result: root.results[row.index] || ({ item: {}, positions: [] })

                    width: grid.cellWidth - 4
                    height: grid.cellHeight - 2
                    base_radius: 6
                    selected: row.index === root.selected

                    IconImage {
                        id: row_icon
                        x: 8 + row.inset
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Style.px(20)
                        asynchronous: true
                        source: row.result.item.glyph ? "" : root.icon_source(row.result.item)
                        visible: !row.result.item.glyph
                    }

                    Text {
                        id: row_glyph
                        visible: !!row.result.item.glyph
                        x: 8 + row.inset
                        width: Style.px(20)
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: row.result.item.glyph || ""
                        textFormat: Text.PlainText
                        color: row.fg(root.st.text_fg)
                        font.family: row.result.item.glyph_font || (root.provider && root.provider.glyph_font !== "" ? root.provider.glyph_font : root.st.font_family)
                        font.weight: row.result.item.glyph_weight || Font.Normal
                        font.pixelSize: root.st.fs(2)
                    }

                    Text {
                        id: row_label
                        anchors.left: row_icon.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, row.width - x - 8 - (row_desc.visible ? Style.px(40) : 0))
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: Fuzzy.highlight(row.result.item.label || "", row.result.positions, String(row.fg(root.st.text_accent)))
                        color: row.fg(row.result.item.accent ? root.st.text_accent : root.st.text_fg)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-1)
                    }

                    Text {
                        id: row_desc
                        visible: root.columns === 1 && text !== "" && row.width - row_label.x - row_label.implicitWidth > Style.px(90)
                        anchors.left: row_label.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: row.result.item.description || ""
                        textFormat: Text.PlainText
                        color: row.fg(root.st.text_muted)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = row.index;
                            root.activate();
                        }
                    }
                }
            }

            Text {
                visible: root.results.length === 0 && !root.items_hidden
                anchors.centerIn: grid
                text: root.provider && root.provider.items.length > 0 ? "No matches" : root.provider ? root.provider.empty_text : "Nothing to pick"
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Loader {
                id: preview_loader
                x: root.browse ? 0 : parent.width - width
                width: root.browse ? parent.width : parent.width * 0.38 - 8
                height: root.browse ? root.browse_split.preview_height : parent.height
                // Unloaded while the browse preview is off, so a live one (the agents' pane capture) stops polling.
                active: root.visible && !!root.provider && root.provider.preview !== null && !(root.browse && root.preview_size === "off")
                sourceComponent: root.showing_alt ? root.provider.alt_preview : root.provider ? root.provider.preview : null
            }

            Binding {
                target: preview_loader.item
                property: "entry"
                value: root.selected_item
                when: preview_loader.status === Loader.Ready && !root.showing_alt
            }
        }

        Text {
            id: detail
            // A browse card shows its own description.
            visible: !root.browse
            anchors.bottom: parent.bottom
            width: parent.width
            elide: Text.ElideRight
            text: root.selected_item && root.selected_item.description ? root.selected_item.description : " "
            textFormat: Text.PlainText
            color: root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }

    // A card's or list row's body: the provider's component given the item, its query match and whether it is selected.
    component EntryBody: Loader {
        id: entry_body
        property var result: ({ item: {}, positions: [] })
        property bool is_selected: false

        Binding {
            target: entry_body.item
            property: "entry"
            value: entry_body.result.item
            when: entry_body.status === Loader.Ready
        }

        Binding {
            target: entry_body.item
            property: "positions"
            value: entry_body.result.positions
            when: entry_body.status === Loader.Ready
        }

        Binding {
            target: entry_body.item
            property: "selected"
            value: entry_body.is_selected
            when: entry_body.status === Loader.Ready
        }
    }

    // The digit that selects the item in NORMAL mode, on the first nine on screen; shown in INSERT too, so it can be read ahead.
    component QuickHint: Rectangle {
        id: hint
        property int index: -1
        property var shown: ({ first: 0, end: 0 })
        readonly property string digit: BrowseLayout.hint_of(hint.index, hint.shown)

        visible: hint.digit !== ""
        width: Math.max(height, hint_text.implicitWidth + 6)
        height: hint_text.implicitHeight + 2
        radius: Style.radius(3)
        color: Qt.alpha(Theme.bg_surface, 0.9)

        Text {
            id: hint_text
            anchors.centerIn: parent
            text: hint.digit
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.bold: true
        }
    }
}
