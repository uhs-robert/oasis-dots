import QtQuick
import QtQuick.Layouts
import qs.features.audio
import qs.theme

// A section of ChoiceRows; each row is { label, values: () => [...], text: v => string, value: () => current, set: v => void, pick?: bool }.
// Enter or a click opens a filterable list of a row's values; `pick: false` keeps a row cycling and `cycle: false` stops H/L from stepping it, and `activate: () => void` replaces Enter or a click.
// A row's `desc` (text), optional `help` (a longer explanation shown under it) and optional `keys` (hint) fill the pane's description block for the selected or hovered row; `section_keys` follow every row's keys.
// The block shows once any row has a `desc`, so give every row one.
SettingsPane {
    id: root

    property var rows: []
    property int cursor: 0
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
    // Content shown beside the open picker list, and under the rows when none is open.
    property alias side: side_col.data
    readonly property real side_width: Style.px(420)
    readonly property real side_gap: Style.px(12)
    readonly property bool has_side: side_col.visibleChildren.length > 0
    // Below this width the side content drops under a list that is capped at its slot, rather than squeezing the list.
    // A section with no side content never caps its list.
    readonly property bool side_fits: root.has_side && root.width >= root.side_width + Style.px(360) + root.side_gap

    // Keys the rows do not use, for sections with their own.
    signal extra_key(var event)
    // Runs first; a section that accepts the event keeps it from the rows.
    signal first_key(var event)

    onCursorChanged: if (root.live) ThemeAudio.play("cursor")

    footer_hint: "j/k move · H/L change · Enter list · h/Esc sections · q close"
    search_rows: root.rows.map(r => r.label)
    search_cursor: root.cursor
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

    function step(index, delta) {
        const row = root.rows[index];
        if (!row || row.cycle === false) return;
        const values = row.values();
        if (values.length === 0) return;
        const at = values.indexOf(row.value());
        const next = at < 0 ? (delta > 0 ? 0 : values.length - 1) : root.wrap_index(at, delta, values.length);
        row.set(values[next]);
        ThemeAudio.play("confirm");
    }

    function pickable(index) {
        const row = root.rows[index];
        return !!row && row.pick !== false && row.values().length >= root.pick_min;
    }

    function open_picker(index) {
        const row = root.rows[index];
        const values = row.values();
        root.cursor = index;
        root.open_list(row.label, values, values.map(v => row.text(v)), row.value(), v => row.set(v));
    }

    // Opens the list over arbitrary values (not just a row's), with an optional image url per value.
    function open_list(title, values, labels, current, on_pick, thumbs) {
        root.pick_values = values;
        root.show_picker(picker, title, labels, values.indexOf(current), i => {
            on_pick(values[i]);
            ThemeAudio.play("confirm");
        }, thumbs);
    }

    function keys_of(row) {
        if (!row) return root.section_keys;
        let keys = row.keys;
        if (keys === undefined) {
            const parts = [];
            const values = row.values();
            const is_toggle = values.length === 2 && values[0] === "on";
            if (row.cycle !== false) parts.push(is_toggle ? "H/L toggle" : "H/L change");
            if (row.activate || row.pick !== false && values.length >= root.pick_min) parts.push("Enter list");
            keys = parts.join(" · ");
        }
        return [keys, root.section_keys].filter(k => k !== "").join(" · ");
    }

    function activate(index, delta) {
        const row = root.rows[index];
        if (row && row.activate) row.activate();
        else if (root.pickable(index)) root.open_picker(index);
        else root.step(index, delta);
    }

    function search_select(index) {
        root.cursor = index;
    }

    function jump(delta) {
        root.cursor = delta < 0 ? 0 : root.rows.length - 1;
    }

    Keys.onPressed: event => {
        if (root.picking) return;
        if (event.modifiers & Qt.ControlModifier) return;
        root.first_key(event);
        if (event.accepted) return;
        if (event.key === Qt.Key_J) root.cursor = root.wrap_index(root.cursor, 1, root.rows.length);
        else if (event.key === Qt.Key_K) root.cursor = root.wrap_index(root.cursor, -1, root.rows.length);
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

        Repeater {
            model: root.rows

            ChoiceRow {
                id: row
                required property int index
                required property var modelData

                visible: !root.picking
                selected: root.live && row.index === root.cursor
                label: row.modelData.label
                value_text: row.modelData.text(row.modelData.value())
                onHoveredChanged: {
                    if (row.hovered) root.hovered_row = row.index;
                    else if (root.hovered_row === row.index) root.hovered_row = -1;
                }
                // A row whose Enter does something else (activate) still steps on a click, so the mouse can change its value.
                onStepped: delta => {
                    root.focus_pane();
                    root.cursor = row.index;
                    if (row.modelData.activate && row.modelData.cycle !== false) root.step(row.index, delta);
                    else root.activate(row.index, delta);
                }
            }
        }

        // The list fills the left and `side` sits right of it. The list overflows its slot into the pane's spare
        // height, so `side` must not sit below it; when it cannot sit beside, the list is capped at the slot instead.
        GridLayout {
            id: picker_grid
            visible: root.picking || root.has_side
            Layout.fillWidth: true
            columns: root.side_fits ? 2 : 1
            columnSpacing: root.side_gap
            rowSpacing: 4

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
                    visible: root.picking
                    st: root.st
                    available_height: root.has_side && !root.side_fits ? picker.default_height : Math.max(0, root.height - picker_grid.y - 4)
                    onPicked: index => root.finish_picker(index)
                    onClosed: root.hide_picker()
                }
            }

            ColumnLayout {
                id: side_col
                visible: side_col.visibleChildren.length > 0
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: !root.picking || !root.side_fits
                Layout.preferredWidth: root.picking && root.side_fits ? root.side_width : -1
                spacing: 4
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
