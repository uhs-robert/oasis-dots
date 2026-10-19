import QtQuick
import Quickshell
import Quickshell.Io

// One settings object persisted as a JSON file: loaded and watched, written back debounced and atomically (tmp + rename).
// A store singleton holds one as a child and exposes `values` through its own named properties.
//
// A set in memory always beats the disk while it is unsaved: file changes that arrive while `dirty` or `writing` are ignored, which also covers the reload our own write causes.
// An external edit made inside that window is lost, as is any key it added.
Scope {
    id: root

    // Absolute path of the file.
    property string path: ""
    property var defaults: ({})
    // (raw) -> clean object; `raw` is the parsed top-level object. Null keeps it unchanged. Called on loads only.
    property var validate: null
    // Top-level keys the store owns. Any other key in the file is kept verbatim on every save and never shows in `values`, so a key the store deletes itself must be listed here or it would come back.
    property var known_keys: Object.keys(root.defaults)
    property int debounce_ms: 0
    property bool watch: true
    property bool block_loading: true
    // (values) -> argv or null, called after a write succeeded and never after a load. The argv runs once the write is on disk.
    property var after_save: null

    // Replaced, never mutated, so bindings on it fire. Starts as a copy of `defaults`.
    property var values: Object.assign({}, root.defaults)
    // The last parsed top-level object, {} when the file was missing or corrupt; for migrations that need old keys.
    property var raw: ({})
    // Read-only for callers.
    property bool loaded_once: false
    property bool dirty: false
    property bool writing: false

    // After values were replaced from disk or reset to defaults; not for echoes of our own writes.
    signal loaded
    signal saved
    signal save_failed(var error)
    signal after_save_done(int code)

    property var extras: ({})
    property string last_written: ""
    property string last_corrupt: ""
    property bool dir_ready: false
    property bool after_wanted: false
    // Toggled to re-arm the file watch.
    property bool rearming: false

    function set_key(key, value) {
        root.replace(Object.assign({}, root.values, { [key]: value }));
    }

    function patch(next) {
        root.replace(Object.assign({}, root.values, next));
    }

    function replace(next) {
        root.values = next;
        root.dirty = true;
        if (root.debounce_ms > 0) save_timer.restart();
        else root.start_write();
    }

    function flush() {
        if (!root.dirty) return;
        save_timer.stop();
        root.start_write();
    }

    function reload() {
        file.reload();
    }

    function start_write() {
        // A write in flight picks the newer values up from onSaved.
        if (root.writing) return;
        root.writing = true;
        if (root.dir_ready) {
            root.write_now();
            return;
        }
        mkdir_proc.command = ["mkdir", "-p", root.path.substring(0, root.path.lastIndexOf("/"))];
        mkdir_proc.running = true;
    }

    function write_now() {
        const text = JSON.stringify(Object.assign({}, root.extras, root.values));
        root.dirty = false;
        root.last_written = text;
        file.setText(text);
    }

    function fail_write(error) {
        root.writing = false;
        root.dirty = false;
        root.dir_ready = false;
        console.warn("JsonStore: could not write " + root.path + " (" + error + ")");
        root.save_failed(error);
    }

    function run_after_save() {
        if (typeof root.after_save !== "function") return;
        if (after_proc.running) {
            root.after_wanted = true;
            return;
        }
        const argv = root.after_save(root.values);
        if (!argv) return;
        after_proc.command = argv;
        after_proc.running = true;
    }

    function adopt(parsed) {
        const clean = typeof root.validate === "function" ? root.validate(parsed) : Object.assign({}, parsed);
        const extras = {};
        for (const key in parsed) {
            if (root.known_keys.indexOf(key) < 0 && !(key in clean)) extras[key] = parsed[key];
        }
        root.raw = parsed;
        root.extras = extras;
        root.values = clean;
    }

    Timer {
        id: save_timer
        interval: root.debounce_ms
        onTriggered: root.start_write()
    }

    Process {
        id: mkdir_proc
        onExited: code => {
            if (code !== 0) {
                root.fail_write("mkdir exited " + code);
                return;
            }
            root.dir_ready = true;
            // A watch armed while the directory was missing never fires for files created in it later.
            root.rearming = true;
            root.rearming = false;
            root.write_now();
        }
    }

    Process {
        id: after_proc
        onExited: code => {
            root.after_save_done(code);
            if (root.after_wanted) {
                root.after_wanted = false;
                root.run_after_save();
            }
        }
    }

    FileView {
        id: file
        path: root.path
        printErrors: false
        blockLoading: root.block_loading
        atomicWrites: true
        watchChanges: root.watch && !root.rearming

        onFileChanged: {
            if (!root.dirty && !root.writing) file.reload();
        }

        onSaved: {
            root.writing = false;
            root.saved();
            root.run_after_save();
            if (root.dirty && !save_timer.running) root.start_write();
        }

        onSaveFailed: error => root.fail_write(error)

        onLoaded: {
            if (root.dirty || root.writing) return;
            const text = file.text();
            if (root.loaded_once && text === root.last_written) return;
            let parsed = null;
            try {
                parsed = JSON.parse(text);
            } catch (e) {
                parsed = null;
            }
            root.loaded_once = true;
            if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
                if (text !== root.last_corrupt) console.warn("JsonStore: " + root.path + " is not a JSON object; keeping the current values");
                root.last_corrupt = text;
                return;
            }
            root.last_corrupt = "";
            root.adopt(parsed);
            root.loaded();
        }

        onLoadFailed: error => {
            if (root.dirty || root.writing) return;
            root.loaded_once = true;
            root.raw = {};
            root.extras = {};
            root.values = Object.assign({}, root.defaults);
            root.loaded();
        }
    }
}
