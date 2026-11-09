import QtQuick
import Quickshell
import qs.core
import "LoadGuard.js" as Guard

// Caps the CPU of agents.slice (the user unit agent sessions run in) as a share of the machine's threads: the unit's
// X-UnlockedCPUQuota while unlocked and X-LockedCPUQuota while `locked`, never above a CPUQuota the user configured.
// A user drop-in can change a share or unset it with an empty key. An unset unlocked share leaves the slice at the
// configured quota, and without the unit or any key nothing is touched. `--runtime` keeps the cap out of the unit
// files, so a reboot always drops it.
Scope {
    id: root

    property bool locked: false
    property int threads: 0
    // A change arrived while a read or a set was running; sync again once it ends.
    property bool resync: false
    // This bar set a cap, so an unlock without an unlocked share restores the configured quota.
    property bool capped: false

    function sync() {
        if (unit_read.busy || set_quota.busy) {
            root.resync = true;
            return;
        }
        root.resync = false;
        unit_read.run();
    }

    function settle() {
        if (root.resync) root.sync();
    }

    onLockedChanged: root.sync()
    // The cpu list is read asynchronously, so threads can arrive after the start sync found it 0.
    onThreadsChanged: root.sync()
    // Starting applies the unlocked cap, and undoes one a bar that died while locked left.
    Component.onCompleted: root.sync()

    // Exits non-zero when agents.slice does not exist.
    PolledCommand {
        id: unit_read
        command: ["systemctl", "--user", "cat", "agents.slice"]
        onStart_failed: root.settle()
        onFinished: (code, out) => {
            const quota = Guard.slice_quota(out, root.threads, root.locked, root.capped);
            if (code !== 0 || quota === null) {
                root.settle();
                return;
            }
            root.capped = root.locked || isFinite(Guard.share(out, "X-UnlockedCPUQuota"));
            set_quota.command = ["systemctl", "--user", "set-property", "--runtime", "agents.slice", "CPUQuota=" + quota];
            set_quota.run();
        }
    }

    // A command rather than execDetached so a lock and an unlock in quick succession reach systemd in order.
    PolledCommand {
        id: set_quota
        onStart_failed: root.settle()
        onFinished: root.settle()
    }
}
