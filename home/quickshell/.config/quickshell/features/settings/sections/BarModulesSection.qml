import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.ui.menu
import qs.theme
import "../../bar/BarLayout.js" as BarLayout
import qs.features.settings
import qs.features.bar
import qs.features.audio

SettingsPane {
    id: root

    property int cursor: 0
    property string target: ""
    // The y/n prompt before forgetting a saved position: { question, run }, or null.
    property var pending: null
    // Row under the pointer, in cursor numbering; -1 when none.
    property int hovered_index: -1

    readonly property var screens: Array.from(Quickshell.screens)
    readonly property var target_screen: root.screens.find(s => s.name === root.target) || null
    readonly property var focused_screen: root.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || root.screens[0] || null
    readonly property var view_screen: root.target_screen || root.focused_screen
    readonly property string monitor_key: root.target_screen ? BarSettings.monitor_key(root.target_screen) : ""
    readonly property bool has_own: root.monitor_key !== "" && !!BarSettings.state.monitors[root.monitor_key]
    readonly property var tracked: root.view_screen ? BarSettings.tracked_rule_for(root.view_screen) : null
    readonly property var view_layout: BarLayout.layout_of(BarLayout.effective(root.tracked, BarSettings.state, root.monitor_key))
    readonly property int top_count: root.target_screen ? (root.has_own ? 4 : 3) : 2
    readonly property bool own_compact: root.has_own && BarSettings.compact_for(BarSettings.state.monitors[root.monitor_key])
    // Saved per monitor apart from the own layout, so the row shows and keeps its value with Own layout off.
    readonly property string bar_position: BarLayout.position_of(BarLayout.effective(root.tracked, BarSettings.state, root.monitor_key))
    // All monitors has no monitor key, so it reads the shared value, else the focused monitor's rule.
    readonly property string position_source: BarLayout.position_source(root.tracked, BarSettings.state, root.monitor_key)
    readonly property bool position_set_here: root.position_source === (root.target_screen ? "monitor" : "global")
    readonly property var entries: {
        const out = [];
        for (const side of BarLayout.sides) {
            const list = Style.bar_lualine && side !== "left" ? BarLayout.section_sorted(root.view_layout[side]) : root.view_layout[side];
            list.forEach(e => out.push({ entry: e, side: side }));
        }
        BarLayout.hidden_entries(BarSettings.rules, BarSettings.state, root.view_layout).forEach(e => out.push({ entry: e, side: "hidden" }));
        return out;
    }
    readonly property int total: root.top_count + root.entries.length
    readonly property int described_index: root.hovered_index >= 0 && root.hovered_index < root.total ? root.hovered_index : root.cursor
    readonly property var module_notes: ({
            start: "Start button that opens the Start menu.",
            workspaces: "Workspace buttons for each monitor.",
            clock: "Time and date; opens the calendar popup.",
            tray: "Tray icons of running apps.",
            volume: "Volume level; opens the volume popup.",
            battery: "Battery level and charging state.",
            bluetooth: "Bluetooth status; opens its popup.",
            system: "System readout, starting on CPU.",
            "system:cpu": "CPU usage readout.",
            "system:memory": "Memory usage readout.",
            "system:temperature": "Temperature readout.",
            network: "Network status; opens the network popup.",
            weather: "Current weather; opens the forecast popup.",
            keeptabs: "AI agent sessions busy, done or waiting. Hidden while none run.",
            cmdstatus: "Status pills from your own commands in custom/command-status.json. Hidden without any.",
            updates: "Count of pending package updates.",
            voxtype: "Dictation status.",
            recording: "A chip shown while the screen is recording.",
            notifications: "Notification center and Do Not Disturb.",
            media: "Now playing; opens the media popup."
        })

    footer_hint: root.pending ? "y forget · n keep · q close" : "j/k move · Enter target list · Space show/hide · J/K reorder · H/L side · a add argument · x remove · l/H target · / find · h/Esc sections · q close"
    search_rows: ["Editing target", "Position"].concat(root.target_screen ? ["Own layout"] : [], root.has_own ? ["Compact"] : [], root.entries.map(e => e.entry))
    search_cursor: root.cursor
    described: true
    description: root.describe(root.described_index)
    description_keys: root.pending ? "y forget · n keep" : root.keys_for(root.described_index)
    implicitHeight: col.implicitHeight + root.description_space

    function describe(index) {
        if (index === 0) return "The monitor whose bar you edit. All monitors edits the layout they share.";
        if (index === 1 && root.target_screen) return "The screen edge this monitor's bar sits on, with or without its own layout. Until set here it follows the global position, else bars.json.";
        if (index === 1) return "The screen edge every bar sits on, unless a monitor sets its own. Top or bottom. Popups and the submap tab rise from a bottom bar.";
        if (index === 2 && root.target_screen) return "On gives this monitor its own copy of the layout. Off goes back to the shared one.";
        if (index === 3 && root.has_own) return "A tighter bar that hides the system modules on this monitor.";
        const item = root.entries[index - root.top_count];
        if (!item) return "";
        const note = root.module_notes[item.entry] || root.module_notes[BarSettings.parse_module(item.entry).base] || "";
        return note + (item.side === "hidden" ? " Hidden." : "");
    }

    function keys_for(index) {
        if (index === 0) return "H/L change · Enter list";
        if (index === 1 && root.position_set_here) return "Enter next · Shift+H back · x forget";
        if (index === 1) return "Enter next · Shift+H back";
        if (index < root.top_count) return "Enter toggle";
        const item = root.entries[index - root.top_count];
        if (!item) return "";
        const base = BarSettings.parse_module(item.entry).base;
        const keys = item.side === "hidden" ? ["Enter show"] : ["Enter hide", "J/K reorder", "H/L side"];
        if (BarLayout.module_args[base]) keys.push("a add argument");
        if (item.entry.indexOf(":") >= 0) keys.push("x remove");
        return keys.join(" · ");
    }

    function hover(index, on) {
        if (on) root.hovered_index = index;
        else if (root.hovered_index === index) root.hovered_index = -1;
    }

    function target_values() {
        return [""].concat(root.screens.map(s => s.name));
    }

    function target_text(name) {
        const screen = root.screens.find(s => s.name === name);
        if (!screen) return "All monitors";
        const desc = BarSettings.description_for(screen);
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
            BarSettings.set_state(BarLayout.drop_own(BarSettings.state, root.monitor_key));
            return;
        }
        const eff = BarLayout.effective(root.tracked, BarSettings.state, root.monitor_key);
        if (!eff) return;
        BarSettings.set_state(BarLayout.set_own(BarSettings.state, root.monitor_key, eff, BarSettings.compact_for(eff)));
    }

    function toggle_compact() {
        if (!root.has_own) return;
        BarSettings.set_state(BarLayout.set_compact(BarSettings.state, root.monitor_key, !root.own_compact));
    }

    // Top and bottom in turn (BarLayout.settings_positions).
    function step_position(delta) {
        root.pending = null;
        const next = BarLayout.step_position(root.bar_position, delta);
        if (root.target_screen) BarSettings.set_state(BarLayout.set_position(BarSettings.state, root.monitor_key, next));
        else BarSettings.set_state(BarLayout.set_shared_position(BarSettings.state, next));
    }

    function cleared_position_state() {
        return root.target_screen ? BarLayout.clear_position(BarSettings.state, root.monitor_key) : BarLayout.clear_shared_position(BarSettings.state);
    }

    function ask_clear_position() {
        if (!root.position_set_here) return;
        const after = root.cleared_position_state();
        const edge = BarLayout.position_of(BarLayout.effective(root.tracked, after, root.monitor_key));
        const fallback = { global: "the global position", "bars.json": "bars.json", default: "the default" }[BarLayout.position_source(root.tracked, after, root.monitor_key)];
        const question = root.target_screen ? "Forget " + root.target + "'s bar position? It will follow " + fallback + " (" + edge + "). y/n" : "Forget the global bar position? Bars follow " + fallback + " (" + edge + "). y/n";
        root.pending = { question: question, run: () => BarSettings.set_state(root.cleared_position_state()) };
        ThemeAudio.play("confirm");
    }

    function position_text() {
        const note = { global: " (global)", "bars.json": " (bars.json)", default: " (default)" }[root.position_source];
        return root.bar_position + (root.position_set_here ? "" : note);
    }

    function add_argument() {
        const item = root.current_module();
        if (!item) return;
        const base = BarSettings.parse_module(item.entry).base;
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
        if (BarLayout.tracked_side(BarSettings.rules, item.entry) === "") root.edit({ type: "remove", entry: item.entry });
        else if (item.side !== "hidden") root.edit({ type: "hide", entry: item.entry });
    }

    function edit(op) {
        if (!root.tracked) return;
        BarSettings.set_state(BarLayout.edit(root.tracked, BarSettings.state, root.monitor_key, op));
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
        const back = BarLayout.restore_side(BarSettings.rules, BarSettings.state, root.monitor_key, item.entry);
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
    // A pointer click can move off the row or change the target while the prompt is up; the question would then name the wrong thing.
    onCursorChanged: root.pending = null
    onTargetChanged: root.pending = null

    Keys.onPressed: event => {
        if (root.picking || (event.modifiers & Qt.ControlModifier)) return;
        // The prompt holds every key but q, which still closes Settings, as in the Sessions, Network and Bluetooth prompts.
        if (root.pending) {
            if (event.key === Qt.Key_Q) {
                root.pending = null;
                return;
            }
            if (event.key === Qt.Key_Y) {
                const run = root.pending.run;
                root.pending = null;
                run();
            } else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape) {
                root.pending = null;
                ThemeAudio.play("cancel");
            }
            event.accepted = true;
            return;
        }
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const on_module = root.cursor >= root.top_count;
        // A row steps either way through its values; plain h stays free for going back to the sidebar.
        const toggles = event.key === Qt.Key_L || (shift && event.key === Qt.Key_H) || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space;
        if (event.key === Qt.Key_J && !(shift && on_module)) root.cursor = root.wrap_index(root.cursor, 1, root.total);
        else if (event.key === Qt.Key_K && !(shift && on_module)) root.cursor = root.wrap_index(root.cursor, -1, root.total);
        else if (event.key === Qt.Key_J) root.move_module(1);
        else if (event.key === Qt.Key_K) root.move_module(-1);
        else if (on_module && shift && event.key === Qt.Key_H) root.shift_side(-1);
        else if (on_module && shift && event.key === Qt.Key_L) root.shift_side(1);
        else if (root.cursor === 0 && ((shift && event.key === Qt.Key_H) || event.key === Qt.Key_L)) root.cycle_target(event.key === Qt.Key_H ? -1 : 1);
        else if (root.cursor === 0 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) root.open_target_picker();
        else if (root.cursor === 0 && event.key === Qt.Key_Space) root.cycle_target(1);
        else if (root.cursor === 1 && toggles) root.step_position(shift && event.key === Qt.Key_H ? -1 : 1);
        else if (root.cursor === 1 && !shift && event.key === Qt.Key_X) root.ask_clear_position();
        else if (root.target_screen && root.cursor === 2 && toggles) root.toggle_own();
        else if (root.has_own && root.cursor === 3 && toggles) root.toggle_compact();
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
            onHoveredChanged: root.hover(0, hovered)
            onStepped: {
                root.focus_pane();
                root.cursor = 0;
                root.open_target_picker();
            }
        }

        ChoiceRow {
            visible: !root.picking
            selected: root.live && root.cursor === 1
            label: "Position"
            value_text: root.position_text()
            onHoveredChanged: root.hover(1, hovered)
            onStepped: delta => {
                root.focus_pane();
                root.cursor = 1;
                root.step_position(delta);
            }
        }

        Text {
            visible: !!root.pending && !root.picking
            Layout.fillWidth: true
            text: root.pending ? root.pending.question : ""
            wrapMode: Text.WordWrap
            color: Style.pal.error
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }

        ChoiceRow {
            visible: !!root.target_screen && !root.picking
            selected: root.live && root.cursor === 2
            label: "Own layout"
            value_text: root.has_own ? "on" : "off"
            onHoveredChanged: root.hover(2, hovered)
            onStepped: {
                root.focus_pane();
                root.cursor = 2;
                root.toggle_own();
            }
        }

        ChoiceRow {
            visible: root.has_own && !root.picking
            selected: root.live && root.cursor === 3
            label: "Compact"
            value_text: root.own_compact ? "on" : "off"
            onHoveredChanged: root.hover(3, hovered)
            onStepped: {
                root.focus_pane();
                root.cursor = 3;
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
                        hoverEnabled: true
                        onContainsMouseChanged: root.hover(root.top_count + item.index, containsMouse)
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
