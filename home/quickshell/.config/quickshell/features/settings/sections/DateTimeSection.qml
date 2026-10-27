import QtQuick
import Quickshell
import Quickshell.Io
import qs.features.settings
import qs.features.clock
import qs.features.popups
import qs.core

RowsSection {
    id: root

    readonly property var week_names: ({ locale: "Follow locale", monday: "Monday", sunday: "Sunday" })

    readonly property var formats: ({ locale: "Follow locale", "12h": "12-hour", "24h": "24-hour" })

    // `calendar-sync setup --check` exit codes; 127 is the shell's command-not-found, -1 means no answer yet.
    readonly property int check_connected: 0
    readonly property int check_rbw_locked: 3
    readonly property int check_keyring_locked: 4
    readonly property int check_missing: 127
    property int check_code: -1

    readonly property string state_name: {
        if (root.check_code === root.check_missing) return "missing";
        if (root.check_code === root.check_rbw_locked) return "rbw_locked";
        if (root.check_code === root.check_keyring_locked) return "keyring_locked";
        if (root.check_code === root.check_connected) return CalendarState.error !== "" ? "failed" : "connected";
        return root.check_code < 0 ? "checking" : "not_connected";
    }

    // Asks the store, which may be rbw, so it runs when this section opens or on request, never on a timer.
    function run_check() {
        if (!check_proc.running) check_proc.running = true;
    }

    // CalendarState.now_ms ticks each minute, so the text stays current while the section is open.
    function ago(ms) {
        const minutes = Math.max(0, Math.floor((CalendarState.now_ms - ms) / 60000));
        if (minutes < 1) return "just now";
        if (minutes < 60) return minutes + " min ago";
        if (minutes < 1440) return Math.floor(minutes / 60) + " h ago";
        return Math.floor(minutes / 1440) + " d ago";
    }

    readonly property bool has_error_time: CalendarState.error_at_ms > 0 && CalendarState.error_at_ms < 8.64e15

    readonly property var status_texts: ({
            checking: "Checking...",
            missing: "Not installed",
            not_connected: "Not connected",
            rbw_locked: "rbw locked",
            keyring_locked: "Keyring locked"
        })

    function status_text() {
        if (root.state_name === "connected") return "Connected · " + (CalendarState.updated_ms > 0 ? "synced " + root.ago(CalendarState.updated_ms) : "not synced yet");
        if (root.state_name === "failed") return "Last sync failed" + (root.has_error_time ? " · " + TimeFormat.format(new Date(CalendarState.error_at_ms)) : "");
        return root.status_texts[root.state_name];
    }

    readonly property var descriptions: ({
            checking: "Looking up whether a calendar is connected.",
            missing: "The calendar package is not installed. Run just stow calendar in your dotfiles checkout, then reopen Settings.",
            not_connected: "Shows your meetings in the bar and clock popup. Connect runs calendar-sync setup in a terminal.",
            rbw_locked: "The stored calendar address is in rbw, which is locked. Run rbw unlock in a terminal, then check again.",
            keyring_locked: "The stored calendar address is in the system keyring, which is locked. Unlock it (usually by logging in again), then check again."
        })

    function description() {
        if (root.state_name === "connected") return "Syncs every 5 minutes. Sync now fetches again; Reconnect runs calendar-sync setup in a terminal.";
        if (root.state_name === "failed") return CalendarState.error + ". The bar keeps the last good copy. Sync now tries again; Reconnect runs calendar-sync setup in a terminal.";
        return root.descriptions[root.state_name];
    }

    readonly property var actions: ({
            connect: { label: "Connect", run: () => root.open_setup() },
            reconnect: { label: "Reconnect", run: () => root.open_setup() },
            sync: { label: "Sync now", run: () => root.sync_now() },
            check: { label: "Check again", run: () => root.run_check() }
        })

    readonly property var action_ids: ({
            not_connected: ["connect"],
            connected: ["sync", "reconnect"],
            failed: ["sync", "reconnect"],
            rbw_locked: ["check"],
            keyring_locked: ["check"]
        })

    function sync_now() {
        if (!sync_proc.running) sync_proc.running = true;
    }

    // The terminal stays open after setup so its last message can be read.
    function open_setup() {
        Popups.after_close(() => Quickshell.execDetached(["env", "-u", "TMUX", "-u", "TMUX_PANE", "sh", "-c", "t=\"$0\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e sh -c \"$1\"", Paths.term_script, "calendar-sync setup; printf '\\nPress Enter to close. '; read -r _"]));
    }

    function offer_actions() {
        const ids = root.action_ids[root.state_name] || [];
        if (ids.length === 0) return;
        root.open_list("Calendar", ids, ids.map(id => root.actions[id].label), "", id => root.actions[id].run());
    }

    function build_rows() {
        const actionable = (root.action_ids[root.state_name] || []).length > 0;
        return [{ heading: "Format" }, {
                label: "Time format",
                desc: "Used by every clock and popup time. Follow locale uses your system's convention.",
                values: () => ClockSettings.choices.time_format,
                text: v => root.formats[v] || String(v),
                value: () => ClockSettings.time_format,
                set: v => ClockSettings.set("time_format", v)
            }, {
                label: "First day of week",
                desc: "The calendar's first column. Follow locale uses your system's convention.",
                values: () => ClockSettings.choices.week_start,
                text: v => root.week_names[v] || String(v),
                value: () => ClockSettings.week_start,
                set: v => ClockSettings.set("week_start", v)
            }, { heading: "Calendar" }, {
                label: "Calendar",
                desc: root.description(),
                keys: actionable ? "Enter actions" : "",
                values: () => [],
                text: v => root.status_text(),
                value: () => "",
                set: v => {},
                cycle: false,
                activate: actionable ? () => root.offer_actions() : undefined
            }];
    }

    rows: root.build_rows()

    Component.onCompleted: root.run_check()
    // The pane outlives a closed popup, so reopening it (say after Connect) must check again.
    onLiveChanged: if (root.live) root.run_check()

    // calendar-sync pokes the bar only after a good sync; after a failed one its error.json is new and unwatched, so
    // the pane rereads the cache and the connection itself once the sync ends.
    Process {
        id: sync_proc
        command: ["calendar-sync", "--now"]
        onExited: {
            CalendarState.refresh();
            root.run_check();
        }
    }

    Process {
        id: check_proc
        // --check reports a missing rbw as locked, since rbw is the default store; without rbw it is just not connected,
        // and Connect must stay on offer so setup can pick the keyring or a private file.
        command: ["sh", "-c", "command -v calendar-sync >/dev/null 2>&1 || exit 127; calendar-sync setup --check; code=$?; [ $code -eq 3 ] && ! command -v rbw >/dev/null 2>&1 && exit 1; exit $code"]
        onExited: code => root.check_code = code
    }
}
