import QtQuick
import Quickshell
import qs.core
import "LoadGuard.js" as Guard

// Caps the CPU of agents.slice (the user unit agent sessions run in) while `locked`, and on unlock puts back the
// CPUQuota the user configured (none when they set none). The share comes from the unit's X-LockedCPUQuota key, so a
// user drop-in can change or unset it; without the unit or the key nothing is touched. `--runtime` keeps the cap out
// of the unit files, so a reboot always drops it.
Scope {
    id: root

    property bool locked: false
    property int threads: 0
    // A change arrived while a read or a set was running; sync again once it ends.
    property bool resync: false
    // This bar set a cap, so the unlock restores even if the key was removed meanwhile.
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
    // Unlocked at start restores the quota a bar which died while locked left capped.
    Component.onCompleted: root.sync()

    // Exits non-zero when agents.slice does not exist.
    PolledCommand {
        id: unit_read
        command: ["systemctl", "--user", "cat", "agents.slice"]
        onStart_failed: root.settle()
        onFinished: (code, out) => {
            const keyed = isFinite(Guard.locked_share(out));
            const quota = root.locked ? Guard.locked_quota(out, root.threads) : Guard.configured_quota(out);
            if (code !== 0 || (root.locked ? quota === "" : !keyed && !root.capped)) {
                root.settle();
                return;
            }
            root.capped = root.locked;
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
