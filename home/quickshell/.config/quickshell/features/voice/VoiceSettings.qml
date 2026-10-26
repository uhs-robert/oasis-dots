pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Voice choices saved in voice.env under the voxcmd state dir, for voxcmd-wake, voxcmd and voxtype-duck to read.
// The file is KEY=VALUE lines (numbers, and the sensitivity level's name), one per setting the user has chosen; an absent key means the reader's own default.
// It sits outside ~/.config/voxcmd, which is stow-folded into the public repo. An environment variable of the same
// name still wins in every reader, so a value shown here may be overridden; the sensitivity row shows that as Custom.
Singleton {
    id: root

    readonly property string state_dir: Paths.voxcmd_state_dir
    readonly property string file_path: root.state_dir + "/voice.env"

    // The named sensitivity levels; voxcmd-wake maps each to its detector's threshold and frames.
    readonly property var level_ids: ["strict", "balanced", "relaxed"]
    readonly property string default_level: "strict"
    // Percent of its volume the output sink keeps while voxtype records; voxtype-duck's default is 30.
    readonly property int default_duck: 30
    readonly property var duck_steps: [0, 10, 20, 30, 50, 70]
    // The listener keeps hearing while music plays (a song can then say the phrase) and stops while another app records.
    readonly property int default_pause_for_media: 0
    readonly property int default_pause_for_mic: 1

    readonly property var keys: ({
            sensitivity: "VOXCMD_WAKE_SENSITIVITY",
            duck: "VOXCMD_DUCK_MEDIA_VOLUME",
            pause_media: "VOXCMD_WAKE_PAUSE_FOR_MEDIA",
            pause_mic: "VOXCMD_WAKE_PAUSE_FOR_MIC"
        })
    // Reads a value as the listener and voxcmd do, from its exact text: undefined when they would ignore it.
    // Matching by text, not by number, keeps 0.0, 01 and 30.0 out, as voxcmd's voice env reader and voxcmd-wake do.
    readonly property var readers: ({
            sensitivity: text => root.level_ids.indexOf(text) >= 0 ? text : undefined,
            duck: text => /^[0-9]+$/.test(text) && Number(text) <= 100 ? Number(text) : undefined,
            pause_media: text => text === "0" || text === "1" ? Number(text) : undefined,
            pause_mic: text => text === "0" || text === "1" ? Number(text) : undefined
        })

    // The user's saved choices; a setting never chosen is absent, not defaulted.
    property var saved: ({})
    // The units a pending write must try-restart once it lands.
    property var restart_units: ({})

    // The environment voxcmd-wake and voxtype-duck actually run with: the user manager's (`set-environment`) overlaid by
    // each unit's own Environment= (drop-ins), read from systemd because the bar's own environment never sees either.
    // Until the first read lands, the bar's environment stands in. EnvironmentFile= is not followed.
    property var service_env: null

    function env_value(name) {
        return root.service_env !== null ? (root.service_env[name] || "") : (Quickshell.env(name) || "");
    }

    function parse_service_env(text) {
        const found = {};
        for (const line of text.split("\n")) {
            // `show-environment` prints KEY=VALUE lines; `show -p Environment` prints one Environment= line per unit.
            const pairs = line.startsWith("Environment=") ? line.slice("Environment=".length).split(/\s+/) : [line];
            for (const pair of pairs) {
                const match = /^"?([A-Za-z_][A-Za-z0-9_]*)=(.*?)"?$/.exec(pair);
                if (match) found[match[1]] = match[2];
            }
        }
        return found;
    }

    // What the readers will use: their environment, else the file, else the default.
    function effective(key, fallback) {
        const from_env = root.readers[key](root.env_value(root.keys[key]));
        if (from_env !== undefined) return from_env;
        return root.saved[key] !== undefined ? root.saved[key] : fallback;
    }

    // Raw threshold or frames in the environment override any level, so the level shown would not be what runs.
    readonly property bool env_overrides_level: !!root.env_value("VOXCMD_WAKE_THRESHOLD") || !!root.env_value("VOXCMD_WAKE_FRAMES")
    readonly property string sensitivity: root.env_overrides_level ? "custom" : root.effective("sensitivity", root.default_level)
    readonly property int duck: root.effective("duck", root.default_duck)
    readonly property int pause_for_media: root.effective("pause_media", root.default_pause_for_media)
    readonly property int pause_for_mic: root.effective("pause_mic", root.default_pause_for_mic)

    function set(key, value) {
        if (!root.readers[key] || root.readers[key](String(value)) === undefined) return;
        const next = Object.assign({}, root.saved);
        const units = Object.assign({}, root.restart_units);
        next[key] = value;
        // voxtype-duck reads the percent at each duck; the listener reads its settings once, at its own start.
        if (key !== "duck") units["voxcmd-wake.service"] = true;
        root.saved = next;
        root.restart_units = units;
        save_timer.restart();
    }

    function file_text() {
        return Object.keys(root.keys).filter(k => root.saved[k] !== undefined).map(k => root.keys[k] + "=" + root.saved[k] + "\n").join("");
    }

    function parse(text) {
        const found = {};
        for (const line of text.split("\n")) {
            const match = /^(VOXCMD_[A-Z_]+)=([0-9]+(\.[0-9]+)?|[a-z]+)$/.exec(line);
            if (match) found[match[1]] = match[2];
        }
        const next = {};
        for (const key in root.keys) {
            const value = root.readers[key](found[root.keys[key]] || "");
            if (value !== undefined) next[key] = value;
        }
        return next;
    }

    function reload() {
        voice_file.reload();
        if (!env_proc.running) env_proc.running = true;
    }

    Process {
        id: env_proc
        command: ["sh", "-c", "systemctl --user show-environment; systemctl --user show -p Environment voxcmd-wake.service voxtype-duck.service"]
        stdout: StdioCollector {
            onStreamFinished: root.service_env = root.parse_service_env(text)
        }
    }

    // try-restart leaves a stopped unit stopped, so a listener the user has off is not started by a setting.
    Timer {
        id: save_timer
        interval: 300
        onTriggered: {
            if (save_proc.running) {
                save_timer.restart();
                return;
            }
            const units = Object.keys(root.restart_units);
            root.restart_units = ({});
            save_proc.command = ["sh", "-c", "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/voice.env.tmp\" && mv \"$1/voice.env.tmp\" \"$1/voice.env\" || exit 1; shift 2; for unit; do systemctl --user try-restart \"$unit\"; done",
                "sh", root.state_dir, root.file_text()].concat(units);
            save_proc.running = true;
        }
    }

    Process {
        id: save_proc
    }

    FileView {
        id: voice_file
        path: root.file_path
        printErrors: false
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        // A reload during a pending or running write would put the older file over the choice just made.
        onLoaded: if (!save_timer.running && !save_proc.running) root.saved = root.parse(text())
        onLoadFailed: error => {
            if (!save_timer.running && !save_proc.running) root.saved = ({});
        }
    }
}
