import QtQuick
import QtQuick.Layouts
import qs.ui.menu
import qs.theme
import qs.features.settings
import qs.features.bar
import qs.features.bar_editor
import qs.features.popups
import "../SettingsScale.js" as SScale

// Layout editing lives in the bar editor; this pane only opens it and holds the Directory module's global switches.
SettingsPane {
    id: root

    property int cursor: 0
    // Row under the pointer, in cursor numbering; -1 when none.
    property int hovered_index: -1

    readonly property var directory_rows: [
        { name: "app_name", label: "Directory: app name" },
        { name: "path", label: "Directory: path" },
        { name: "file_name", label: "Directory: Neovim file name" }
    ]
    // Row 0 is Edit bar; the Directory switches follow.
    readonly property int total: 1 + root.directory_rows.length
    readonly property var labels: ["Edit bar"].concat(root.directory_rows.map(r => r.label))
    // Values start past the longest setting label, as in RowsSection, rather than at the far edge of a wide pane.
    readonly property real value_column: {
        // Read so the width is measured again once the font has loaded; advanceWidth alone does not notify.
        const font = label_metrics.font;
        const need = Math.max(...root.labels.map(l => label_metrics.advanceWidth(l)));
        return Math.min(Math.ceil(need) + Style.px(40), Math.round(root.width * 0.6));
    }
    readonly property int described_index: root.hovered_index >= 0 && root.hovered_index < root.total ? root.hovered_index : root.cursor
    readonly property var directory_notes: ({
            app_name: "Show the focused window's app name in the Directory module and the NeoVim statusline. Applies to every monitor and style.",
            path: "Show a terminal's working directory. Off keeps only a Neovim file name, if that is on.",
            file_name: "Show the file open in Neovim, not just its directory."
        })

    FontMetrics {
        id: label_metrics
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size + SScale.bump_of(root)
    }

    footer_hint: "j/k move · Enter open/toggle · / find · h/Esc sections · q close"
    search_rows: root.labels
    search_cursor: root.cursor
    described: true
    description: root.describe(root.described_index)
    description_keys: root.described_index === 0 ? "Enter open" : "Enter toggle"
    implicitHeight: col.implicitHeight

    function describe(index) {
        if (index === 0) return "Edit the bars live on screen: move, hide, add and re-place modules, give a monitor its own layout, make one module or the whole bar compact, move the bar to another edge. Esc/q leaves.";
        return root.directory_notes[root.directory_rows[index - 1].name];
    }

    // The editor takes the keyboard in the tick it opens, so Settings has to be gone first. Settings does not return afterwards.
    function open_editor() {
        Popups.after_close(() => BarEditor.open(""));
    }

    function toggle_directory(index) {
        const name = root.directory_rows[index - 1].name;
        BarSettings.set_directory_switch(name, !BarSettings.directory_switches[name]);
    }

    function activate(index, delta) {
        if (index === 0) root.open_editor();
        else root.toggle_directory(index);
    }

    function hover(index, on) {
        if (on) root.hovered_index = index;
        else if (root.hovered_index === index) root.hovered_index = -1;
    }

    function search_select(index) {
        root.cursor = index;
    }

    function jump(delta) {
        root.cursor = delta < 0 ? 0 : root.total - 1;
    }

    Keys.onPressed: event => {
        if (root.picking || (event.modifiers & Qt.ControlModifier)) return;
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        // A row steps either way through its values; plain h stays free for going back to the sidebar.
        const toggles = event.key === Qt.Key_L || (shift && event.key === Qt.Key_H) || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space;
        if (event.key === Qt.Key_J) root.cursor = root.wrap_index(root.cursor, 1, root.total);
        else if (event.key === Qt.Key_K) root.cursor = root.wrap_index(root.cursor, -1, root.total);
        else if (toggles) root.activate(root.cursor, 1);
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4

        ChoiceRow {
            value_x: root.value_column
            selected: root.live && root.cursor === 0
            label: "Edit bar"
            value_text: "Enter"
            onHoveredChanged: root.hover(0, hovered)
            onStepped: {
                root.focus_pane();
                root.cursor = 0;
                root.open_editor();
            }
        }

        Repeater {
            model: root.directory_rows

            ChoiceRow {
                required property int index
                required property var modelData
                value_x: root.value_column
                selected: root.live && root.cursor === 1 + index
                label: modelData.label
                value_text: BarSettings.directory_switches[modelData.name] ? "on" : "off"
                onHoveredChanged: root.hover(1 + index, hovered)
                onStepped: {
                    root.focus_pane();
                    root.cursor = 1 + index;
                    root.toggle_directory(root.cursor);
                }
            }
        }
    }
}
