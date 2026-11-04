import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "LoadGuard.js" as Guard

// While `active`, samples the CPU load and the AMD chip power (PPT) every few seconds and turns `still` on after
// about 30 s of heavy load, off after about 30 s of calm; the lock stops its skin's motion while it is on.
Scope {
    id: root

    property bool active: false
    readonly property bool still: root.state.still
    readonly property int threads: Guard.thread_count(online.text())
    // Test seam: /proc and /sys are read under this directory, so a fixture tree can fake the load.
    readonly property string sys_root: Quickshell.env("QS_LOAD_GUARD_ROOT") || ""

    property var state: Guard.initial()
    property bool power_probed: false
    // The amdgpu hwmon folder and its power1_cap text; power is not sampled without a cap to compare it to.
    property string power_dir: ""
    property string power_cap: ""
    property string power_text: ""

    onActiveChanged: {
        root.state = Guard.initial();
        root.power_text = "";
        if (root.active && !root.power_probed) {
            root.power_probed = true;
            power_probe.run();
        }
    }

    onStillChanged: {
        const s = root.state;
        console.info("Lock: load guard " + (root.still ? "stilled the lock" : "resumed the lock") + " (load " + s.loads.map(v => v.toFixed(2)).join(" ") + ", power " + s.powers.map(v => isFinite(v) ? v.toFixed(2) : "-").join(" ") + ")");
    }

    FileView {
        id: online
        path: root.sys_root + "/sys/devices/system/cpu/online"
        blockLoading: true
        printErrors: false
    }

    // The amdgpu hwmon is not always the same hwmonN, so it is found by name.
    PolledCommand {
        id: power_probe
        command: ["sh", "-c", "for d in \"$1\"/sys/class/hwmon/hwmon*; do if [ \"$(cat \"$d/name\" 2>/dev/null)\" = amdgpu ]; then echo \"$d\"; cat \"$d/power1_cap\" 2>/dev/null; exit 0; fi; done", "sh", root.sys_root]
        onFinished: (code, out) => {
            const lines = out.split("\n");
            root.power_dir = (lines[0] || "").trim();
            root.power_cap = (lines[1] || "").trim();
        }
    }

    PolledFile {
        path: root.power_dir === "" ? "" : root.power_dir + "/power1_input"
        enabled: root.active && root.power_dir !== "" && root.power_cap !== ""
        interval_ms: Guard.sample_ms
        onLoaded: text => root.power_text = text
    }

    PolledFile {
        path: root.sys_root + "/proc/loadavg"
        enabled: root.active
        interval_ms: Guard.sample_ms
        // FileView also reads once when its path is set, active or not. Power comes from the previous tick's read, at
        // most one sample old.
        onLoaded: text => {
            if (!root.active) return;
            root.state = Guard.step(root.state, {
                load: Guard.load_ratio(text, root.threads),
                power: Guard.power_ratio(root.power_text, root.power_cap)
            });
        }
    }
}
