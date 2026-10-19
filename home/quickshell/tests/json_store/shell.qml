import QtQuick
import Quickshell
import Quickshell.Io

// Harness shell for run.py: runs the scenario named by $SCENARIO against the files under $XDG_STATE_HOME and prints
// one "RESULT {json}" line when it is done, then quits.
ShellRoot {
    id: root

    readonly property string scenario: Quickshell.env("SCENARIO")
    readonly property string dir: Quickshell.env("XDG_STATE_HOME") + "/json_store"
    property var result: ({})

    function finish() {
        console.log("RESULT " + JSON.stringify(root.result));
        Qt.quit();
    }

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

    // Hard stop so a scenario that never finishes fails on the missing RESULT line instead of hanging.
    Timer {
        interval: 8000
        running: true
        onTriggered: Qt.quit()
    }
}
