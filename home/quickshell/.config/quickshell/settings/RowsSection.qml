// home/quickshell/.config/quickshell/settings/RowsSection.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// A section of ChoiceRows; each row is { label, values: () => [...], text: v => string, value: () => current, set: v => void, pick?: bool }.
// Enter or a click opens a filterable list of a row's values; `pick: false` keeps a row cycling.
SettingsPane {
    id: root

    property var rows: []
    property int cursor: 0
    property int pick_min: 2
    property int picking_row: -1
    default property alias header: header_col.data
    property alias footer: footer_col.data

    // Keys the rows do not use, for sections with their own.
    signal extra_key(var event)
    // Runs first; a section that accepts the event keeps it from the rows.
    signal first_key(var event)

    footer_hint: "j/k move · h/l change · Enter list · Esc sections · q close"
    search_rows: root.rows.map(r => r.label)
    search_cursor: root.cursor
    implicitHeight: col.implicitHeight

    function step(index, delta) {
        const row = root.rows[index];
        if (!row) return;
        const values = row.values();
        if (values.length === 0) return;
        const at = values.indexOf(row.value());
        const next = at < 0 ? (delta > 0 ? 0 : values.length - 1) : root.wrap_index(at, delta, values.length);
        row.set(values[next]);
    }

    function pickable(index) {
        const row = root.rows[index];
        return !!row && row.pick !== false && row.values().length >= root.pick_min;
    }

    function open_picker(index) {
        const row = root.rows[index];
        const values = row.values();
        picker.title = row.label;
        picker.items = values.map(v => ({ label: row.text(v) }));
        picker.current = values.indexOf(row.value());
        root.cursor = index;
        root.picking_row = index;
        root.picking = true;
        picker.open();
    }

    function close_picker() {
        if (!root.picking) return;
        root.picking = false;
        root.picking_row = -1;
        root.forceActiveFocus();
    }

    function pick(item_index) {
        const row = root.rows[root.picking_row];
        if (row) row.set(row.values()[item_index]);
        root.close_picker();
    }

    function activate(index, delta) {
        if (root.pickable(index)) root.open_picker(index);
        else root.step(index, delta);
    }

    onLiveChanged: if (!root.live) root.close_picker()

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
        else if (event.key === Qt.Key_H) root.step(root.cursor, -1);
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
            visible: header_col.children.length > 0
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 4
        }

        PickerList {
            id: picker
            visible: root.picking
            st: root.st
            onPicked: index => root.pick(index)
            onClosed: root.close_picker()
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
                onStepped: delta => {
                    root.focus_pane();
                    root.cursor = row.index;
                    root.activate(row.index, delta);
                }
            }
        }

        ColumnLayout {
            id: footer_col
            visible: footer_col.children.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 4
        }
    }
}
