// home/quickshell/.config/quickshell/services/ThemeAudio.qml
pragma Singleton
import QtQuick
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../theme"

// Per-style UI, notification and lock sounds: sounds/<style>/ ships in the repo, ~/.local/share/quickshell/sounds/<style>/ wins file by file. Saved in audio.json under the state dir.
Singleton {
    id: root

    property bool ui: false
    property bool notify: false
    property bool music: false
    property real volume: 0.5
    // "follow" uses the bar style's pack, else a style name.
    property string pack: "follow"
    // The lock host sets this while the session is locked.
    property bool lock_active: false

    readonly property var kinds: ["cursor", "confirm", "cancel", "notify"]
    readonly property var volumes: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    readonly property var packs: ["follow"].concat(Style.names)
    readonly property string user_dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/quickshell/sounds"
    readonly property string pack_name: root.pack === "follow" || Style.names.indexOf(root.pack) < 0 ? Style.saved_name : root.pack
    readonly property string music_name: root.pack === "follow" && Style.lock_name in Style.styles ? Style.lock_name : root.pack_name
    // These lock skins bring their own music.
    readonly property bool own_music: ["ff7", "ocarina"].indexOf(Style.lock_name) >= 0
    readonly property bool music_on: root.lock_active && root.music && Style.lock_music && !root.own_music
    readonly property string music_url: music_pack.find("music", ["ogg", "wav", "mp3"])

    function valid_pack(name) {
        return root.packs.indexOf(name) >= 0;
    }

    function set_flag(name, on) {
        if (["ui", "notify", "music"].indexOf(name) < 0) return;
        root[name] = on;
        root.save();
    }

    function set_volume(value) {
        if (root.volumes.indexOf(value) < 0) return false;
        root.volume = value;
        root.save();
        return true;
    }

    function set_pack(name) {
        if (!root.valid_pack(name)) return false;
        root.pack = name;
        root.save();
        return true;
    }

    // Plays cursor, confirm, cancel or notify when its category is on.
    function play(kind) {
        if (kind === "notify" ? !root.notify : !root.ui) return;
        root.preview(kind);
    }

    function preview(kind) {
        const fx = ({ cursor: fx_cursor, confirm: fx_confirm, cancel: fx_cancel, notify: fx_notify })[kind];
        if (fx && fx.status === SoundEffect.Ready) fx.play();
    }

    function save() {
        state_file.setText(JSON.stringify({ ui: root.ui, notify: root.notify, music: root.music, volume: root.volume, pack: root.pack }));
    }

    component Pack: QtObject {
        id: pack

        property string style_name: ""
        property string user_dir: ""
        readonly property var urls: {
            const out = {};
            for (let i = 0; i < shipped.count; i++) out[shipped.get(i, "fileName")] = String(shipped.get(i, "fileUrl"));
            for (let i = 0; i < mine.count; i++) out[mine.get(i, "fileName")] = String(mine.get(i, "fileUrl"));
            return out;
        }

        function find(base, exts) {
            for (const ext of exts) {
                const url = pack.urls[base + "." + ext];
                if (url) return url;
            }
            return "";
        }

        FolderListModel {
            id: shipped
            folder: Qt.resolvedUrl("../sounds/" + (pack.style_name || "none"))
            nameFilters: ["*.wav", "*.ogg", "*.mp3"]
            showDirs: false
        }

        FolderListModel {
            id: mine
            folder: "file://" + pack.user_dir + "/" + (pack.style_name || "none")
            nameFilters: ["*.wav", "*.ogg", "*.mp3"]
            showDirs: false
        }
    }

    Pack { id: ui_pack; user_dir: root.user_dir; style_name: root.pack_name }
    Pack { id: music_pack; user_dir: root.user_dir; style_name: root.music_on ? root.music_name : "" }

    SoundEffect { id: fx_cursor; source: ui_pack.find("cursor", ["wav"]); volume: root.volume }
    SoundEffect { id: fx_confirm; source: ui_pack.find("confirm", ["wav"]); volume: root.volume }
    SoundEffect { id: fx_cancel; source: ui_pack.find("cancel", ["wav"]); volume: root.volume }
    SoundEffect { id: fx_notify; source: ui_pack.find("notify", ["wav"]); volume: root.volume }

    MediaPlayer {
        id: player
        source: root.music_on ? root.music_url : ""
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            volume: root.volume * 0.6
        }
        onMediaStatusChanged: {
            if (player.mediaStatus === MediaPlayer.LoadedMedia && root.music_on) player.play();
        }
        onSourceChanged: {
            if (player.source.toString() === "") player.stop();
        }
    }

    FileView {
        id: state_file
        path: Style.state_dir + "/audio.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.ui = data.ui === true;
                root.notify = data.notify === true;
                root.music = data.music === true;
                if (root.volumes.indexOf(data.volume) >= 0) root.volume = data.volume;
                if (typeof data.pack === "string" && (data.pack === "follow" || data.pack in Style.styles)) root.pack = data.pack;
            } catch (e) {
                console.warn("ThemeAudio: invalid audio.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    Component.onCompleted: state_file.reload()
}
