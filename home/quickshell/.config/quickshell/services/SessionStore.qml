// home/quickshell/.config/quickshell/services/SessionStore.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "SessionJson.js" as SessionJson

// Saved sessions in sessions.json under the Hyprland state dir, plus the Lua sessions listed read-only.
// The launcher re-reads the file whenever its picker opens, so a write is all it takes to apply a change.
Singleton {
    id: root

    readonly property string path: Paths.hypr_state_dir + "/sessions.json"
    readonly property string runtime_dir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string state_write: Quickshell.env("HOME") + "/.config/hypr/scripts/state-write"

    // The file as last read or written; fields this UI does not know are kept when saving.
    property var document: SessionJson.empty_document()
    // Set while the file cannot be parsed, which blocks writes so a hand edit is not overwritten.
    property string load_error: ""
    property var lua_sessions: ({})
    property int ws_per_monitor: 5
    // Config.app.editor as Hyprland resolved it, so "Machine default" in Settings opens the machine profile's editor.
    property string machine_editor: ""
    property string notice: ""
    // The newest content waiting for the writer; only the latest matters.
    property string queued_content: ""
    // Sessions announced as saved once the write carrying them succeeds.
    property var queued_names: []
    property var writing_names: []

    readonly property var sessions: SessionJson.merge(root.document, root.lua_sessions)
    readonly property var names: root.sessions.map(s => s.name)

    // A saved session's write has finished; the new or changed one is named.
    signal saved(string name)
    signal failed(string message)
    // Settings asks the overview to start save mode; `target` is the session to replace, or empty for a new one.
    signal save_requested(string target)

    function find(name) {
        return root.sessions.find(s => s.name === name) || null;
    }

    function default_name() {
        return SessionJson.default_name(root.names);
    }

    function request_save(target) {
        root.save_requested(target);
    }

    function say(text) {
        root.notice = text;
        notice_timer.restart();
    }

    function fail(message) {
        root.say(message);
        Quickshell.execDetached(["notify-send", "-u", "critical", "Sessions", message]);
        root.failed(message);
    }

    // Empty when `name` is usable for a saved session; `except` is the session being renamed.
    function name_problem(name, except) {
        if (name.trim() === "") return "Name cannot be empty";
        // Assigning it on a plain object sets the prototype instead of adding a session.
        if (name.trim() === "__proto__") return "That name is reserved";
        const saved_names = Object.keys(root.document.sessions);
        if (name.trim() !== except && saved_names.indexOf(name.trim()) >= 0) return "A saved session is already called " + name.trim();
        return "";
    }

    function refresh() {
        if (!lua_proc.running) lua_proc.running = true;
    }

    // `saved_name`, when given, is announced through `saved` after the write lands.
    function commit(next, saved_name) {
        if (root.load_error !== "") {
            root.fail("sessions.json cannot be read (" + root.load_error + "); fix it before saving");
            return false;
        }
        root.document = next;
        root.queued_content = SessionJson.encode(next);
        if (saved_name) root.queued_names = root.queued_names.concat([saved_name]);
        root.flush();
        return true;
    }

    function flush() {
        if (write_proc.running || root.queued_content === "") return;
        write_proc.command = [root.state_write, root.path, root.queued_content];
        root.queued_content = "";
        root.writing_names = root.queued_names;
        root.queued_names = [];
        write_proc.running = true;
    }

    function save_new(name, windows) {
        const problem = root.name_problem(name, "");
        if (problem !== "") {
            root.fail(problem);
            return false;
        }
        return root.commit(SessionJson.set_session(root.document, name.trim(), windows), name.trim());
    }

    // Replaces the windows of `name` and renames it to `new_name` in one write, so a failed capture leaves both untouched.
    function replace_session(name, new_name, windows) {
        const problem = root.name_problem(new_name, name);
        if (problem !== "") {
            root.fail(problem);
            return false;
        }
        const renamed = new_name.trim() === name ? root.document : SessionJson.rename_session(root.document, name, new_name.trim());
        return root.commit(SessionJson.set_session(renamed, new_name.trim(), windows), new_name.trim());
    }

    function rename(name, new_name) {
        const problem = root.name_problem(new_name, name);
        if (problem !== "") {
            root.fail(problem);
            return false;
        }
        if (new_name.trim() === name) return true;
        return root.commit(SessionJson.rename_session(root.document, name, new_name.trim()));
    }

    function remove(name) {
        return root.commit(SessionJson.remove_session(root.document, name));
    }

    // A null field value removes the field.
    function update_window(name, index, fields) {
        return root.commit(SessionJson.patch_window(root.document, name, index, fields));
    }

    function remove_window(name, index) {
        return root.commit(SessionJson.drop_window(root.document, name, index));
    }

    // Captures the windows at `addresses` (Quickshell's, without 0x) and saves them as a new session called `name`,
    // or, when `replace` is not empty, over that session's windows, renaming it to `name`. Emits saved or failed.
    function save_capture(addresses, name, replace) {
        if (capture_proc.running) {
            root.fail("A save is already running");
            return;
        }
        if (!addresses.every(a => /^[0-9a-fA-F]+$/.test(a))) {
            root.fail("Not a window address");
            return;
        }
        const out = root.runtime_dir + "/qs-session-capture.json";
        const list = addresses.map(a => "'0x" + a + "'").join(", ");
        capture_proc.name = name;
        capture_proc.replace = replace;
        capture_proc.command = ["sh", "-c", "f=$1; rm -f \"$f\"; hyprctl eval \"$2\" >/dev/null 2>&1; cat \"$f\" 2>/dev/null; rm -f \"$f\"",
            "sh", out, "require('extensions.auto_launcher.capture').draft({" + list + "}, '" + out.replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "')"];
        capture_proc.running = true;
    }

    // Opens sessions.json in the configured editor inside the configured terminal, creating an empty file first.
    function open_in_editor() {
        const editor = DefaultApps.app_value("editor") || root.machine_editor || Quickshell.env("EDITOR") || "nvim";
        Quickshell.execDetached(["sh", "-c", "[ -e \"$2\" ] || \"$3\" \"$2\" \"$4\" || exit 1; t=\"${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e \"$1\" \"$2\"",
            "sh", editor, root.path, root.state_write, SessionJson.encode(SessionJson.empty_document())]);
    }

    Timer {
        id: notice_timer
        interval: 6000
        onTriggered: root.notice = ""
    }

    Process {
        id: write_proc
        stderr: StdioCollector {
            id: write_errors
        }
        onExited: code => {
            const written = root.writing_names;
            root.writing_names = [];
            if (code !== 0) {
                const detail = write_errors.text.trim();
                root.queued_content = "";
                root.queued_names = [];
                root.fail("Could not save sessions.json" + (detail !== "" ? ": " + detail : ""));
                sessions_file.reload();
            } else {
                for (const name of written) root.saved(name);
                root.flush();
            }
        }
    }

    Process {
        id: capture_proc
        property string name: ""
        property string replace: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let draft = null;
                try {
                    draft = JSON.parse(text);
                } catch (e) {
                    draft = null;
                }
                const windows = draft && Array.isArray(draft.windows) ? draft.windows : [];
                if (windows.length === 0) {
                    root.fail("None of the marked windows could be captured");
                    return;
                }
                if (capture_proc.replace !== "") root.replace_session(capture_proc.replace, capture_proc.name, windows);
                else root.save_new(capture_proc.name, windows);
            }
        }
    }

    // Hyprland owns the Lua sessions and its workspace count, and hyprctl eval prints nothing back, so both go through files.
    // The first line is workspaces per monitor, the second the machine editor, the rest the export.
    Process {
        id: lua_proc
        command: ["sh", "-c", "d=\"${XDG_RUNTIME_DIR:-/tmp}\"; e=\"$d/qs-sessions-export.json\"; w=\"$d/qs-sessions-ws.txt\"; rm -f \"$e\" \"$w\"; hyprctl eval \"require('extensions.auto_launcher.sessions').export('$e')\" >/dev/null 2>&1; hyprctl eval \"local f = io.open('$w', 'w'); local c = require('config'); f:write(tostring(c.ws_per_monitor) .. '\\n' .. tostring(c.app.editor or '')); f:close()\" >/dev/null 2>&1; cat \"$w\" 2>/dev/null; echo; cat \"$e\" 2>/dev/null; rm -f \"$e\" \"$w\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const per_monitor = parseInt(lines[0]);
                if (per_monitor > 0) root.ws_per_monitor = per_monitor;
                root.machine_editor = (lines[1] || "").trim();
                try {
                    const data = JSON.parse(lines.slice(2).join("\n"));
                    root.lua_sessions = data && typeof data.sessions === "object" && data.sessions ? data.sessions : {};
                } catch (e) {
                    root.lua_sessions = {};
                }
            }
        }
    }

    // A reload during a pending write would swap in the older file and drop the edit.
    FileView {
        id: sessions_file
        path: root.path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (write_proc.running || root.queued_content !== "") return;
            if (text().trim() === "") {
                root.document = SessionJson.empty_document();
                root.load_error = "";
                return;
            }
            try {
                const data = JSON.parse(text());
                if (!SessionJson.valid_document(data)) throw new Error("expected an object with a sessions object");
                root.document = SessionJson.with_sessions(data, data.sessions || {});
                root.load_error = "";
            } catch (e) {
                root.load_error = String(e);
                console.warn("SessionStore: invalid sessions.json (" + e + ")");
            }
        }
        // Only a missing file starts empty; an unreadable one blocks writes like a malformed one, so a save cannot overwrite it.
        onLoadFailed: error => {
            if (write_proc.running || root.queued_content !== "") return;
            if (error === FileViewError.FileNotFound) {
                root.document = SessionJson.empty_document();
                root.load_error = "";
            } else {
                root.load_error = FileViewError.toString(error);
            }
        }
    }

    Component.onCompleted: root.refresh()
}
