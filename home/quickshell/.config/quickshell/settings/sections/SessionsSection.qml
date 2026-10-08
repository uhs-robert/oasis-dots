// home/quickshell/.config/quickshell/settings/sections/SessionsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import "../Choices.js" as Choices
import ".."

// Three levels in one pane: the session list, one session's windows, and one window's fields. h and Esc step up a level before leaving the pane.
RowsSection {
    id: root

    property string view: "list"
    property string session_name: ""
    property int window_index: -1
    // The cursor of each level above this one, restored when stepping back up.
    property var parents: []
    // "rename", "command" or "special" while the field is open.
    property string edit_key: ""
    property bool edit_invalid: false
    // The destructive row waiting for a second Enter, as "delete:<name>" or "remove:<index>".
    property string armed: ""

    readonly property var session: SessionStore.find(root.session_name)
    readonly property var entry: root.session && root.window_index >= 0 ? root.session.windows[root.window_index] || null : null
    readonly property var delay_steps: [0, 250, 500, 1000, 2000, 5000]
    readonly property string hint: SessionStore.load_error !== "" ? "sessions.json cannot be read (" + SessionStore.load_error + "); fix it with Edit sessions.json." : SessionStore.notice
    readonly property string breadcrumb: root.view === "list" ? "" : root.session_name + (root.view === "window" && root.entry ? " > " + root.window_label(root.entry) : "")

    section_keys: "n save layout · e edit file"
    rows: root.build_rows()
    description_keys: root.edit_key !== "" ? "Enter save · Ctrl+u clear · Esc cancel" : root.keys_of(root.described_row)
    footer_hint: root.edit_key !== "" ? "Enter save · Ctrl+u clear · Esc cancel" : root.armed !== "" ? "Enter confirm · any other key cancels" : root.view === "list" ? "j/k move · Enter open · n save layout · e edit file · h/Esc sections · q close" : "j/k move · H/L change · Enter edit · h/Esc back · q close"
    onRowsChanged: root.cursor = Math.max(0, Math.min(root.cursor, root.rows.length - 1))
    onSessionChanged: Qt.callLater(root.check_view)
    onEntryChanged: Qt.callLater(root.check_view)

    function range(count) {
        const out = [];
        for (let i = 1; i <= count; i++) out.push(i);
        return out;
    }

    function window_label(w) {
        return w.class || w.title || String(w.cmd || "").split(" ")[0] || "window";
    }

    function placement_text(w) {
        return typeof w.special === "string" ? "special " + w.special : "monitor " + (w.monitor || 1) + " · ws " + (w.ws || 1);
    }

    function action_row(label, desc, keys, run, value_text) {
        return { label: label, desc: desc, keys: keys, values: () => [], text: () => value_text, value: () => "", set: v => {}, cycle: false, activate: run };
    }

    function text_row(label, desc, kind, current) {
        return root.action_row(label, desc, "Enter edit", () => root.start_edit(kind), current);
    }

    function choice_row(label, desc, values, text, value, set) {
        return { label: label, desc: desc, values: () => values, text: text, value: value, set: set, pick: false };
    }

    // The first Enter arms the row and the second runs it.
    function confirm_row(label, desc, key, run) {
        const row = root.action_row(label, desc, "Enter twice to confirm", () => {
            if (root.armed === key) {
                root.armed = "";
                run();
            } else {
                root.armed = key;
            }
        }, "");
        row.text = () => root.armed === key ? "Enter to confirm" : "Enter";
        return row;
    }

    function build_rows() {
        if (root.view === "window") return root.window_rows();
        if (root.view === "session") return root.session_rows();
        return root.list_rows();
    }

    function list_rows() {
        const rows = [root.action_row("Save current layout", "Opens the overview with every window marked. Unmark what to leave out, then name the session.", "Enter save layout", () => root.start_save(""), "Enter")];
        for (const s of SessionStore.sessions) {
            const count = s.windows.length + (s.windows.length === 1 ? " window" : " windows");
            const desc = s.read_only ? "A Lua session from custom/sessions.lua. It is read-only here; edit that file to change it." : "A saved session. Enter opens its windows to edit them.";
            rows.push(root.action_row(s.name, desc, "Enter open", () => root.open_session(s.name), s.read_only ? "Lua · " + count : count));
        }
        rows.push(root.action_row("Edit sessions.json", "Opens the saved sessions file in your editor. Changes show up here when you save it.", "Enter edit file", SessionStore.open_in_editor, "Enter"));
        return rows;
    }

    function session_rows() {
        const s = root.session;
        if (!s) return [];
        const rows = [];
        if (!s.read_only) {
            rows.push(root.text_row("Name", "The name the picker lists. Enter renames the session.", "rename", s.name));
            rows.push(root.action_row("Update from current windows", "Opens the overview with every window marked; saving replaces this session's windows with the marked ones.", "Enter update", () => root.start_save(s.name), "Enter"));
            rows.push(root.confirm_row("Delete session", "Removes " + s.name + " from sessions.json.", "delete:" + s.name, () => {
                SessionStore.remove(s.name);
                root.go_up();
            }));
        }
        s.windows.forEach((w, i) => {
            const guessed = w.guessed === true;
            const lead = s.read_only ? "Defined in custom/sessions.lua. " : guessed ? "Guessed from /proc, check it. " : "";
            const row = root.action_row(root.window_label(w), lead + String(w.cmd || ""), s.read_only ? "" : "Enter edit window", () => root.open_window(i), root.placement_text(w) + (guessed ? " · guessed" : ""));
            if (s.read_only) {
                row.activate = undefined;
                row.keys = "Read-only";
            }
            rows.push(row);
        });
        return rows;
    }

    function window_rows() {
        const s = root.session;
        const w = root.entry;
        if (!s || !w || s.read_only) return [];
        const name = s.name;
        const index = root.window_index;
        const special = typeof w.special === "string";
        const patch = fields => SessionStore.update_window(name, index, fields);
        const rows = [root.choice_row("Placement", "Whether the window opens on a numbered workspace of a monitor or on a special workspace.", ["workspace", "special"], v => v === "special" ? "Special workspace" : "Numbered workspace", () => special ? "special" : "workspace",
            v => patch(v === "special" ? { special: w.special || "scratchpad", monitor: null, ws: null } : { special: null, monitor: w.monitor || 1, ws: w.ws || 1 }))];
        if (special) {
            rows.push(root.text_row("Special workspace", "Name of the special workspace, without the special: prefix.", "special", w.special));
        } else {
            rows.push(root.choice_row("Monitor", "Which monitor, numbered in the order of the Hyprland monitor config.", root.range(Math.max(Displays.enabled_count, w.monitor || 1, 1)), v => String(v), () => w.monitor || 1, v => patch({ monitor: v })));
            rows.push(root.choice_row("Workspace", "Which of that monitor's workspaces, 1 to " + SessionStore.ws_per_monitor + ".", root.range(Math.max(SessionStore.ws_per_monitor, w.ws || 1)), v => String(v), () => w.ws || 1, v => patch({ ws: v })));
        }
        const cmd_desc = w.guessed === true ? "Read from /proc when saved, so it may be wrong: a single-instance terminal reports its server process. Edit it to the command that opens this window." : "The shell command that opens the window. Enter edits it.";
        rows.push(root.text_row("Command", cmd_desc, "command", String(w.cmd || "") + (w.guessed === true ? " (guessed)" : "")));
        rows.push(root.choice_row("Delay", "How long to wait before launching this window.", Choices.with_current(root.delay_steps, w.delay || 0), v => v === 0 ? "None" : v + " ms", () => w.delay || 0, v => patch({ delay: v === 0 ? null : v })));
        const has_geometry = w.size !== undefined || w.pos !== undefined;
        rows.push(root.choice_row("Keep size and position", "Off drops the saved size and position, so the layout places the window. To capture them again, use Update from current windows.", ["on", "off"], v => v, () => has_geometry ? "on" : "off",
            v => v === "off" ? patch({ size: null, pos: null }) : SessionStore.say("Use Update from current windows to capture size and position again")));
        rows.push(root.confirm_row("Remove window", "Removes this window from the session.", "remove:" + index, () => {
            SessionStore.remove_window(name, index);
            root.go_up();
        }));
        return rows;
    }

    function enter_level(next_view) {
        root.parents = root.parents.concat([root.cursor]);
        root.view = next_view;
        root.armed = "";
        root.cursor = 0;
    }

    function open_session(name) {
        root.session_name = name;
        root.enter_level("session");
    }

    function open_window(index) {
        root.window_index = index;
        root.enter_level("window");
    }

    function go_up() {
        if (root.view === "list") return;
        const last = root.parents.length > 0 ? root.parents[root.parents.length - 1] : 0;
        root.parents = root.parents.slice(0, -1);
        if (root.view === "window") {
            root.view = "session";
            root.window_index = -1;
        } else {
            root.view = "list";
            root.session_name = "";
        }
        root.armed = "";
        root.cursor = last;
    }

    // Falls back to the list when the session or window was removed by an edit outside this pane.
    function check_view() {
        if (root.view !== "list" && !root.session) {
            root.view = "list";
            root.session_name = "";
            root.window_index = -1;
            root.parents = [];
            root.cursor = 0;
        } else if (root.view === "window" && !root.entry) {
            root.go_up();
        }
    }

    function apply_requested() {
        const name = SettingsNav.requested_session;
        if (name === "") return;
        SettingsNav.requested_session = "";
        if (!SessionStore.find(name)) return;
        root.view = "list";
        root.window_index = -1;
        root.parents = [];
        root.cursor = 1 + SessionStore.names.indexOf(name);
        root.open_session(name);
    }

    function start_save(target) {
        SessionStore.request_save(target);
    }

    function start_edit(kind) {
        const current = kind === "rename" ? root.session_name : kind === "command" ? root.entry.cmd : root.entry.special;
        root.edit_key = kind;
        root.edit_invalid = false;
        input.text = String(current || "");
        input.forceActiveFocus();
        input.selectAll();
    }

    function end_edit() {
        // The section is a focus scope: unless the field gives up its scoped focus, forceActiveFocus hands it straight back to the hidden field and keys go nowhere.
        input.focus = false;
        root.edit_key = "";
        root.forceActiveFocus();
    }

    function commit_edit() {
        const text = input.text.trim();
        const kind = root.edit_key;
        if (kind === "rename") {
            const old_name = root.session_name;
            const problem = SessionStore.name_problem(text, old_name);
            if (problem !== "") {
                SessionStore.say(problem);
                root.edit_invalid = true;
                return;
            }
            // The session is looked up by name, so the view follows the new name before the file does.
            root.session_name = text;
            if (!SessionStore.rename(old_name, text)) root.session_name = old_name;
        } else {
            if (text === "") {
                root.edit_invalid = true;
                return;
            }
            const fields = kind === "command" ? { cmd: text, guessed: null } : { special: text };
            SessionStore.update_window(root.session_name, root.window_index, fields);
        }
        root.end_edit();
    }

    onFirst_key: event => {
        if (root.edit_key !== "") return;
        const key = event.key;
        const confirm = key === Qt.Key_Return || key === Qt.Key_Enter;
        const back = key === Qt.Key_Escape || (key === Qt.Key_H && !(event.modifiers & Qt.ShiftModifier));
        if (root.armed !== "" && !confirm) {
            root.armed = "";
            if (back) {
                event.accepted = true;
                return;
            }
        }
        if (root.view !== "list" && back) {
            root.go_up();
            event.accepted = true;
            return;
        }
        const row = root.rows[root.cursor];
        if (row && row.activate && (key === Qt.Key_L || key === Qt.Key_Space)) {
            row.activate();
            event.accepted = true;
        }
    }

    onExtra_key: event => {
        if (event.key === Qt.Key_N) root.start_save("");
        else if (event.key === Qt.Key_E) SessionStore.open_in_editor();
        else return;
        event.accepted = true;
    }

    Connections {
        target: SettingsNav
        function onRequested_sessionChanged() {
            if (SettingsNav.requested_session !== "") root.apply_requested();
        }
    }

    Component.onCompleted: {
        Displays.refresh();
        SessionStore.refresh();
        root.apply_requested();
    }

    Text {
        visible: root.breadcrumb !== ""
        Layout.fillWidth: true
        text: root.breadcrumb
        elide: Text.ElideRight
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    Text {
        visible: root.hint !== ""
        Layout.fillWidth: true
        text: root.hint
        wrapMode: Text.WordWrap
        color: root.st.text_accent
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    footer: ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Rectangle {
            visible: root.edit_key !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: Style.px(28)
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: root.edit_invalid ? root.st.text_primary : root.st.text_accent

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                maximumLength: root.edit_key === "command" ? 512 : 64
                clip: true
                color: root.st.text_fg
                selectionColor: root.st.selection_bg
                selectedTextColor: root.st.selection_inverse ? root.st.selection_fg : root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
                onTextEdited: root.edit_invalid = false
                onActiveFocusChanged: if (!input.activeFocus && root.edit_key !== "") root.edit_key = ""

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) root.end_edit();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit_edit();
                    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) input.text = "";
                    else return;
                    event.accepted = true;
                }
            }
        }
    }
}
