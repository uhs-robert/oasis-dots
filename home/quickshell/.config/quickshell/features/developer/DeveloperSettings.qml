pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "DeveloperSettings.js" as Logic

// Settings > Developer: the code reviewers (built-in plus the user's file) and the local-review and merge-gate choices
// saved in developer.json under the Quickshell state dir, which reviewers.sh reads as its Settings layer.
Singleton {
    id: root

    // The same overrides reviewers.sh honours, for tests and the shadow bar.
    readonly property string builtin_path: Quickshell.env("REVIEWERS_BUILTIN_FILE") || Quickshell.env("HOME") + "/.claude/skills/orchestrator/reviewers.json"
    readonly property string user_path: Quickshell.env("REVIEWERS_USER_FILE") || Paths.xdg("XDG_CONFIG_HOME", "/.config") + "/code-reviewers/reviewers.json"

    readonly property var choices: Logic.choices
    readonly property var saved: store.values
    property var installed: []
    readonly property var entries: Logic.merged_entries(builtin_layer.values.reviewers, user_layer.values.reviewers)
    readonly property var reviewers: Logic.rows(root.entries, root.saved, root.installed)
    readonly property var binaries: root.entries.map(e => e.local && typeof e.local.binary === "string" ? e.local.binary : "").filter(b => b !== "")

    function valid(key, value) {
        return Logic.valid(key, value);
    }

    function step(key, current, delta) {
        return Logic.step(key, current, delta);
    }

    function set(name, key, value) {
        if (!root.valid(key, value)) return;
        store.set_key("reviewers", Logic.with_choice(root.saved, name, key, value).reviewers);
    }

    // Looks for each binary on PATH; called when the section opens, since an install can happen while the bar runs.
    function probe() {
        if (probe_proc.running || root.binaries.length === 0) return;
        probe_proc.command = ["sh", "-c", 'for b; do command -v "$b" >/dev/null 2>&1 && echo "$b"; done', "sh"].concat(root.binaries);
        probe_proc.running = true;
    }

    onBinariesChanged: Qt.callLater(root.probe)

    JsonStore {
        id: store
        path: Paths.state_dir + "/developer.json"
        defaults: ({ reviewers: {} })
        debounce_ms: 300
        validate: raw => Logic.clean_saved(raw)
    }

    JsonStore {
        id: builtin_layer
        path: root.builtin_path
        read_only: true
        defaults: ({ reviewers: [] })
        validate: raw => Logic.clean_layer(raw)
    }

    JsonStore {
        id: user_layer
        path: root.user_path
        read_only: true
        defaults: ({ reviewers: [] })
        validate: raw => Logic.clean_layer(raw)
    }

    Process {
        id: probe_proc
        stdout: StdioCollector {
            onStreamFinished: root.installed = text.split("\n").filter(l => l !== "")
        }
    }
}
