pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.core

// Official (checkupdates) and AUR (paru -Qua) update counts, ported from the Waybar
// arch_updates.rb script so the bar has no Ruby dependency.
Singleton {
    id: root

    property var official: []
    property var aur: []
    readonly property int total: official.length + aur.length

    property bool checking: false
    readonly property bool offline: Networking.connectivity === NetworkConnectivity.None
    property bool pending_refresh: false
    property string error: ""
    property double last_checked: 0

    property bool official_failed: false
    property bool aur_failed: false
    property bool official_available: true
    property bool aur_available: true
    readonly property bool available: official_available || aur_available
    property bool official_done: false
    property bool aur_done: false

    property bool upgrade_running: false

    readonly property int refresh_interval_ms: 1800000

    Component.onCompleted: root.refresh_if_due()

    onOfflineChanged: if (!root.offline) root.refresh_if_due()

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
        if (root.offline) return;
        if (root.checking) {
            root.pending_refresh = true;
            return;
        }
        root.checking = true;
        root.official_done = false;
        root.aur_done = false;
        official_cmd.run();
        aur_cmd.run();
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

    PolledCommand {
        id: official_cmd
        // Through sh so a missing checkupdates exits 127, read as unavailable, instead of failing to start.
        command: ["sh", "-c", "checkupdates"]
        onFinished: (code, out) => {
            root.official_available = code !== 127;
            if (!root.official_available) root.official = [];
            root.official_failed = code !== 0 && code !== 2 && code !== 127;
            if (code === 0) root.official = root.parse_official(out);
            else if (code === 2) root.official = [];
            root.official_done = true;
            root.finish_if_done();
        }
    }

    PolledCommand {
        id: aur_cmd
        command: ["sh", "-c", "paru -Qua"]
        onFinished: (code, out) => {
            root.aur_available = code !== 127;
            if (!root.aur_available) root.aur = [];
            root.aur_failed = code !== 0 && code !== 127;
            if (code === 0) root.aur = root.parse_aur(out);
            root.aur_done = true;
            root.finish_if_done();
        }
    }

    function run_upgrade() {
        if (root.upgrade_running) return;
        root.upgrade_running = true;
        upgrade_proc.running = true;
    }

    // scripts/focus-topgrade.sh finds the window by this class.
    readonly property string upgrade_class: "quickshell-upgrade"

    // Hyprland's term wrapper normalizes every terminal to `term -e cmd`, but may hand the
    // window to a running instance and exit at once, so the refresh waits on topgrade itself.
    Process {
        id: upgrade_proc
        command: ["env", "-u", "TMUX", "-u", "TMUX_PANE", "sh", "-c", "t=\"$0\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" --class " + root.upgrade_class + " -e topgrade", Paths.term_script]
        onExited: root.upgrade_watching = true
    }

    property bool upgrade_watching: false

    PolledCommand {
        id: upgrade_check
        command: ["pgrep", "-x", "topgrade"]
        enabled: root.upgrade_watching
        interval_ms: 10000
        run_on_start: false
        onFinished: code => {
            if (code === 0) return;
            root.upgrade_watching = false;
            root.upgrade_running = false;
            root.refresh();
        }
    }
}
