// home/quickshell/.config/quickshell/picker/Picker.qml
import QtQuick
import Quickshell
import Quickshell.Widgets
import "../components"
import "../theme"
import "../services"
import "Fuzzy.js" as Fuzzy

// The shared picker over Pickers.provider: docked at the bottom from IPC, or dropped from an island when opened with an anchor.
Popup {
    id: root

    popup_name: "picker"
    size_class: "large"
    dock_bottom: root.held_anchor === null
    fit_island: !root.dock_bottom
    anim_scale: 0.3
    preferred_width: 320
    title: root.provider ? root.provider.title.toUpperCase() : "PICKER"
    footer_hint: "Enter " + root.verb + " · Esc normal · q close"
    footer_override: root.insert ? "Enter " + root.verb + " · Esc normal" : root.action_hint !== "" ? "Enter " + root.verb + " · " + root.action_hint + " · ? help · q close" : ""
    key_help: ["Enter " + root.verb, "Up/Down move", "Ctrl+j/k move", "Tab/Shift+Tab next/prev", "Ctrl+u clear", "Esc normal mode", "j/k rows", "h/l columns", "gg/G first/last", "i/a insert", "/ search"].concat(root.action_hint !== "" ? [root.action_hint] : []).concat(["q/Esc close"]).join(" · ")
    jumps_enabled: !root.insert

    readonly property var provider: Pickers.provider
    readonly property string verb: root.provider ? root.provider.verb : "open"
    readonly property string action_hint: root.provider ? root.provider.actions.map(a => a.key + " " + a.desc).join(" · ") : ""
    readonly property bool is_open: Popups.open_name === "picker"
    readonly property int columns: root.dock_bottom && root.provider ? Math.max(1, root.provider.columns) : 1
    readonly property real cell_height: Style.px(30)
    readonly property real screen_height: root.screen ? root.screen.height : 1080
    readonly property real anchored_height: query_bar.height + 8 + root.cell_height * Math.max(1, Math.min(10, root.results.length)) + detail.height + 6 + 24

    body_height: root.dock_bottom ? Math.round(root.screen_height * 0.4) - root.header_height - root.footer_height - root.st.frame_drop : root.anchored_height

    property string query: ""
    property int selected: 0
    property bool insert: true

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
    onSelectedChanged: grid.positionViewAtIndex(root.selected, GridView.Contain)
    onJump_first: root.selected = 0
    onJump_last: root.selected = Math.max(0, root.results.length - 1)

    // Reset once hidden so an open finds the empty-query results already laid out.
    onVisibleChanged: if (!visible) root.reset()
    onIs_openChanged: if (is_open) {
        root.reset();
        root.set_insert(!root.provider || root.provider.starts_insert);
    }
    Component.onCompleted: root.sync_slots()

    Connections {
        target: Pickers

        function onStep_requested(delta) {
            root.step(delta);
        }
    }

    function reset() {
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
        const out = [];
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const f = use_usage ? Pickers.frecency(name, item.id) : 0;
            const bonus = f > 0 ? 12 * Math.log2(1 + f) : 0;
            if (terms.length === 0) {
                out.push({ item: item, positions: [], score: bonus, order: i });
                continue;
            }
            const m = Fuzzy.score_item(terms, item);
            if (m) out.push({ item: item, positions: m.positions, score: m.score + bonus, order: i });
        }
        if (keep_order && terms.length === 0) return out;
        out.sort((a, b) => b.score - a.score || (keep_order ? a.order - b.order : (terms.length > 0 ? a.item.label.length - b.item.label.length : 0) || a.item.label.localeCompare(b.item.label)));
        return out;
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
        Pickers.close();
        p.activate(item);
    }

    // j/k keep the column and wrap top to bottom; a short last row lands on its last item.
    function move_row(delta) {
        const n = root.results.length;
        if (n === 0) return;
        const cols = root.columns;
        if (cols === 1) {
            root.selected = root.wrap_index(root.selected, delta, 0, n);
            return;
        }
        const rows = Math.ceil(n / cols);
        const col = root.selected % cols;
        const row = (Math.floor(root.selected / cols) + delta + rows) % rows;
        root.selected = Math.min(n - 1, row * cols + col);
    }

    function step(delta) {
        if (root.results.length > 0) root.selected = root.wrap_index(root.selected, delta, 0, root.results.length);
    }

    function icon_source(item) {
        if (item.icon_path !== undefined) return item.icon_path;
        const icon = item.icon;
        if (!icon) return Quickshell.iconPath("application-x-executable", true);
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    function handle_key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.activate();
        } else if (k === Qt.Key_Down || (ctrl && (k === Qt.Key_J || k === Qt.Key_N))) {
            root.move_row(1);
        } else if (k === Qt.Key_Up || (ctrl && (k === Qt.Key_K || k === Qt.Key_P))) {
            root.move_row(-1);
        } else if (k === Qt.Key_Tab) {
            root.step(1);
        } else if (k === Qt.Key_Backtab) {
            root.step(-1);
        } else if (ctrl && k === Qt.Key_U) {
            query_input.text = "";
        } else if (root.insert || ctrl || (event.modifiers & Qt.AltModifier)) {
            return;
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
        } else if (root.provider && root.selected_item && root.provider.actions.some(a => a.key === event.text)) {
            root.provider.run_action(event.text, root.selected_item);
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

        Rectangle {
            id: query_bar
            width: parent.width
            height: Style.px(30)
            radius: Style.radius(4)
            color: Theme.bg_surface
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
                anchors.right: mode_text.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                focus: true
                clip: true
                color: root.st.text_fg
                selectionColor: root.st.selection_bg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
                onTextChanged: root.query = text
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
            y: query_bar.height + 8
            width: parent.width
            height: parent.height - y - detail.height - 6

            GridView {
                id: grid
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: preview_loader.active ? parent.width * 0.62 : parent.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / root.columns)
                cellHeight: root.cell_height
                model: slots
                reuseItems: true

                delegate: MenuRow {
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
                        source: root.icon_source(row.result.item)
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
                        color: row.fg(root.st.text_fg)
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
                visible: root.results.length === 0
                anchors.centerIn: grid
                text: root.provider && root.provider.items.length > 0 ? "No matches" : "Nothing to pick"
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Loader {
                id: preview_loader
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * 0.38 - 8
                active: root.visible && !!root.provider && root.provider.preview !== null
                sourceComponent: root.provider ? root.provider.preview : null
            }

            Binding {
                target: preview_loader.item
                property: "entry"
                value: root.selected_item
                when: preview_loader.status === Loader.Ready
            }
        }

        Text {
            id: detail
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
}
