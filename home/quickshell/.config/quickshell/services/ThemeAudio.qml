// home/quickshell/.config/quickshell/services/ThemeAudio.qml
pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../theme"
import "../lock/skins/sound"

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
    readonly property string data_dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/quickshell"
    readonly property string user_dir: root.data_dir + "/sounds"
    // Imported game effects a style borrows over its shipped ones, as kind: file base.
    readonly property var borrowed: ({ ps1: { dir: root.data_dir + "/mgs2-audio", names: { cursor: "select", confirm: "submit", cancel: "back" } } })
    readonly property string pack_name: root.pack === "follow" || Style.names.indexOf(root.pack) < 0 ? Style.saved_name : root.pack
    readonly property string music_name: root.pack === "follow" && Style.lock_name in Style.styles ? Style.lock_name : root.pack_name
    // These lock skins bring their own music.
    readonly property bool own_music: ["ff7", "ocarina"].indexOf(Style.lock_name) >= 0
    readonly property bool music_on: root.lock_active && root.music && Style.lock_music && !root.own_music
    readonly property string music_url: music_pack.find("music", ["ogg", "wav", "mp3"])

    // The login screen's own pack, and the music file to hand the greeter ("" when off, or the skin brings its own).
    readonly property string login_skin: LoginScreen.resolved_screen
    readonly property string login_name: root.pack === "follow" && root.login_skin in Style.styles ? root.login_skin : root.pack_name
    readonly property string login_music_path: {
        if (!root.music || !LoginScreen.resolved_music || ["ff7", "ocarina"].indexOf(root.login_skin) >= 0) return "";
        return login_pack.find("music", ["ogg", "wav", "mp3"]).replace(/^file:\/\//, "");
    }

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
        const url = ui_pack.find(kind, ["wav", "ogg"]);
        if (url !== "") effects.queue(["loadfile", url, "replace"]);
    }

    function save() {
        state_file.setText(JSON.stringify({ ui: root.ui, notify: root.notify, music: root.music, volume: root.volume, pack: root.pack }));
    }

    component Pack: Item {
        id: pack

        property string style_name: ""
        property string user_dir: ""
        readonly property var borrow: root.borrowed[pack.style_name] || null
        function listing(model) {
            const out = {};
            for (let i = 0; i < model.count; i++) out[model.get(i, "fileName")] = String(model.get(i, "fileUrl"));
            return out;
        }

        readonly property var shipped_urls: pack.listing(shipped)
        readonly property var user_urls: pack.listing(mine)
        readonly property var borrowed_urls: pack.listing(lent)

        // The user's files beat borrowed ones, which beat shipped ones.
        function find(base, exts) {
            const lent_base = pack.borrow ? pack.borrow.names[base] : undefined;
            for (const [set, name] of [[pack.user_urls, base], [pack.borrowed_urls, lent_base], [pack.shipped_urls, base]]) {
                if (!name) continue;
                for (const ext of exts) {
                    if (set[name + "." + ext]) return set[name + "." + ext];
                }
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

        FolderListModel {
            id: lent
            folder: pack.borrow ? "file://" + pack.borrow.dir : ""
            nameFilters: ["*.wav", "*.ogg", "*.mp3"]
            showDirs: false
        }
    }

    Pack { id: ui_pack; user_dir: root.user_dir; style_name: root.pack_name }
    Pack { id: login_pack; user_dir: root.user_dir; style_name: root.login_name }
    Pack { id: music_pack; user_dir: root.user_dir; style_name: root.music_on ? root.music_name : "" }

    MpvProcess {
        id: effects
        wanted: root.ui || root.notify
        args: ["--idle=yes"]
        volume: root.volume
    }

    MpvProcess {
        wanted: root.music_on && root.music_url !== ""
        args: ["--loop-file=inf", root.music_url]
        volume: root.volume * 0.6
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
