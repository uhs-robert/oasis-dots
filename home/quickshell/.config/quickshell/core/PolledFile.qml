import QtQuick
import Quickshell
import Quickshell.Io

// A file read on a timer and on demand, with `loaded` or `load_failed` for each read. The caller decides what a
// missing file means; a failed read is not logged, since a file that comes and goes is the usual reason to poll it.
// A `poll()` while a read is in flight is dropped by FileView, the next tick reads again.
Scope {
    id: root

    property string path: ""
    // Gates the timer only; `poll()` ignores it.
    property bool enabled: true
    // 0 means no timer, only `poll()`.
    property int interval_ms: 0
    // Fire the timer when `enabled` turns true, not only one interval later.
    property bool run_on_start: true
    // Reads synchronously, so `loaded` or `load_failed` arrives from inside `poll()`. FileView does not block again
    // once it has loaded a path.
    property bool block_loading: false

    signal loaded(string text)
    // `error` is a FileViewError.
    signal load_failed(var error)

    function poll() {
        view.reload();
    }

    Timer {
        interval: root.interval_ms
        running: root.enabled && root.interval_ms > 0
        repeat: true
        triggeredOnStart: root.run_on_start
        onTriggered: root.poll()
    }

    FileView {
        id: view
        path: root.path
        printErrors: false
        blockLoading: root.block_loading
        onLoaded: root.loaded(view.text())
        onLoadFailed: error => root.load_failed(error)
    }
}
