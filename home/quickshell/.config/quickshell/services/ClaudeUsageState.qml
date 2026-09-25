// home/quickshell/.config/quickshell/services/ClaudeUsageState.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// `claude -p /usage`, refreshed every 10 min only on AC while agents run, and when one finishes.
Singleton {
    id: root

    property var rows: []
    property bool loading: false
    property string error: ""
    property double updated: 0

    readonly property int max_age_ms: 300000
    readonly property int timeout_ms: 60000
    readonly property int poll_ms: 600000

    // Warn once per reset window: session at 80%, any weekly limit at 90%.
    readonly property var warnings: root.rows.filter(r => r.percent >= (/session/i.test(r.label) ? 80 : 90))
    readonly property bool warning: root.warnings.length > 0
    // Persisted so a restart or reload doesn't warn again for the same window.
    property var warned: ({})

    // The reset time wobbles between e.g. "6am" and "5:59am"; round to the hour.
    function reset_key(resets) {
        const m = /^(\w+ \d+),?\s*(\d+)(?::(\d+))?\s*(am|pm)/i.exec(resets || "");
        if (!m) return resets || "";
        const hour = (parseInt(m[2]) % 12 + (/pm/i.test(m[4]) ? 12 : 0) + (m[3] && parseInt(m[3]) >= 30 ? 1 : 0)) % 24;
        return m[1] + " " + hour;
    }

    FileView {
        id: warned_file
        path: Quickshell.stateDir + "/claude_usage_warned.json"
        printErrors: false
        blockAllReads: true
        onLoaded: {
            try {
                root.warned = JSON.parse(text()) || {};
            } catch (e) {}
        }
        onLoadFailed: error => {}
    }

    onWarningsChanged: {
        if (root.rows.length === 0) return;
        const next = {};
        for (const r of root.warnings) {
            const key = r.label + "|" + root.reset_key(r.resets);
            next[key] = true;
            if (root.warned[key]) continue;
            const urgency = r.percent >= 95 ? "critical" : "normal";
            Quickshell.execDetached(["notify-send", "-a", "Claude usage", "-u", urgency, r.label + " at " + r.percent + "%", r.resets ? "Resets " + r.resets : ""]);
        }
        root.warned = next;
        warned_file.setText(JSON.stringify(next));
    }

    Timer {
        interval: root.poll_ms
        running: Power.on_ac && KeeptabsState.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    // A finished agent is exactly when usage just moved; the tooltip lists each session's state.
    property int done_count: 0
    Connections {
        target: KeeptabsState
        function onTooltipChanged() {
            const count = KeeptabsState.tooltip.split("\n").filter(l => l.startsWith("DONE")).length;
            if (count > root.done_count && Power.on_ac) root.refresh(true);
            root.done_count = count;
        }
    }

    // Matches "Current session: 15% used · resets Aug 31, 11pm (America/New_York)" and the
    // dash variant; the reset clause is optional so a line with no reset still parses.
    readonly property var line_pattern: /^(Current [^:]+):\s*(\d+)%\s*used(?:\s*[·-]\s*resets\s*(.+))?$/

    function refresh(force) {
        if (fetch_proc.running) return;
        if (!force && root.updated > 0 && Date.now() - root.updated < root.max_age_ms) return;
        root.loading = true;
        root.error = "";
        fetch_proc.running = true;
        timeout_timer.restart();
    }

    function parse(result_text) {
        const out = [];
        for (const line of (result_text || "").split("\n")) {
            const m = root.line_pattern.exec(line.trim());
            if (!m) continue;
            out.push({ label: m[1], percent: parseInt(m[2]), resets: m[3] ? m[3].trim() : "" });
        }
        return out;
    }

    Process {
        id: fetch_proc
        command: ["env", "-u", "TMUX", "-u", "TMUX_PANE", "claude", "-p", "/usage", "--output-format", "json", "--no-session-persistence"]
        onExited: code => {
            timeout_timer.stop();
            root.loading = false;
            if (code !== 0 && !root.error) root.error = "claude /usage exited with code " + code;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.is_error) {
                        root.error = "claude /usage reported an error";
                        return;
                    }
                    const parsed = root.parse(data.result);
                    if (parsed.length === 0) {
                        root.error = "could not parse usage output";
                        return;
                    }
                    root.rows = parsed;
                    root.updated = Date.now();
                    root.error = "";
                } catch (e) {
                    root.error = "claude /usage failed: " + e;
                }
            }
        }
    }

    Timer {
        id: timeout_timer
        interval: root.timeout_ms
        onTriggered: if (fetch_proc.running) fetch_proc.running = false
    }
}
