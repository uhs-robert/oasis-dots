// home/quickshell/.config/quickshell/settings/sections/BarModulesSection.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../components"
import "../../theme"
import "../../services"
import "../../services/BarLayout.js" as BarLayout
import ".."

SettingsPane {
    id: root

    property int cursor: 0
    property string target: ""

    readonly property var screens: Array.from(Quickshell.screens)
    readonly property var target_screen: root.screens.find(s => s.name === root.target) || null
    readonly property var focused_screen: root.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || root.screens[0] || null
    readonly property var view_screen: root.target_screen || root.focused_screen
    readonly property string monitor_key: root.target_screen ? BarConfig.monitor_key(root.target_screen) : ""
    readonly property bool has_own: root.monitor_key !== "" && !!BarConfig.state.monitors[root.monitor_key]
    readonly property var tracked: root.view_screen ? BarConfig.tracked_rule_for(root.view_screen) : null
    readonly property var view_layout: BarLayout.layout_of(BarLayout.effective(root.tracked, BarConfig.state, root.monitor_key))
    readonly property int top_count: root.target_screen ? (root.has_own ? 3 : 2) : 1
    readonly property bool own_compact: root.has_own && BarConfig.compact_for(BarConfig.state.monitors[root.monitor_key])
    readonly property var entries: {
        const out = [];
        for (const side of BarLayout.sides) {
            const list = Style.bar_lualine && side !== "left" ? BarLayout.section_sorted(root.view_layout[side]) : root.view_layout[side];
            list.forEach(e => out.push({ entry: e, side: side }));
        }
        BarLayout.hidden_entries(BarConfig.rules, BarConfig.state, root.view_layout).forEach(e => out.push({ entry: e, side: "hidden" }));
        return out;
    }
    readonly property int total: root.top_count + root.entries.length

    footer_hint: "j/k move · Enter target list · Space show/hide · J/K reorder · H/L side · a add argument · x remove · l/H target · / find · h/Esc sections · q close"
    search_rows: ["Editing target"].concat(root.target_screen ? ["Own layout"] : [], root.has_own ? ["Compact"] : [], root.entries.map(e => e.entry))
    search_cursor: root.cursor
    implicitHeight: col.implicitHeight

    function target_values() {
        return [""].concat(root.screens.map(s => s.name));
    }

    function target_text(name) {
        const screen = root.screens.find(s => s.name === name);
        if (!screen) return "All monitors";
        const desc = BarConfig.description_for(screen);
        return desc ? screen.name + " · " + desc : screen.name;
    }

    function cycle_target(delta) {
        const values = root.target_values();
        root.target = values[root.wrap_index(values.indexOf(root.target), delta, values.length)];
    }

    function open_target_picker() {
        const values = root.target_values();
        root.show_picker(picker, "Editing target", values.map(v => root.target_text(v)), values.indexOf(root.target), i => root.target = values[i]);
    }

    function toggle_own() {
        if (!root.target_screen) return;
        if (root.has_own) {
            BarConfig.set_state(BarLayout.drop_own(BarConfig.state, root.monitor_key));
            return;
        }
        const eff = BarLayout.effective(root.tracked, BarConfig.state, root.monitor_key);
        if (!eff) return;
        BarConfig.set_state(BarLayout.set_own(BarConfig.state, root.monitor_key, eff, BarConfig.compact_for(eff)));
    }

    function toggle_compact() {
        if (!root.has_own) return;
        BarConfig.set_state(BarLayout.set_compact(BarConfig.state, root.monitor_key, !root.own_compact));
    }

    function add_argument() {
        const item = root.current_module();
        if (!item) return;
        const base = BarConfig.parse_module(item.entry).base;
        const next = BarLayout.next_entry(base, root.entries.map(e => e.entry));
        if (next === "") return;
        const side = item.side === "hidden" ? "right" : item.side;
        const index = item.side === "hidden" ? -1 : root.view_layout[side].indexOf(item.entry) + 1;
        root.edit({ type: "show", entry: next, side: side, index: index });
        root.follow(next);
    }

    function remove_argument() {
        const item = root.current_module();
        if (!item || item.entry.indexOf(":") < 0) return;
        if (BarLayout.tracked_side(BarConfig.rules, item.entry) === "") root.edit({ type: "remove", entry: item.entry });
        else if (item.side !== "hidden") root.edit({ type: "hide", entry: item.entry });
    }

    function edit(op) {
        if (!root.tracked) return;
        BarConfig.set_state(BarLayout.edit(root.tracked, BarConfig.state, root.monitor_key, op));
    }

    function current_module() {
        return root.entries[root.cursor - root.top_count] || null;
    }

    function toggle_module() {
        const item = root.current_module();
        if (!item) return;
        if (item.side !== "hidden") {
            root.edit({ type: "hide", entry: item.entry });
            return;
        }
        const back = BarLayout.restore_side(BarConfig.rules, BarConfig.state, root.monitor_key, item.entry);
        root.edit({ type: "show", entry: item.entry, side: back.side, index: back.index });
    }

    // Keeps the cursor on the module it moved.
    function follow(entry) {
        const at = root.entries.findIndex(e => e.entry === entry);
        if (at >= 0) root.cursor = root.top_count + at;
    }

    function move_module(delta) {
        const item = root.current_module();
        if (!item || item.side === "hidden") return;
        const same = root.entries.filter(e => e.side === item.side).map(e => e.entry);
        const neighbor = same[same.indexOf(item.entry) + delta];
        const sectioned = Style.bar_lualine && item.side !== "left";
        if (!neighbor || (sectioned && BarLayout.lualine_section(neighbor) !== BarLayout.lualine_section(item.entry))) return;
        root.edit({ type: "move", entry: item.entry, with: neighbor });
        root.follow(item.entry);
    }

    function shift_side(delta) {
        const item = root.current_module();
        if (!item || item.side === "hidden") return;
        const to = BarLayout.sides.indexOf(item.side) + delta;
        if (to < 0 || to >= BarLayout.sides.length) return;
        root.edit({ type: "side", entry: item.entry, side: BarLayout.sides[to] });
        root.follow(item.entry);
    }

    function search_select(index) {
        root.cursor = index;
    }

    function jump(delta) {
        root.cursor = delta < 0 ? 0 : root.total - 1;
    }

    onTotalChanged: root.cursor = Math.min(root.cursor, root.total - 1)

    Keys.onPressed: event => {
        if (root.picking || (event.modifiers & Qt.ControlModifier)) return;
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const on_module = root.cursor >= root.top_count;
        if (event.key === Qt.Key_J && !(shift && on_module)) root.cursor = root.wrap_index(root.cursor, 1, root.total);
        else if (event.key === Qt.Key_K && !(shift && on_module)) root.cursor = root.wrap_index(root.cursor, -1, root.total);
        else if (event.key === Qt.Key_J) root.move_module(1);
        else if (event.key === Qt.Key_K) root.move_module(-1);
        else if (on_module && shift && event.key === Qt.Key_H) root.shift_side(-1);
        else if (on_module && shift && event.key === Qt.Key_L) root.shift_side(1);
        else if (root.cursor === 0 && ((shift && event.key === Qt.Key_H) || event.key === Qt.Key_L)) root.cycle_target(event.key === Qt.Key_H ? -1 : 1);
        else if (root.cursor === 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) root.open_target_picker();
        else if (root.cursor === 0 && event.key === Qt.Key_Space) root.cycle_target(1);
        else if (root.target_screen && root.cursor === 1 && (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) root.toggle_own();
        else if (root.has_own && root.cursor === 2 && (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) root.toggle_compact();
        else if (on_module && !shift && event.key === Qt.Key_A) root.add_argument();
        else if (on_module && !shift && event.key === Qt.Key_X) root.remove_argument();
        else if (on_module && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) root.toggle_module();
        else return;
        event.accepted = true;
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 4

        PickerList {
            id: picker
            visible: root.picking
            st: root.st
            onPicked: index => root.finish_picker(index)
            onClosed: root.hide_picker()
        }

        ChoiceRow {
            visible: !root.picking
            selected: root.live && root.cursor === 0
            label: "Editing target"
            value_text: root.target_text(root.target)
            onStepped: {
                root.focus_pane();
                root.cursor = 0;
                root.open_target_picker();
            }
        }

        ChoiceRow {
            visible: !!root.target_screen && !root.picking
            selected: root.live && root.cursor === 1
            label: "Own layout"
            value_text: root.has_own ? "on" : "off"
            onStepped: {
                root.focus_pane();
                root.cursor = 1;
                root.toggle_own();
            }
        }

        ChoiceRow {
            visible: root.has_own && !root.picking
            selected: root.live && root.cursor === 2
            label: "Compact"
            value_text: root.own_compact ? "on" : "off"
            onStepped: {
                root.focus_pane();
                root.cursor = 2;
                root.toggle_compact();
            }
        }

        Text {
            visible: !!root.target_screen && !root.has_own && !root.picking
            Layout.fillWidth: true
            text: "Edits go to the shared layout for every monitor"
            wrapMode: Text.WordWrap
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }

        Repeater {
            model: root.picking ? [] : root.entries

            ColumnLayout {
                id: item
                required property int index
                required property var modelData
                readonly property bool first: item.index === 0 || root.entries[item.index - 1].side !== item.modelData.side

                Layout.fillWidth: true
                spacing: 4

                MenuSection {
                    visible: item.first
                    Layout.topMargin: 6
                    label: root.cap(item.modelData.side)
                }

                MenuRow {
                    id: row
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.px(26)
                    base_radius: 6
                    selected: root.live && root.cursor === root.top_count + item.index

                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 8 + row.inset
                        anchors.right: parent.right
                        anchors.rightMargin: 8 + row.key_space
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        RowLabel {
                            Layout.fillWidth: true
                            label: item.modelData.entry
                            color: row.fg(item.modelData.side === "hidden" ? root.st.text_dim : root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.focus_pane();
                            root.cursor = root.top_count + item.index;
                            root.toggle_module();
                        }
                    }
                }
            }
        }
    }
}
