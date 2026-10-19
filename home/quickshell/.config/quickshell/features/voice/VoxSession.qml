pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.theme

// The voice session voxcmd keeps open (rapid, click, type...), read from the file it writes while one is
// open and removes when it ends. The top level describes the current mode; `stack` holds the modes underneath, last
// being the one returned to. While `active`, the microphone re-opens after every turn, so the bar says so.
Singleton {
    id: root

    readonly property bool active: session_open && owner_alive
    readonly property string kind: session.values.kind
    readonly property string label: session.values.label
    readonly property string exit_hint: session.values.exit_hint
    readonly property var stack: session.values.stack

    // Colored per mode kind from the submap palette, as SubmapState does per submap. Kinds from other integrations
    // fall back to the theme's secondary color.
    readonly property var color_map: ({
        "rapid": Theme.syntax_builtin_func,
        "click": Theme.syntax_macro,
        "type": Theme.syntax_string,
    })
    readonly property color mode_color: color_map[kind] || Theme.theme_secondary

    readonly property string voxcmd_dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voxcmd"
    readonly property bool session_open: session.values.open
    readonly property int owner: session.values.owner
    readonly property string owner_start: session.values.owner_start
    property bool owner_alive: false
    property bool voxcmd_dir_exists: false

    // The file exists only while a session is open, so a missing or unreadable one is the defaults: not open.
    JsonStore {
        id: session
        path: root.voxcmd_dir + "/session.json"
        read_only: true
        defaults: ({ open: false, kind: "", label: "", exit_hint: "", stack: [], owner: 0, owner_start: "" })
        validate: raw => ({
            open: true,
            kind: String(raw.kind || ""),
            label: String(raw.label || "Voice session"),
            exit_hint: String(raw.exit_hint || ""),
            stack: Array.isArray(raw.stack) ? raw.stack : [],
            owner: Number(raw.owner) || 0,
            owner_start: String(raw.owner_start || "")
        })
        onLoaded: {
            if (session.values.open) owner_probe.reload();
        }
    }

    // A watch only reports a file appearing in a folder that exists, and voxcmd makes its folder on first use, which
    // can come after the bar starts. Until the folder is there it is looked for; reading a folder fails with an error
    // other than FileNotFound.
    FileView {
        id: voxcmd_dir_probe
        path: root.voxcmd_dir
        printErrors: false
        blockLoading: true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                return;
            root.voxcmd_dir_exists = true;
            session.rearm();
        }
    }

    Timer {
        running: !root.voxcmd_dir_exists
        repeat: true
        triggeredOnStart: true
        interval: 1000
        onTriggered: voxcmd_dir_probe.reload()
    }

    // voxcmd removes the file however its owner ends, except when the owner is killed outright (SIGKILL), so while a
    // session shows, its owner is checked. A pid alone could be a new process that reused it, so the owner is the pid
    // with the start time voxcmd saved, as voxcmd's own session_state_locked checks.
    FileView {
        id: owner_probe
        path: root.owner > 0 ? "/proc/" + root.owner + "/stat" : ""
        printErrors: false
        blockLoading: true
        onLoaded: root.owner_alive = root.owner_start !== "" && root.process_start_time(text()) === root.owner_start
        onLoadFailed: error => root.owner_alive = false
    }

    // Field 22 of /proc/<pid>/stat, the start time in clock ticks since boot. Fields are counted after the last ")",
    // since the command name in parentheses may hold spaces and parentheses itself.
    function process_start_time(stat: string): string {
        const after_name = stat.slice(stat.lastIndexOf(")") + 1).trim().split(/\s+/);
        // after_name starts at field 3 (the state).
        return after_name.length > 19 ? after_name[19] : "";
    }

    Timer {
        running: root.session_open
        repeat: true
        interval: 3000
        onTriggered: owner_probe.reload()
    }
}
