import QtQuick
import Quickshell
import Quickshell.Io

// One settings object persisted as a JSON file: loaded and watched, written back debounced and atomically (tmp + rename).
// A store singleton holds one as a child and exposes `values` through its own named properties.
//
// A set in memory always beats the disk while it is unsaved: file changes that arrive while `dirty` or `writing` are ignored.
// An external edit made inside that window is lost, as is any key it added.
//
// FileView is never asked to read or write from inside its own signals: it clears its live operation after emitting,
// which orphans one started in a handler (its saved never comes, and a read can then run beside the write and deliver
// older text). Both go through Qt.callLater, also for a set made from a `loaded` or `saved` handler.
//
// Echoes need no record of our writes. FileView disowns a read in flight when a write starts and ignores reload() while
// its write is live, so every load we receive was read after our last write landed. A load of `synced_text` changes
// nothing and is skipped; any other text is an edit, even one that restores an earlier write of ours.
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
    // (values) -> argv or null, called when a write starts and never for a load. The argv runs once that write is on disk, so it describes the values that write carried.
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
    // Mirrors the text FileView holds: our last write, or the last load ("" for a missing file). setText of that same
    // text is skipped by FileView and never answered with saved or saveFailed. Unwritten when that write failed.
    property string view_text: ""
    property bool view_text_unwritten: false
    // The text `values` were last reconciled with: our last write, the last load adopted or found corrupt, "" when missing.
    property string synced_text: ""
    // FileView drops a reload() asked while it is reading, so a change seen then is reread once that read is in.
    // It starts reading as soon as it has its path.
    property bool reading: true
    property bool reread: false
    property bool dir_ready: false
    // The after_save argv of the write in flight, computed from the values that write carries.
    property var pending_argv: null
    // Argvs of finished writes waiting for after_proc, which is still running for an earlier one. All run, in order: a later write cannot stand in for an earlier one, whose argv may be the one that reloads.
    property var queued_argvs: []
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
        if (root.writing) return;
        if (root.reading) {
            root.reread = true;
            return;
        }
        root.reading = true;
        Qt.callLater(root.read_now);
    }

    function read_now() {
        file.reload();
    }

    function start_write() {
        // A write in flight picks the newer values up from onSaved.
        if (root.writing) return;
        root.writing = true;
        if (root.dir_ready) {
            Qt.callLater(root.write_now);
            return;
        }
        mkdir_proc.command = ["mkdir", "-p", root.path.substring(0, root.path.lastIndexOf("/"))];
        mkdir_proc.running = true;
    }

    function write_now() {
        const text = JSON.stringify(Object.assign({}, root.extras, root.values));
        root.dirty = false;
        root.pending_argv = typeof root.after_save === "function" ? root.after_save(root.values) : null;
        root.synced_text = text;
        if (text === root.view_text) {
            // FileView would skip this setText without a word.
            if (root.view_text_unwritten) root.fail_write("unchanged since the failed write");
            else root.finish_write();
            return;
        }
        // The write disowns any read in flight.
        root.reading = false;
        root.reread = false;
        root.view_text = text;
        file.setText(text);
    }

    function finish_write() {
        root.writing = false;
        root.saved();
        const argv = root.pending_argv;
        root.pending_argv = null;
        root.run_after_save(argv);
        if (root.dirty && !save_timer.running) root.start_write();
    }

    function fail_write(error) {
        root.writing = false;
        root.dirty = false;
        root.dir_ready = false;
        root.pending_argv = null;
        console.warn("JsonStore: could not write " + root.path + " (" + error + ")");
        root.save_failed(error);
    }

    function run_after_save(argv) {
        if (!argv) return;
        if (after_proc.running) {
            root.queued_argvs = root.queued_argvs.concat([argv]);
            return;
        }
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
            if (root.queued_argvs.length > 0) {
                const next = root.queued_argvs[0];
                root.queued_argvs = root.queued_argvs.slice(1);
                root.run_after_save(next);
            }
        }
    }

    FileView {
        id: file
        path: root.path
        printErrors: false
        blockLoading: root.block_loading
        atomicWrites: true
        watchChanges: false

        onSaved: {
            root.view_text_unwritten = false;
            root.finish_write();
        }

        onSaveFailed: error => {
            root.view_text_unwritten = true;
            root.fail_write(error);
        }

        onLoaded: {
            const text = file.text();
            root.view_text = text;
            root.view_text_unwritten = false;
            root.reading = false;
            if (root.reread) {
                // This read may have started before the change that asked for it.
                root.reread = false;
                root.reload();
                return;
            }
            if (root.dirty || root.writing) return;
            if (root.loaded_once && text === root.synced_text) return;
            root.synced_text = text;
            let parsed = null;
            try {
                parsed = JSON.parse(text);
            } catch (e) {
                parsed = null;
            }
            root.loaded_once = true;
            if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
                console.warn("JsonStore: " + root.path + " is not a JSON object; keeping the current values");
                return;
            }
            root.adopt(parsed);
            root.loaded();
        }

        onLoadFailed: error => {
            root.view_text = "";
            root.view_text_unwritten = false;
            root.reading = false;
            if (root.reread) {
                root.reread = false;
                root.reload();
                return;
            }
            if (root.dirty || root.writing) return;
            root.loaded_once = true;
            root.synced_text = "";
            root.raw = {};
            root.extras = {};
            root.values = Object.assign({}, root.defaults);
            root.loaded();
        }
    }

    // The watch lives apart from `file` because FileView's reload() rebuilds its watch after starting the read, so a
    // change landing in between would never be reported. This one is never reloaded and keeps its watch.
    FileView {
        path: root.path
        preload: false
        printErrors: false
        watchChanges: root.watch && !root.rearming

        onFileChanged: {
            if (!root.dirty && !root.writing) root.reload();
        }
    }
}
