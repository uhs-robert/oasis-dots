// home/quickshell/.config/quickshell/services/UpdatesState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Official (checkupdates) and AUR (paru -Qua) update counts, ported from the Waybar
// arch_updates.rb script so the bar has no Ruby dependency.
Singleton {
    id: root

    property var official: []
    property var aur: []
    readonly property int total: official.length + aur.length

    property bool checking: false
    property bool pending_refresh: false
    property string error: ""
    property double last_checked: 0

    property bool official_failed: false
    property bool aur_failed: false
    property bool official_done: false
    property bool aur_done: false

    property bool upgrade_running: false

    readonly property int refresh_interval_ms: 1800000

    Component.onCompleted: root.refresh_if_due()

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh_if_due()
    }

    function refresh_if_due() {
        if (Date.now() - root.last_checked >= root.refresh_interval_ms) root.refresh();
    }

    function refresh() {
        if (root.checking) {
            root.pending_refresh = true;
            return;
        }
        root.checking = true;
        root.official_done = false;
        root.aur_done = false;
        official_proc.running = true;
        aur_proc.running = true;
    }

    // Splits "name oldver -> newver" into { name, old, new }; blank lines are skipped.
    function parse_line(line) {
        const trimmed = line.trim();
        if (!trimmed) return null;
        const m = /^(\S+)\s+(\S+)\s+->\s+(\S+)/.exec(trimmed);
        if (!m) return null;
        return { name: m[1], old: m[2], new: m[3] };
    }

    function parse_official(text) {
        return text.split("\n").map(root.parse_line).filter(p => !!p);
    }

    // Drops -git/-svn/-hg/-bzr/-cvs packages, matching arch_updates.rb's aur filter.
    function parse_aur(text) {
        return text.split("\n").map(root.parse_line).filter(p => !!p && !/-(?:git|svn|hg|bzr|cvs)$/.test(p.name));
    }

    function finish_if_done() {
        if (!root.official_done || !root.aur_done) return;
        root.checking = false;
        root.last_checked = Date.now();
        const failed = [root.official_failed ? "checkupdates" : "", root.aur_failed ? "paru" : ""].filter(n => !!n);
        root.error = failed.length ? failed.join(" and ") + " failed, showing the last results" : "";
        if (root.pending_refresh) {
            root.pending_refresh = false;
            root.refresh();
        }
    }

    // The exit code rides on the last stdout line, so parsing never races the process exit.
    function split_status(text) {
        const m = /__rc=(\d+)\s*$/.exec(text);
        return { code: m ? parseInt(m[1]) : -1, body: m ? text.slice(0, m.index) : text };
    }

    Process {
        id: official_proc
        command: ["sh", "-c", "checkupdates; echo \"__rc=$?\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.split_status(text);
                root.official_failed = r.code !== 0 && r.code !== 2;
                if (r.code === 0) root.official = root.parse_official(r.body);
                else if (r.code === 2) root.official = [];
                root.official_done = true;
                root.finish_if_done();
            }
        }
    }

    Process {
        id: aur_proc
        command: ["sh", "-c", "paru -Qua; echo \"__rc=$?\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.split_status(text);
                root.aur_failed = r.code !== 0;
                if (r.code === 0) root.aur = root.parse_aur(r.body);
                root.aur_done = true;
                root.finish_if_done();
            }
        }
    }

    function run_upgrade() {
        if (root.upgrade_running) return;
        root.upgrade_running = true;
        upgrade_proc.running = true;
    }

    // Hyprland's term wrapper normalizes every terminal to `term -e cmd`, but may hand the
    // window to a running instance and exit at once, so the refresh waits on topgrade itself.
    Process {
        id: upgrade_proc
        command: ["env", "-u", "TMUX", "-u", "TMUX_PANE", "sh", "-c", "t=\"$HOME/.config/hypr/scripts/term\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e topgrade"]
        onExited: upgrade_watch.start()
    }

    Timer {
        id: upgrade_watch
        interval: 10000
        repeat: true
        onTriggered: if (!upgrade_check.running) upgrade_check.running = true
    }

    Process {
        id: upgrade_check
        command: ["pgrep", "-x", "topgrade"]
        onExited: code => {
            if (code === 0) return;
            upgrade_watch.stop();
            root.upgrade_running = false;
            root.refresh();
        }
    }
}
