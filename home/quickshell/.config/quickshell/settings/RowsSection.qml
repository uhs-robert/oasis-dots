// home/quickshell/.config/quickshell/settings/RowsSection.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// A section of ChoiceRows; each row is { label, values: () => [...], text: v => string, value: () => current, set: v => void }.
SettingsPane {
    id: root

    property var rows: []
    property int cursor: 0
    default property alias header: header_col.data
    property alias footer: footer_col.data

    // Keys the rows do not use, for sections with their own.
    signal extra_key(var event)

    footer_hint: "j/k move · h/l change · Esc sections · q close"
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

    function search_select(index) {
        root.cursor = index;
    }

    function jump(delta) {
        root.cursor = delta < 0 ? 0 : root.rows.length - 1;
    }

    Keys.onPressed: event => {
        if (event.modifiers & Qt.ControlModifier) return;
        if (event.key === Qt.Key_J) root.cursor = root.wrap_index(root.cursor, 1, root.rows.length);
        else if (event.key === Qt.Key_K) root.cursor = root.wrap_index(root.cursor, -1, root.rows.length);
        else if (event.key === Qt.Key_H) root.step(root.cursor, -1);
        else if (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.step(root.cursor, 1);
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

        Repeater {
            model: root.rows

            ChoiceRow {
                id: row
                required property int index
                required property var modelData

                selected: root.live && row.index === root.cursor
                label: row.modelData.label
                value_text: row.modelData.text(row.modelData.value())
                onStepped: delta => {
                    root.focus_pane();
                    root.cursor = row.index;
                    root.step(row.index, delta);
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
