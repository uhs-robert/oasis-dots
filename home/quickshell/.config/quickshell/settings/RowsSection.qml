// home/quickshell/.config/quickshell/settings/RowsSection.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "../services"

// A section of ChoiceRows; each row is { label, values: () => [...], text: v => string, value: () => current, set: v => void, pick?: bool }.
// Enter or a click opens a filterable list of a row's values; `pick: false` keeps a row cycling and `cycle: false` stops H/L from stepping it, and `activate: () => void` replaces Enter or a click.
// A row's optional `desc` (text) and `keys` (hint) show below the section for the selected or hovered row; `section_keys` follow every row's keys.
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
            if (row.cycle !== false) parts.push("H/L change");
            if (row.activate || row.pick !== false && row.values().length >= root.pick_min) parts.push("Enter list");
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
                onHoveredChanged: {
                    if (row.hovered) root.hovered_row = row.index;
                    else if (root.hovered_row === row.index) root.hovered_row = -1;
                }
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

        // Fixed at two lines each so moving between rows does not resize the pane.
        ColumnLayout {
            visible: root.has_descriptions && !root.picking
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 2

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.alpha(root.st.text_muted, 0.4)
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: description_metrics.height * 2
                text: root.described_row && root.described_row.desc ? root.described_row.desc : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                color: root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)

                FontMetrics {
                    id: description_metrics
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: keys_metrics.height * 2
                text: root.keys_of(root.described_row)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                color: root.st.text_accent
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)

                FontMetrics {
                    id: keys_metrics
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }
            }
        }
    }
}
