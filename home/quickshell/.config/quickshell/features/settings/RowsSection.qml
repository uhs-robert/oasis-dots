import QtQuick
import QtQuick.Layouts
import qs.features.audio
import qs.theme
import qs.ui.menu
import "SettingsScale.js" as SScale

// A section of ChoiceRows; each row is { label, values: () => [...], text: v => string, value: () => current, set: v => void, pick?: bool }.
// Enter or a click opens a filterable list of a row's values; `pick: false` keeps a row cycling and `cycle: false` stops H/L from stepping it, and `activate: () => void` replaces Enter or a click.
// `indent: n` nests a row under the one above it. `{ heading: "Name" }` is a heading row: never selected, `{`/`}` jump between them.
// `tabs: [{ label, rows }]` instead of `rows` splits a long section into tabs `[`/`]` step; an empty tab is not shown.
// A row's `desc` (text), optional `help` (a longer explanation shown under it) and optional `keys` (hint) fill the pane's description block for the selected or hovered row; `section_keys` follow every row's keys.
// The block shows once any row has a `desc`, so give every row one.
SettingsPane {
    id: root

    property var tabs: []
    readonly property var shown_tabs: root.tabs.filter(t => t.rows.some(r => !root.is_heading(r)))
    // Kept by label, so a tab that empties and refills (the theme's options follow the style) does not move the others.
    property string tab_label: ""
    readonly property int tab_index: Math.max(0, root.shown_tabs.findIndex(t => t.label === root.tab_label))
    property var tab_cursors: ({})
    property var rows: root.shown_tabs.length > 0 ? root.shown_tabs[root.tab_index].rows : []
    property int cursor: 0
    readonly property bool has_headings: root.rows.some(r => root.is_heading(r))
    // The heading over the cursor, "" above the first one; a section shows a preview for one group of rows by it.
    readonly property string cursor_heading: root.heading_above(root.cursor)
    readonly property string layout_hint: (root.shown_tabs.length > 1 ? "[/] tab · " : "") + (root.has_headings ? "{/} heading · " : "")
    property int pick_min: 2
    property var pick_values: []
    property string section_keys: ""
    property int hovered_row: -1
    readonly property var described_row: root.rows[root.hovered_row >= 0 ? root.hovered_row : root.cursor] || null
    readonly property bool has_descriptions: root.rows.some(r => !!r.desc)
    // The value under the open list's cursor, undefined when no list is open.
    readonly property var highlighted_value: root.picking && picker.highlighted >= 0 ? root.pick_values[picker.highlighted] : undefined
    default property alias header: header_col.data
    property alias footer: footer_col.data
    // A section's preview, docked in the popup's panel under the help card, never among the rows or the open list.
    property alias preview: preview_col.data

    // Where every row's value starts, past the longest label of any tab, so values sit in one column near their labels
    // however wide the pane is; capped at 60% of the row, where a long label elides.
    readonly property real value_column: {
        const f = label_metrics.font;
        let need = 0;
        for (const r of (root.shown_tabs.length > 0 ? root.shown_tabs.reduce((all, t) => all.concat(t.rows), []) : root.rows)) {
            if (!root.is_heading(r)) need = Math.max(need, (r.indent || 0) * Style.px(14) + label_metrics.advanceWidth(r.label));
        }
        return Math.min(Math.ceil(need) + Style.px(40), Math.round(root.width * 0.6));
    }

    FontMetrics {
        id: label_metrics
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size + SScale.bump_of(root)
    }

    // Keys the rows do not use, for sections with their own.
    signal extra_key(var event)
    // Runs first; a section that accepts the event keeps it from the rows.
    signal first_key(var event)

    onCursorChanged: {
        if (root.is_heading(root.rows[root.cursor])) root.cursor = root.next_row(root.cursor, 1);
        else if (root.live) ThemeAudio.play("cursor");
    }
    // Deferred: rows are first built while a binding reads them, and moving the cursor then loops back into that binding.
    onRowsChanged: Qt.callLater(root.settle_cursor)
    Component.onCompleted: root.settle_cursor()

    function settle_cursor() {
        if (root.cursor >= root.rows.length || root.is_heading(root.rows[root.cursor])) root.cursor = root.next_row(Math.min(root.cursor, root.rows.length - 1), 1);
    }

    footer_hint: "j/k move · " + root.layout_hint + "H/L change · Enter list · h/Esc sections · q close"
    // Every tab's rows, so a search finds a row on a tab not shown; headings are blank and never match.
    search_rows: (root.shown_tabs.length > 0 ? root.shown_tabs.reduce((all, t) => all.concat(t.rows), []) : root.rows).map(r => root.is_heading(r) ? "" : r.label)
    search_cursor: root.tab_offset(root.tab_index) + root.cursor
    // Where the rows end, for a section that sizes its own content below them.
    readonly property real footer_top: footer_col.y
    described: root.has_descriptions
    description: {
        const row = root.described_row;
        if (!row || !row.desc) return "";
        return row.help ? row.desc + "\n\n" + row.help : row.desc;
    }
    description_keys: root.keys_of(root.described_row)
    implicitHeight: col.implicitHeight

    function is_heading(row) {
        return !!row && row.heading !== undefined;
    }

    // The next row from `from` that is not a heading, `delta` 1 or -1, wrapping; `from` (kept in range) when there is none.
    function next_row(from, delta) {
        const count = root.rows.length;
        for (let s = 1; s <= count; s++) {
            const i = root.wrap_index(from, delta * s, count);
            if (!root.is_heading(root.rows[i])) return i;
        }
        return Math.max(0, Math.min(from, count - 1));
    }

    function heading_above(index) {
        for (let i = Math.min(index, root.rows.length - 1); i >= 0; i--) {
            if (root.is_heading(root.rows[i])) return root.rows[i].heading;
        }
        return "";
    }

    // The first row of each run of rows between headings.
    function group_starts() {
        const starts = [];
        let open = true;
        root.rows.forEach((r, i) => {
            if (root.is_heading(r)) open = true;
            else if (open) {
                starts.push(i);
                open = false;
            }
        });
        return starts;
    }

    // `}` goes to the next group's first row; `{` to the start of this group, or from there to the previous group's.
    function step_heading(delta) {
        const starts = root.group_starts();
        if (starts.length === 0) return;
        let at = 0;
        starts.forEach((start, n) => {
            if (start <= root.cursor) at = n;
        });
        if (delta < 0 && root.cursor > starts[at]) root.cursor = starts[at];
        else root.cursor = starts[root.wrap_index(at, delta, starts.length)];
    }

    // Ctrl+D/U: about half the pane's height of rows, never past either end (no wrap, as in vim).
    function half_page(delta) {
        let steps = root.popup && root.popup.half_page_rows ? root.popup.half_page_rows : 8;
        let at = root.cursor;
        for (let i = at + delta; steps > 0 && i >= 0 && i < root.rows.length; i += delta) {
            if (root.is_heading(root.rows[i])) continue;
            at = i;
            steps--;
        }
        root.cursor = at;
    }

    function tab_offset(index) {
        let offset = 0;
        for (let i = 0; i < index && i < root.shown_tabs.length; i++) offset += root.shown_tabs[i].rows.length;
        return offset;
    }

    function set_tab(index, cursor) {
        const tab = root.shown_tabs[index];
        if (!tab || index === root.tab_index && cursor === undefined) return;
        const saved = Object.assign({}, root.tab_cursors);
        saved[root.shown_tabs[root.tab_index].label] = root.cursor;
        root.tab_cursors = saved;
        root.tab_label = tab.label;
        const wanted = cursor !== undefined ? cursor : saved[tab.label] !== undefined ? saved[tab.label] : root.next_row(-1, 1);
        root.cursor = Math.max(0, Math.min(wanted, root.rows.length - 1));
    }

    // Opens the tab or heading named `part` (an old section id's place in a merged section); false when there is none.
    function focus_part(part) {
        const tab = root.shown_tabs.findIndex(t => t.label === part);
        if (tab >= 0) {
            root.set_tab(tab);
            root.cursor = root.next_row(-1, 1);
            return true;
        }
        const heading = root.rows.findIndex(r => root.is_heading(r) && r.heading === part);
        if (heading < 0) return false;
        root.cursor = root.next_row(heading, 1);
        return true;
    }

    function step(index, delta) {
        const row = root.rows[index];
        if (!row || root.is_heading(row) || row.cycle === false) return;
        const values = row.values();
        if (values.length === 0) return;
        const at = values.indexOf(row.value());
        const next = at < 0 ? (delta > 0 ? 0 : values.length - 1) : root.wrap_index(at, delta, values.length);
        row.set(values[next]);
        ThemeAudio.play("confirm");
    }

    function pickable(index) {
        const row = root.rows[index];
        return !!row && !root.is_heading(row) && row.pick !== false && row.values().length >= root.pick_min;
    }

    function open_picker(index) {
        const row = root.rows[index];
        const values = row.values();
        root.cursor = index;
        root.open_list(row.label, values, values.map(v => row.text(v)), row.value(), v => row.set(v));
    }

    // Opens the list over arbitrary values (not just a row's), with an optional image url per value. `split` puts the
    // rows in the help column and a large preview of the highlighted thumb in the pane (PickerList.list_host).
    function open_list(title, values, labels, current, on_pick, thumbs, split) {
        picker.list_host = split && root.popup && root.popup.description_host ? root.popup.description_host : null;
        root.pick_values = values;
        root.show_picker(picker, title, labels, values.indexOf(current), i => {
            on_pick(values[i]);
            ThemeAudio.play("confirm");
        }, thumbs);
    }

    function keys_of(row) {
        const layout = root.layout_hint.replace(/ · $/, "");
        if (!row || root.is_heading(row)) return [root.section_keys, layout, "C-d/C-u half page"].filter(k => k !== "").join(" · ");
        let keys = row.keys;
        if (keys === undefined) {
            const parts = [];
            const values = row.values();
            const is_toggle = values.length === 2 && values[0] === "on";
            if (row.cycle !== false) parts.push(is_toggle ? "H/L toggle" : "H/L change");
            if (row.activate || row.pick !== false && values.length >= root.pick_min) parts.push("Enter list");
            keys = parts.join(" · ");
        }
        return [keys, root.section_keys, layout, "C-d/C-u half page"].filter(k => k !== "").join(" · ");
    }

    function activate(index, delta) {
        const row = root.rows[index];
        if (row && row.activate) row.activate();
        else if (root.pickable(index)) root.open_picker(index);
        else root.step(index, delta);
    }

    function search_select(index) {
        if (root.shown_tabs.length === 0) {
            root.cursor = index;
            return;
        }
        for (let t = root.shown_tabs.length - 1; t >= 0; t--) {
            if (index < root.tab_offset(t)) continue;
            root.set_tab(t, index - root.tab_offset(t));
            return;
        }
    }

    function jump(delta) {
        root.cursor = root.next_row(delta < 0 ? -1 : root.rows.length, delta < 0 ? 1 : -1);
    }

    Keys.onPressed: event => {
        if (root.picking) return;
        if (event.modifiers & Qt.ControlModifier) return;
        root.first_key(event);
        if (event.accepted) return;
        if (event.key === Qt.Key_J) root.cursor = root.next_row(root.cursor, 1);
        else if (event.key === Qt.Key_K) root.cursor = root.next_row(root.cursor, -1);
        else if ((event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight) && root.shown_tabs.length > 1) root.set_tab(root.wrap_index(root.tab_index, event.key === Qt.Key_BracketLeft ? -1 : 1, root.shown_tabs.length));
        else if ((event.key === Qt.Key_BraceLeft || event.key === Qt.Key_BraceRight) && root.has_headings) root.step_heading(event.key === Qt.Key_BraceLeft ? -1 : 1);
        // Plain h is left for the popup, which goes back to the sidebar.
        else if (event.key === Qt.Key_H && (event.modifiers & Qt.ShiftModifier)) root.step(root.cursor, -1);
        // A row that does not step (cycle: false) goes in on plain l, as Enter does, per the Settings contract.
        else if (event.key === Qt.Key_L && !(event.modifiers & Qt.ShiftModifier) && root.rows[root.cursor] && root.rows[root.cursor].cycle === false) root.activate(root.cursor, 1);
        else if (event.key === Qt.Key_L || event.key === Qt.Key_Space) root.step(root.cursor, 1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.activate(root.cursor, 1);
        else {
            root.extra_key(event);
            return;
        }
        event.accepted = true;
    }

    ColumnLayout {
        id: preview_col
        parent: root.popup && root.popup.preview_host ? root.popup.preview_host : root
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4

        ColumnLayout {
            id: header_col
            visible: header_col.visibleChildren.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 4
        }

        // Held at the chips' own width, since TabRows centers chips and the strip belongs over the labels, left.
        Item {
            visible: root.shown_tabs.length > 1 && !root.picking
            Layout.fillWidth: true
            Layout.preferredHeight: tab_strip.implicitHeight
            Layout.bottomMargin: 6

            TabRows {
                id: tab_strip
                width: Math.min(parent.width, tab_strip.label_needs.reduce((sum, w) => sum + w + tab_strip.spacing, tab_strip.well_pad * 2))
                chips: true
                labels: root.shown_tabs.map(t => t.label)
                current: root.tab_index
                onPicked: index => {
                    root.focus_pane();
                    root.set_tab(index);
                }
            }
        }

        Repeater {
            model: root.rows

            ColumnLayout {
                id: entry
                required property int index
                required property var modelData
                readonly property bool heading: root.is_heading(entry.modelData)

                visible: !root.picking
                Layout.fillWidth: true
                spacing: 0

                MenuSection {
                    visible: entry.heading
                    Layout.fillWidth: true
                    topPadding: entry.index === 0 ? 0 : 8
                    bottomPadding: 2
                    label: entry.heading ? entry.modelData.heading : ""
                    size_bump: SScale.bump_of(root)
                    fg_override: root.popup && root.popup.group_fg !== undefined ? root.popup.group_fg : "transparent"
                }

                ChoiceRow {
                    id: row
                    visible: !entry.heading
                    selected: root.live && entry.index === root.cursor
                    label: entry.heading ? "" : entry.modelData.label
                    indent: entry.modelData.indent || 0
                    value_x: root.value_column
                    value_text: entry.heading ? "" : entry.modelData.text(entry.modelData.value())
                    onHoveredChanged: {
                        if (row.hovered) root.hovered_row = entry.index;
                        else if (root.hovered_row === entry.index) root.hovered_row = -1;
                    }
                    // A row whose Enter does something else (activate) still steps on a click, so the mouse can change its value.
                    onStepped: delta => {
                        root.focus_pane();
                        root.cursor = entry.index;
                        if (entry.modelData.activate && entry.modelData.cycle !== false) root.step(entry.index, delta);
                        else root.activate(entry.index, delta);
                    }
                }
            }
        }

        // The list overflows its slot into the pane's spare height.
        Item {
            id: picker_slot
            visible: root.picking
            Layout.fillWidth: true
            Layout.preferredHeight: picker.default_height

            PickerList {
                id: picker
                objectName: "picker"
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                // Split, it fills the pane down to its bottom edge, so the filter box sits there under the preview.
                height: picker.split ? picker.available_height : picker.implicitHeight
                visible: root.picking
                st: root.st
                // The visible pane, not the section's own height, which grows past it with a long section.
                available_height: Math.max(0, (root.popup && root.popup.pane_view_height ? root.popup.pane_view_height : root.height) - picker_slot.y - 4)
                list_height: root.popup && root.popup.help_room !== undefined ? root.popup.help_room : 0
                onPicked: index => root.finish_picker(index)
                onClosed: root.hide_picker()
            }
        }

        ColumnLayout {
            id: footer_col
            visible: footer_col.visibleChildren.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 4
        }
    }
}
