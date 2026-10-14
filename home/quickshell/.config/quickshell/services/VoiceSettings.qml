// home/quickshell/.config/quickshell/services/VoiceSettings.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Voice choices saved in voice.env under the voxcmd state dir, for voxcmd-wake, voxcmd and voxtype-daemon to read.
// The file is KEY=NUMBER lines, one per setting the user has chosen; an absent key means the reader's own default.
// It sits outside ~/.config/voxcmd, which is stow-folded into the public repo. An environment variable of the same
// name still wins in every reader, so a value shown here may be overridden; the sensitivity row shows that as Custom.
Singleton {
    id: root

    readonly property string state_dir: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state") + "/voxcmd";
    }
    readonly property string file_path: root.state_dir + "/voice.env"

    readonly property var levels: ({
            strict: { threshold: 0.8, frames: 3 },
            balanced: { threshold: 0.7, frames: 2 },
            relaxed: { threshold: 0.6, frames: 2 }
        })
    readonly property var level_ids: ["strict", "balanced", "relaxed"]
    // Percent of its volume ducked music keeps while voxtype records; 30 is config.toml's own value.
    readonly property int default_duck: 30
    readonly property real default_chunk_pause: 2.5
    readonly property var duck_steps: [0, 10, 20, 30, 50, 70]
    readonly property var chunk_pause_steps: [1.5, 2, 2.5, 3, 4]

    // The listener keeps hearing while music plays (a song can then say the phrase) and stops in a calendar meeting.
    readonly property int default_pause_for_media: 0
    readonly property int default_pause_for_meetings: 1

    readonly property var keys: ({
            threshold: "VOXCMD_WAKE_THRESHOLD",
            frames: "VOXCMD_WAKE_FRAMES",
            duck: "VOXCMD_DUCK_MEDIA_VOLUME",
            chunk: "VOXCMD_TYPE_CHUNK_PAUSE_SECS",
            pause_media: "VOXCMD_WAKE_PAUSE_FOR_MEDIA",
            pause_meetings: "VOXCMD_WAKE_PAUSE_FOR_MEETINGS"
        })
    readonly property var limits: ({
            threshold: v => v > 0 && v <= 1,
            frames: v => Number.isInteger(v) && v >= 1,
            duck: v => Number.isInteger(v) && v >= 0 && v <= 100,
            chunk: v => v > 0 && v <= 30,
            pause_media: v => v === 0 || v === 1,
            pause_meetings: v => v === 0 || v === 1
        })

    // The user's saved numbers; a setting never chosen is absent, not defaulted.
    property var saved: ({})
    // The units a pending write must try-restart once it lands.
    property var restart_units: ({})

    function number_or_undefined(text) {
        return /^[0-9]+(\.[0-9]+)?$/.test(text || "") ? Number(text) : undefined;
    }

    // What the readers will use: their environment, else the file, else the default. Only the Quickshell process's
    // own environment is visible here, which is the best the bar can know about the systemd user manager's.
    function effective(key, fallback) {
        const from_env = root.number_or_undefined(Quickshell.env(root.keys[key]));
        if (from_env !== undefined && root.limits[key](from_env)) return from_env;
        return root.saved[key] !== undefined ? root.saved[key] : fallback;
    }

    readonly property string sensitivity: {
        const threshold = root.effective("threshold", root.levels.strict.threshold);
        const frames = root.effective("frames", root.levels.strict.frames);
        for (const id of root.level_ids) {
            if (root.levels[id].threshold === threshold && root.levels[id].frames === frames) return id;
        }
        return "custom";
    }
    readonly property int duck: root.effective("duck", root.default_duck)
    readonly property real chunk_pause: root.effective("chunk", root.default_chunk_pause)

    readonly property int pause_for_media: root.effective("pause_media", root.default_pause_for_media)
    readonly property int pause_for_meetings: root.effective("pause_meetings", root.default_pause_for_meetings)

    function set(key, value) {
        const next = Object.assign({}, root.saved);
        const units = Object.assign({}, root.restart_units);
        if (key === "sensitivity") {
            if (!root.levels[value]) return;
            next.threshold = root.levels[value].threshold;
            next.frames = root.levels[value].frames;
            units["voxcmd-wake.service"] = true;
        } else if (key === "pause_media" || key === "pause_meetings") {
            if (!root.limits[key](value)) return;
            next[key] = value;
            // Read once when the listener starts, like its sensitivity.
            units["voxcmd-wake.service"] = true;
        } else if (key === "duck" || key === "chunk") {
            if (!root.limits[key](value)) return;
            next[key] = value;
            // The chunk pause is read afresh by each type-mode session; only voxtype reads ducking once, at start.
            if (key === "duck") units["voxtype.service"] = true;
        } else {
            return;
        }
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
            const match = /^(VOXCMD_[A-Z_]+)=([0-9]+(\.[0-9]+)?)$/.exec(line);
            if (match) found[match[1]] = Number(match[2]);
        }
        const next = {};
        for (const key in root.keys) {
            const value = found[root.keys[key]];
            if (value !== undefined && root.limits[key](value)) next[key] = value;
        }
        return next;
    }

    function reload() {
        voice_file.reload();
    }

    // try-restart leaves a stopped unit stopped, so a listener or voxtype the user has off is not started by a setting.
    // A voxtype restart cuts off a recording in progress.
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
