// home/quickshell/.config/quickshell/settings/sections/VoiceSection.qml
import QtQuick
import Quickshell.Io
import "../../services"
import ".."
import "../Choices.js" as Choices

RowsSection {
    id: root

    // voxcmd-wake exits 78 when openWakeWord or its models are missing; the unit does not retry that.
    readonly property int exit_missing_setup: 78
    readonly property string unit: "voxcmd-wake.service"

    // "unknown" until the first answer; then "missing" (no unit), "off", "starting", "on", "failed" or "setup".
    property string listener_state: "unknown"
    // "enabled" or "disabled" (anything not enabled, including a missing unit).
    property string login_state: "unknown"

    readonly property var sensitivity_names: ({ strict: "Strict", balanced: "Balanced", relaxed: "Relaxed", custom: "Custom" })
    readonly property var listener_texts: ({
            unknown: "Checking...",
            missing: "Not installed",
            off: "Off",
            starting: "Starting...",
            on: "On",
            failed: "Failed",
            setup: "Needs setup"
        })

    function parse_show(text) {
        const fields = {};
        for (const line of text.split("\n")) {
            const at = line.indexOf("=");
            if (at > 0) fields[line.slice(0, at)] = line.slice(at + 1);
        }
        if (fields.LoadState === "not-found") return "missing";
        if (fields.ActiveState === "active" || fields.ActiveState === "reloading") return "on";
        if (fields.ActiveState === "activating") return "starting";
        if (fields.ActiveState === "failed") return Number(fields.ExecMainStatus) === root.exit_missing_setup ? "setup" : "failed";
        return "off";
    }

    function refresh() {
        if (!listener_proc.running) listener_proc.running = true;
        if (!login_proc.running) login_proc.running = true;
    }

    // A running or starting listener is switched off; anything else (off, failed, needs setup) is switched on.
    function toggle_listener(wanted) {
        if (root.listener_state === "missing") return;
        root.listener_state = wanted === "on" ? "starting" : "off";
        toggle_proc.command = wanted === "on" ? ["systemctl", "--user", "start", "--no-block", root.unit] : ["systemctl", "--user", "stop", root.unit];
        toggle_proc.running = true;
    }

    function toggle_login(wanted) {
        if (root.listener_state === "missing") return;
        root.login_state = wanted === "on" ? "enabled" : "disabled";
        login_set_proc.command = ["systemctl", "--user", wanted === "on" ? "enable" : "disable", root.unit];
        login_set_proc.running = true;
    }

    rows: [{
            label: "Listener",
            desc: "Hears \"hey jarvis\" and starts a voice command, holding the microphone while on. " + (root.listener_state === "setup" ? "Needs python-openwakeword and its models; see the voxcmd README." : "The first start downloads its models."),
            values: () => ["on", "off"],
            text: v => v === (root.listener_state === "on" || root.listener_state === "starting" ? "on" : "off") ? root.listener_texts[root.listener_state] : (v === "on" ? "On" : "Off"),
            value: () => root.listener_state === "on" || root.listener_state === "starting" ? "on" : "off",
            set: v => root.toggle_listener(v),
            pick: false
        }, {
            label: "Start at login",
            desc: "Turns the listener on at every login. Off, it waits until you switch it on.",
            values: () => ["on", "off"],
            text: v => v === "on" ? "On" : "Off",
            value: () => root.login_state === "enabled" ? "on" : "off",
            set: v => root.toggle_login(v),
            pick: false
        }, {
            label: "Sensitivity",
            desc: "Strict starts by mistake least; Relaxed hears you most easily. A change restarts the listener if it runs. An environment variable shows as Custom.",
            values: () => VoiceSettings.sensitivity === "custom" ? VoiceSettings.level_ids.concat(["custom"]) : VoiceSettings.level_ids,
            text: v => root.sensitivity_names[v] || String(v),
            value: () => VoiceSettings.sensitivity,
            set: v => VoiceSettings.set("sensitivity", v)
        }, {
            label: "While media plays",
            desc: "Keep listening lets a song or video say \"hey jarvis\" and start a command. Pause stops the listener while a player plays. A change restarts the listener if it runs.",
            values: () => [0, 1],
            text: v => v === 1 ? "Pause" : "Keep listening",
            value: () => VoiceSettings.pause_for_media,
            set: v => VoiceSettings.set("pause_media", v)
        }, {
            label: "While mic is active",
            desc: "Pause stops the listener while another app, such as a call, is recording from a microphone. Keep listening does not. A change restarts the listener if it runs.",
            values: () => [0, 1],
            text: v => v === 1 ? "Pause" : "Keep listening",
            value: () => VoiceSettings.pause_for_mic,
            set: v => VoiceSettings.set("pause_mic", v)
        }, {
            label: "Music while recording",
            desc: "The share of its volume music keeps while recording. A change restarts voxtype, which cuts off a recording in progress.",
            values: () => Choices.with_current(VoiceSettings.duck_steps, VoiceSettings.duck),
            text: v => v === 0 ? "Silent" : v + "%",
            value: () => VoiceSettings.duck,
            set: v => VoiceSettings.set("duck", v)
        }, {
            label: "Type mode pause",
            desc: "How long a pause ends a chunk of dictation, which is then typed. Applies to the next type-mode session.",
            values: () => Choices.with_current(VoiceSettings.chunk_pause_steps, VoiceSettings.chunk_pause),
            text: v => v + " s",
            value: () => VoiceSettings.chunk_pause,
            set: v => VoiceSettings.set("chunk", v)
        }]

    // Settings keeps a loaded section across closes, so the units are asked again on every open.
    Component.onCompleted: {
        root.refresh();
        VoiceSettings.reload();
    }
    onLiveChanged: if (root.live) {
        root.refresh();
        VoiceSettings.reload();
    }

    // The listener starts slowly on first use (it fetches models), so the state is followed while the pane is open.
    Timer {
        interval: 2000
        repeat: true
        running: root.live
        onTriggered: root.refresh()
    }

    Process {
        id: listener_proc
        command: ["systemctl", "--user", "show", "-p", "LoadState", "-p", "ActiveState", "-p", "ExecMainStatus", root.unit]
        stdout: StdioCollector {
            onStreamFinished: root.listener_state = root.parse_show(text)
        }
    }

    Process {
        id: login_proc
        command: ["systemctl", "--user", "is-enabled", root.unit]
        stdout: StdioCollector {
            onStreamFinished: root.login_state = text.trim() === "enabled" ? "enabled" : "disabled"
        }
    }

    Process {
        id: toggle_proc
        onExited: refresh_timer.restart()
    }

    Process {
        id: login_set_proc
        onExited: refresh_timer.restart()
    }

    Timer {
        id: refresh_timer
        interval: 800
        onTriggered: root.refresh()
    }
}
