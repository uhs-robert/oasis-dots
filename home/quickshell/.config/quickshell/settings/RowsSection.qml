// home/quickshell/.config/quickshell/settings/RowsSection.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

// A section of ChoiceRows; each row is { label, values: () => [...], text: v => string, value: () => current, set: v => void, pick?: bool }.
// Enter or a click opens a filterable list of a row's values; `pick: false` keeps a row cycling and `cycle: false` stops H/L from stepping it, and `activate: () => void` replaces Enter or a click.
SettingsPane {
    id: root

    property var rows: []
    property int cursor: 0
    property int pick_min: 2
    property var pick_values: []
    // The value under the open list's cursor, undefined when no list is open.
    readonly property var highlighted_value: root.picking && picker.highlighted >= 0 ? root.pick_values[picker.highlighted] : undefined
    default property alias header: header_col.data
    property alias footer: footer_col.data

    // Keys the rows do not use, for sections with their own.
    signal extra_key(var event)
    // Runs first; a section that accepts the event keeps it from the rows.
    signal first_key(var event)

    onCursorChanged: if (root.live) ThemeAudio.play("cursor")

    footer_hint: "j/k move · H/L change · Enter list · h/Esc sections · q close"
    search_rows: root.rows.map(r => r.label)
    search_cursor: root.cursor
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
        root.pick_values = values;
        root.show_picker(picker, row.label, values.map(v => row.text(v)), values.indexOf(row.value()), i => {
            row.set(values[i]);
            ThemeAudio.play("confirm");
        });
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
            onPicked: index => root.finish_picker(index)
            onClosed: root.hide_picker()
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
