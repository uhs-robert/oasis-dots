import QtQuick
import Quickshell
import Quickshell.Io

// One settings object persisted as a JSON file: loaded and watched, written back debounced and atomically (tmp + rename).
// A store singleton holds one as a child and exposes `values` through its own named properties.
//
// With `read_only` the file belongs to another program: the store only follows it. Its setters do nothing, it never
// writes or makes the directory, and a file that is missing or not the expected JSON gives `defaults` (there is no
// write of ours for a corrupt file to protect).
//
// A set in memory always beats the disk while it is unsaved: file changes that arrive while `dirty` or `writing` are ignored.
// An external edit made inside that window is lost, as is any key it added.
//
// The first write waits for the initial read (it only matters with block_loading off), which a write would otherwise
// disown: the keys on disk would be neither adopted nor kept. The keys set before it arrives win; the disk fills in the rest.
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
    property bool read_only: false
    // Saves indented with a trailing newline, for a file people also edit by hand. Only the written format changes: the
    // unchanged-text skip compares the text in that same format, and a load of the other format is just an edit.
    property bool pretty: false
    // The file's top level is a JSON array, not an object (a user's list of entries); `validate` is then required.
    property bool array_root: false
    // (values) -> argv or null, called when a write starts and never for a load. The argv runs once that write is on disk, so it describes the values that write carried.
    property var after_save: null

    // Replaced, never mutated, so bindings on it fire. Starts as a copy of `defaults`.
    property var values: Object.assign({}, root.defaults)
    // The last parsed top level, {} when the file was missing or corrupt; for migrations that need old keys.
    property var raw: ({})
    // Read-only for callers.
    property bool loaded_once: false
    property bool dirty: false
    property bool writing: false
    // Counts edits; `write_seq` is the count the write in flight carries, so a failure can tell a newer edit from its own content.
    property int edit_seq: 0
    property int write_seq: 0

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
    // Set while a reload clears FileView's cached copy of text that failed to save; the load it ends with restarts the write.
    property bool retrying: false
    // The text `values` were last reconciled with: our last write, the last load adopted or found corrupt, "" when missing.
    property string synced_text: ""
    // FileView drops a reload() asked while it is reading, so a change seen then is reread once that read is in.
    // It starts reading as soon as it has its path.
    property bool reading: true
    property bool reread: false
    property bool dir_ready: false
    // Keys set before the initial load arrived.
    property var early_keys: ({})
    // The after_save argv of the write in flight, computed from the values that write carries.
    property var pending_argv: null
    // Argvs of finished writes waiting for after_proc, which is still running for an earlier one. All run, in order: a later write cannot stand in for an earlier one, whose argv may be the one that reloads.
    property var queued_argvs: []
    // Toggled to re-arm the file watch.
    property bool rearming: false

    function set_key(key, value) {
        root.commit(Object.assign({}, root.values, { [key]: value }), [key]);
    }

    function patch(next) {
        root.commit(Object.assign({}, root.values, next), Object.keys(next));
    }

    function replace(next) {
        root.commit(next, Object.keys(next));
    }

    // `keys` are the ones this edit set; before the initial load they are the only ones that beat the disk.
    function commit(next, keys) {
        if (root.read_only) return;
        if (!root.loaded_once) {
            const early = Object.assign({}, root.early_keys);
            for (const key of keys) early[key] = true;
            root.early_keys = early;
        }
        root.values = next;
        root.dirty = true;
        root.edit_seq += 1;
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

    // For a file whose directory did not exist when the store started: a watch armed then never fires for it.
    function rearm() {
        root.rearming = true;
        root.rearming = false;
        root.reload();
    }

    function read_now() {
        file.reload();
    }

    function start_write() {
        // A write in flight picks the newer values up from onSaved; the initial load starts the first one.
        if (root.read_only || root.writing || !root.loaded_once) return;
        root.writing = true;
        root.write_seq = root.edit_seq;
        if (root.dir_ready) {
            Qt.callLater(root.write_now);
            return;
        }
        mkdir_proc.command = ["mkdir", "-p", root.path.substring(0, root.path.lastIndexOf("/"))];
        mkdir_proc.running = true;
    }

    function write_now() {
        const merged = Object.assign({}, root.extras, root.values);
        const text = root.pretty ? JSON.stringify(merged, null, 2) + "\n" : JSON.stringify(merged);
        // FileView skips a setText equal to its cached text, silently, so a write of text that failed to save needs a
        // load first (any load drops the cache). Only an explicit write gets here; a failure never retries by itself.
        if (root.view_text_unwritten && text === root.view_text && !root.retrying) {
            root.retrying = true;
            file.reload();
            return;
        }
        root.retrying = false;
        root.dirty = false;
        root.write_seq = root.edit_seq;
        root.pending_argv = typeof root.after_save === "function" ? root.after_save(root.values) : null;
        root.synced_text = text;
        if (text === root.view_text) {
            // FileView would skip this setText without a word.
            root.finish_write();
            return;
        }
        // The write disowns any read in flight.
        root.reading = false;
        root.reread = false;
        root.view_text = text;
        file.setText(text);
    }

    // True when this load was the one a retry waited for.
    function resume_retry() {
        if (!root.retrying) return false;
        root.reread = false;
        Qt.callLater(root.write_now);
        return true;
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
        // Only an edit made after the failed write started stays dirty; the failed content is not retried, or an unwritable path would loop.
        root.dirty = root.edit_seq !== root.write_seq;
        root.dir_ready = false;
        root.pending_argv = null;
        console.warn("JsonStore: could not write " + root.path + " (" + error + ")");
        root.save_failed(error);
        if (root.dirty) Qt.callLater(root.resume_dirty);
    }

    // Deferred, like every write start: this runs out of a failure signal of FileView or mkdir_proc.
    function resume_dirty() {
        if (root.dirty && !root.writing && !save_timer.running) root.start_write();
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

    // The initial load found edits made before it arrived. They win key by key; the disk fills in the rest. `parsed` is
    // null for a missing or corrupt file, which leaves the edits as they are.
    function merge_initial(parsed, text) {
        root.loaded_once = true;
        root.synced_text = text;
        if (parsed !== null) {
            const edits = {};
            for (const key in root.early_keys) edits[key] = root.values[key];
            root.adopt(parsed);
            root.values = Object.assign({}, root.values, edits);
        }
        root.loaded();
        if (!save_timer.running) root.start_write();
    }

    function adopt(parsed) {
        const clean = typeof root.validate === "function" ? root.validate(parsed) : Object.assign({}, parsed);
        const extras = {};
        for (const key in parsed) {
            if (!root.read_only && root.known_keys.indexOf(key) < 0 && !(key in clean)) extras[key] = parsed[key];
        }
        root.raw = parsed;
        root.extras = extras;
        root.values = clean;
    }

    function reset_to_defaults() {
        root.raw = {};
        root.extras = {};
        root.values = Object.assign({}, root.defaults);
        root.loaded();
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
            if (root.resume_retry()) return;
            if (root.reread) {
                // This read may have started before the change that asked for it.
                root.reread = false;
                root.reload();
                return;
            }
            if (root.loaded_once && (root.dirty || root.writing)) return;
            if (root.loaded_once && text === root.synced_text) return;
            let parsed = null;
            try {
                parsed = JSON.parse(text);
            } catch (e) {
                parsed = null;
            }
            const usable = parsed !== null && typeof parsed === "object" && Array.isArray(parsed) === root.array_root;
            if (root.dirty) {
                root.merge_initial(usable ? parsed : null, text);
                return;
            }
            root.synced_text = text;
            root.loaded_once = true;
            if (!usable) {
                console.warn("JsonStore: " + root.path + " is not a JSON " + (root.array_root ? "array" : "object") + (root.read_only ? "; using the defaults" : "; keeping the current values"));
                if (root.read_only) root.reset_to_defaults();
                return;
            }
            root.adopt(parsed);
            root.loaded();
        }

        onLoadFailed: error => {
            root.view_text = "";
            root.view_text_unwritten = false;
            root.reading = false;
            if (root.resume_retry()) return;
            if (root.reread) {
                root.reread = false;
                root.reload();
                return;
            }
            if (root.loaded_once && (root.dirty || root.writing)) return;
            if (root.dirty) {
                root.merge_initial(null, "");
                return;
            }
            root.loaded_once = true;
            root.synced_text = "";
            root.reset_to_defaults();
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
