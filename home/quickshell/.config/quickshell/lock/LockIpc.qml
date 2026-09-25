// home/quickshell/.config/quickshell/lock/LockIpc.qml
import Quickshell.Io

// No unlock here: only a PAM success ends the lock.
IpcHandler {
    target: "lock"

    // Creates the Lock singleton at startup, so locking never waits on it.
    readonly property bool locked: Lock.locked

    // "ok" when a new lock starts, "locked" when one is already up, "failed" otherwise.
    function lock(): string {
        return Lock.lock();
    }

    // "secure" once the compositor confirms, "pending" before that, else "unlocked".
    function state(): string {
        return Lock.state();
    }
}
