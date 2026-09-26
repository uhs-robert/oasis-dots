// home/quickshell/.config/quickshell/lock/LockIpc.qml
import Quickshell
import Quickshell.Io

// No unlock here: only a PAM success ends the lock.
Scope {
    id: root

    // Kept off the IpcHandler, which exposes every property it has.
    property var previewer: null

    IpcHandler {
        target: "lock"

        // Creates the Lock singleton at startup, so locking never waits on it.
        readonly property bool locked: Lock.locked

        // "ok" when a new lock starts, "locked" when one is already up, "failed" otherwise.
        function lock(): string {
            return Lock.lock();
        }

        // Shows a lock skin in a normal overlay window with fake state; the session lock and PAM are never touched.
        function preview(name: string): string {
            return root.previewer ? root.previewer.open(name) : "unavailable";
        }

        function preview_close(): string {
            if (root.previewer) root.previewer.close();
            return "ok";
        }

        // "secure" once the compositor confirms, "pending" before that, else "unlocked".
        function state(): string {
            return Lock.state();
        }
    }
}
