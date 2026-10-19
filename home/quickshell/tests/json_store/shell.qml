import QtQuick
import Quickshell
import Quickshell.Io

// Harness shell for run.py: runs the scenario named by $SCENARIO against the files under $XDG_STATE_HOME and writes
// the result as result.json under $XDG_STATE_HOME when it is done, then quits.
ShellRoot {
    id: root

    readonly property string scenario: Quickshell.env("SCENARIO")
    readonly property string dir: Quickshell.env("XDG_STATE_HOME") + "/json_store"
    property var result: ({})

    // The result goes to a file and the shell quits once it is saved: a log line can be lost at exit.
    function finish() {
        result_file.setText(JSON.stringify(root.result));
    }

    FileView {
        id: result_file
        path: Quickshell.env("XDG_STATE_HOME") + "/result.json"
        atomicWrites: true
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    // The store scenarios: each plan gives the store's settings and timed steps (ms from start); `end` is when the
    // result is printed. Edits "from outside" are tmp + rename, like an editor or another program would save.
    readonly property string store_path: root.dir + "/store.json"
    readonly property var overlay: raw => {
        const out = { a: 0, b: 0 };
        for (const key in out) {
            if (key in raw) out[key] = raw[key];
        }
        return out;
    }
    property int loaded_count: 0
    property int saved_count: 0
    property var failures: []
    property var after_log: []
    property bool reload_pending: false
    property real started: 0
    property var done_steps: ({})

    function outside_write(path, text) {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf %s \"$2\" > \"$1.ext\" && mv \"$1.ext\" \"$1\"", "sh", path, text]);
    }

    readonly property var plans: ({
        // First run: the directory does not exist until the first set.
        firstrun: {
            path: root.dir + "/absent/deeper/store.json",
            steps: [[100, () => store.set_key("a", 1)]],
            end: 800
        },
        // A store that is only loaded creates nothing.
        no_write_before_set: {
            path: root.dir + "/absent/store.json",
            steps: [],
            end: 500
        },
        // Debounce against the reload our own write causes: the second set lands at several offsets around the echo. The
        // first set waits for the initial load, which a write starting earlier would cancel.
        echo: {
            debounce_ms: 100,
            steps: [0, 1, 2, 3, 4, 5, 6, 7].reduce((all, i) => all.concat([
                [100 + i * 600, () => store.set_key("a", i + 1)],
                [100 + i * 600 + [90, 100, 104, 110, 120, 150, 200, 300][i], () => store.set_key("b", i + 1)]
            ]), []),
            end: 100 + 8 * 600 + 800
        },
        // Immediate writes: five sets in a row all land, the last wins, and every echo is ignored.
        immediate: {
            debounce_ms: 0,
            steps: [1, 2, 3, 4, 5].map(i => [100 + i * 3, () => store.set_key("a", i)]),
            end: 1000
        },
        corrupt: {
            steps: [],
            end: 600
        },
        corrupt_then_set: {
            steps: [[300, () => store.set_key("a", 5)]],
            end: 900
        },
        external_idle: {
            steps: [[200, () => root.outside_write(root.store_path, '{"a":2,"b":1,"x":9}')]],
            end: 800
        },
        // The local value wins while a save is pending; an edit made in that window is dropped.
        external_dirty: {
            debounce_ms: 400,
            steps: [
                [200, () => root.outside_write(root.store_path, '{"a":2,"b":1,"x":9}')],
                [600, () => store.set_key("b", 7)],
                [700, () => root.outside_write(root.store_path, '{"a":3,"b":1,"x":10,"y":1}')]
            ],
            end: 1800
        },
        unknown_keys: {
            defaults: { week_start: "locale" },
            validate: raw => ({ week_start: raw.week_start || "locale" }),
            steps: [[200, () => store.set_key("week_start", "sunday")]],
            end: 800
        },
        // A key the store drops itself stays dropped only when it is listed in known_keys.
        dropped_known: {
            known_keys: ["a", "b"],
            steps: [[200, () => store.replace({ a: 1 })]],
            end: 800
        },
        // after_save runs once the write is on disk, and only for our own writes.
        after_save: {
            debounce_ms: 50,
            after_save: values => {
                const kind = root.reload_pending ? "reload" : "apply";
                root.reload_pending = false;
                return ["sh", "-c", 'echo "$1 $(cat "$2")" >> "$3"', "sh", kind, root.store_path, root.dir + "/after.log"];
            },
            steps: [
                [100, () => { root.reload_pending = true; store.set_key("a", 1); }],
                [600, () => store.set_key("a", 2)],
                [900, () => root.outside_write(root.store_path, '{"a":3,"b":0}')]
            ],
            end: 1600
        },
        // A file edited and then put back to the text we last wrote is an edit, not our echo.
        revert: {
            steps: [
                [100, () => store.set_key("a", 1)],
                [500, () => root.outside_write(root.store_path, '{"a":2,"b":0}')],
                [900, () => root.outside_write(root.store_path, '{"a":1,"b":0}')]
            ],
            end: 1400
        },
        // Same for a delete (reset to defaults) followed by the same bytes again.
        recreate: {
            steps: [
                [100, () => store.set_key("a", 1)],
                [500, () => Quickshell.execDetached(["rm", root.store_path])],
                [900, () => root.outside_write(root.store_path, '{"a":1,"b":0}')]
            ],
            end: 1400
        },
        // Two saves, then the file is put back to the first one's bytes (an editor's undo): an edit, not a late echo.
        undo_to_earlier_write: {
            steps: [
                [100, () => store.set_key("a", 1)],
                [400, () => store.set_key("a", 2)],
                [800, () => root.outside_write(root.store_path, '{"a":1,"b":0}')]
            ],
            end: 1300
        },
        // Setting what the file already holds writes nothing but still completes; the store must not wait for it.
        same_value: {
            steps: [
                [100, () => store.set_key("a", 1)],
                [400, () => store.set_key("a", 1)],
                [700, () => store.set_key("a", 2)]
            ],
            end: 1200
        },
        // Two outside saves back to back: the second can land while the first one's read is in flight. Under load only.
        external_burst: {
            steps: [[200, () => Quickshell.execDetached(["sh", "-c",
                "printf %s '{\"a\":1,\"b\":0}' > \"$1.ext\" && mv \"$1.ext\" \"$1\" && printf %s '{\"a\":2,\"b\":0}' > \"$1.ext\" && mv \"$1.ext\" \"$1\"",
                "sh", root.store_path])]],
            end: 800
        },
        // A migration that sets from its loaded handler, which runs inside FileView's own signal.
        // The first save makes the directory known, so the set after the edit goes straight to FileView.
        set_from_loaded: {
            on_loaded: () => { if (root.loaded_count === 2) store.set_key("b", 9); },
            steps: [
                [100, () => store.set_key("a", 3)],
                [400, () => root.outside_write(root.store_path, '{"a":4,"b":0}')]
            ],
            end: 900
        },
        // A set lands while a write is in flight: each write's argv comes from the values it carried, and the second
        // one waits for the first, which is still running (it sleeps).
        after_save_inflight: {
            after_save: values => {
                const kind = root.reload_pending ? "reload" : "apply";
                root.reload_pending = false;
                return ["sh", "-c", 'sleep 0.3; echo "$1" >> "$2"', "sh", kind, root.dir + "/after.log"];
            },
            steps: [
                [100, () => store.set_key("c", 0)],
                [600, () => {
                    store.set_key("a", 1);
                    // The store starts its write on the next turn of the event loop; this set comes right after that.
                    Qt.callLater(() => { root.reload_pending = true; store.set_key("b", 5); });
                }]
            ],
            end: 2200
        },
        // The directory cannot be made (its parent is a file): save_failed fires and after_save never runs.
        write_fails: {
            path: root.dir + "/blocker/store.json",
            after_save: values => { root.after_log.push("called"); return null; },
            steps: [[100, () => store.set_key("a", 1)]],
            end: 800
        },
        // An edit lands while a write that then fails is in flight: it must be tried, not dropped with the failed one.
        // The set comes on the next turn of the event loop, after the write started (its mkdir is still running).
        edit_during_failed_write: {
            path: root.dir + "/blocker/store.json",
            steps: [[100, () => {
                store.set_key("a", 1);
                Qt.callLater(() => store.set_key("a", 2));
            }]],
            end: 800
        },
        // Same through flush() with a debounce: nothing else would start a write for the newer edit.
        edit_during_failed_flush: {
            path: root.dir + "/blocker/store.json",
            debounce_ms: 300,
            steps: [[100, () => {
                store.set_key("a", 1);
                store.flush();
                Qt.callLater(() => { store.set_key("a", 2); store.flush(); });
            }]],
            end: 900
        },
        // A write fails, the path becomes writable, and the same values are set again: that is a real write attempt.
        // run.py makes the directory unwritable first; the step between the sets makes it writable again.
        same_values_after_failed_write: {
            steps: [
                [100, () => store.set_key("a", 1)],
                [300, () => Quickshell.execDetached(["chmod", "700", root.dir])],
                [500, () => store.set_key("a", 1)]
            ],
            end: 1000
        },
        // The watch was armed while the directory was missing: the first save makes it, and an edit after that must still arrive.
        watch_after_first_write: {
            path: root.dir + "/late/store.json",
            steps: [
                [100, () => store.set_key("a", 1)],
                [600, () => root.outside_write(root.dir + "/late/store.json", '{"a":4,"b":0}')]
            ],
            end: 1200
        }
    })
    readonly property var plan: root.plans[root.scenario] || ({})

    JsonStore {
        id: store
        path: root.plan.path || root.store_path
        defaults: root.plan.defaults || ({ a: 0, b: 0 })
        validate: root.plan.validate || root.overlay
        known_keys: root.plan.known_keys || Object.keys(root.plan.defaults || ({ a: 0, b: 0 }))
        debounce_ms: root.plan.debounce_ms || 0
        after_save: root.plan.after_save || null
        onLoaded: {
            root.loaded_count += 1;
            if (root.plan.on_loaded) root.plan.on_loaded();
        }
        onSaved: root.saved_count += 1
        onSave_failed: error => root.failures = root.failures.concat([String(error)])
        onAfter_save_done: code => root.after_log = root.after_log.concat(["done " + code])
    }

    Timer {
        id: clock
        interval: 5
        repeat: true
        running: !!root.plans[root.scenario]
        onTriggered: {
            const elapsed = Date.now() - root.started;
            (root.plan.steps || []).forEach((step, index) => {
                if (elapsed >= step[0] && !root.done_steps[index]) {
                    root.done_steps[index] = true;
                    step[1]();
                }
            });
            if (elapsed >= root.plan.end) {
                clock.stop();
                root.result = {
                    values: store.values, raw: store.raw, loaded_count: root.loaded_count, saved_count: root.saved_count,
                    failures: root.failures, after_log: root.after_log, dirty: store.dirty, writing: store.writing
                };
                root.finish();
            }
        }
    }

    Component.onCompleted: root.started = Date.now()

    // Scenario "atomic": the store's write primitive. Two writes 400 ms apart; run.py watches the directory and
    // requires the second one to arrive as a rename over the target, and the target's inode to change.
    FileView {
        id: atomic_file
        path: root.dir + "/atomic.json"
        atomicWrites: true
        printErrors: false
        property int saves: 0
        property int failures: 0
        onSaved: {
            atomic_file.saves += 1;
            if (atomic_file.saves === 1) second_write.start();
            else {
                root.result = { saves: atomic_file.saves, failures: atomic_file.failures };
                root.finish();
            }
        }
        onSaveFailed: error => {
            atomic_file.failures += 1;
            root.result = { saves: atomic_file.saves, failures: atomic_file.failures, error: String(error) };
            root.finish();
        }
    }

    Timer {
        id: second_write
        interval: 400
        onTriggered: atomic_file.setText("{\"n\":2}")
    }

    Timer {
        interval: 50
        running: root.scenario === "atomic"
        onTriggered: atomic_file.setText("{\"n\":1}")
    }

    // Hard stop so a scenario that never finishes fails on the missing result file instead of hanging.
    Timer {
        interval: 8000
        running: true
        onTriggered: Qt.quit()
    }
}
