// home/quickshell/.config/quickshell/services/ThemeAudio.qml
pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../theme"
import "../lock/skins/sound"

// UI and notification sounds from one effects pack (a sounds/<pack>/ directory or an imported game), the style's own unless the user picks one; ~/.local/share/quickshell/sounds/<pack>/ wins file by file, and its <style>/ is the only source of lock and login music. Saved in audio.json under the state dir.
Singleton {
    id: root

    property bool ui: false
    property bool notify: false
    property bool music: false
    property real music_volume: 0.5
    property real fx_volume: 0.5
    // The user's pack for every style; "" follows the style (its preset, else its own).
    property string choice: ""
    // The lock host sets this while the session is locked.
    property bool lock_active: false
    // The lock host clears this until a key press; lock music fades out with it.
    property bool lock_armed: true
    property real music_level: root.lock_armed ? 1 : 0
    Behavior on music_level { NumberAnimation { duration: 800 } }

    readonly property var kinds: ["cursor", "confirm", "cancel", "notify", "error", "lock", "unlock"]
    // A pack without one of these plays the other kind instead; lock and unlock have none and stay silent.
    readonly property var fallbacks: ({ error: "cancel" })
    readonly property var volumes: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    readonly property string data_dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/quickshell"
    readonly property string user_dir: root.data_dir + "/sounds"
    // Game packs, offered once imported; names maps a kind to the file base, and a kind left out uses the style's own sound.
    readonly property var games: ({
            "game:ff7": { label: "FFVII", replaces: "ff7", dir: "file://" + root.data_dir + "/ff7-audio", legacy_dir: Qt.resolvedUrl("../lock/skins/ff7/audio"), names: { cursor: "cursor", confirm: "cursor", cancel: "cancel", error: "buzzer" } },
            "game:mgs2": { label: "MGS2 (imported)", dir: "file://" + root.data_dir + "/mgs2-audio", names: { cursor: "select", confirm: "submit", cancel: "back", error: "error" } },
            "game:ocarina": { label: "Ocarina", dir: "file://" + root.data_dir + "/ocarina-audio", names: { cursor: "move", confirm: "decide", cancel: "cancel", notify: "letter", error: "error" } }
        })
    // Shipped packs that belong to no style.
    readonly property var extra_packs: ({ mgs2: { label: "MGS2" } })
    readonly property var presets: ({ ff7: "game:ff7" })
    readonly property var game_urls: {
        const out = {};
        for (let i = 0; i < game_dirs.count; i++) {
            const dir = game_dirs.objectAt(i);
            if (dir && dir.urls) out[dir.key] = dir.urls;
        }
        return out;
    }
    readonly property var imported_games: Object.keys(root.game_urls).filter(key => Object.keys(root.game_urls[key]).length > 0)
    readonly property string music_name: Style.lock_name in Style.styles ? Style.lock_name : Style.saved_name
    // These lock skins bring their own music.
    readonly property var own_music_skins: ["ff7", "goldeneye", "mgs2", "ocarina"]
    readonly property bool own_music: root.own_music_skins.indexOf(Style.lock_name) >= 0
    readonly property bool music_on: root.lock_active && root.music && Style.lock_music && !root.own_music
    readonly property string music_url: music_pack.find("music", ["ogg", "wav", "mp3"])

    // The login screen's own pack, and the music file to hand the greeter ("" when off, or the skin brings its own).
    readonly property string login_skin: LoginScreen.resolved_screen
    readonly property string login_name: root.login_skin in Style.styles ? root.login_skin : Style.saved_name
    readonly property string login_music_path: {
        if (!root.music || !LoginScreen.resolved_music || root.own_music_skins.indexOf(root.login_skin) >= 0) return "";
        return login_pack.find("music", ["ogg", "wav", "mp3"]).replace(/^file:\/\//, "");
    }

    // A FolderListModel keeps its old rows when pointed at a missing folder, so rows from elsewhere are dropped.
    function listing(model) {
        const out = {};
        const prefix = String(model.folder).replace(/\/?$/, "/");
        for (let i = 0; i < model.count; i++) {
            const url = String(model.get(i, "fileUrl"));
            if (url.startsWith(prefix)) out[model.get(i, "fileName")] = url;
        }
        return out;
    }

    function valid_pack(name) {
        return Style.names.indexOf(name) >= 0 || name in root.extra_packs || root.imported_games.indexOf(name) >= 0;
    }

    function default_pack(style_name) {
        return root.presets[style_name] || style_name;
    }

    // The pack a style really uses: the user's choice, else its preset, else its own.
    function pack_for(style_name) {
        for (const name of [root.choice, root.default_pack(style_name)]) {
            if (name && root.valid_pack(name)) return name;
        }
        return style_name;
    }

    // "" is follow the style; an imported game hides the style pack it replaces.
    function pack_options() {
        const hidden = root.imported_games.map(key => root.games[key].replaces).filter(name => name);
        return [""].concat(Style.names.filter(name => hidden.indexOf(name) < 0), Object.keys(root.extra_packs), root.imported_games);
    }

    function pack_label(name) {
        const pack = root.games[name] || root.extra_packs[name];
        return pack ? pack.label : Style.label(name);
    }

    function set_flag(name, on) {
        if (["ui", "notify", "music"].indexOf(name) < 0) return;
        root[name] = on;
        root.save();
    }

    function set_volume(name, value) {
        if (["music_volume", "fx_volume"].indexOf(name) < 0 || root.volumes.indexOf(value) < 0) return false;
        root[name] = value;
        root.save();
        return true;
    }

    function set_pack(name) {
        if (name !== "" && !root.valid_pack(name)) return false;
        root.choice = name;
        root.save();
        return true;
    }

    // Plays cursor, confirm, cancel or notify when its category is on.
    function play(kind) {
        if (kind === "notify" ? !root.notify : !root.ui) return;
        root.preview(kind);
    }

    // Lock screen cues; a skin with its own audio plays its own.
    function play_lock(kind) {
        if (!root.own_music) root.play(kind);
    }

    readonly property string fx_node_name: "quickshell-fx"
    property int voice: 0
    property real played_at: 0

    function preview(kind) {
        const url = ui_pack.find(kind, ["wav", "ogg"]) || (root.fallbacks[kind] ? ui_pack.find(root.fallbacks[kind], ["wav", "ogg"]) : "");
        const now = Date.now();
        if (url === "" || now - root.played_at < 30) return;
        root.played_at = now;
        voices.objectAt(root.voice).play(["pw-play", "-P", "{ node.name = " + root.fx_node_name + " }", "--volume", String(root.fx_volume), decodeURIComponent(String(url).replace(/^file:\/\//, ""))]);
        root.voice = (root.voice + 1) % voices.count;
    }

    function save() {
        state_file.setText(JSON.stringify({ ui: root.ui, notify: root.notify, music: root.music, music_volume: root.music_volume, fx_volume: root.fx_volume, pack: root.choice }));
    }

    component Pack: Item {
        id: pack

        property string style_name: ""
        property string user_dir: ""
        property string choice: ""
        readonly property var game: root.games[pack.choice] || null

        readonly property var shipped_urls: root.listing(shipped)
        readonly property var user_urls: root.listing(mine)
        readonly property var chosen_urls: pack.game ? (root.game_urls[pack.choice] || ({})) : root.listing(other)

        // The user's files beat the chosen pack, which beats the style's own.
        function find(base, exts) {
            const chosen_base = pack.game ? pack.game.names[base] : base;
            for (const [set, name] of [[pack.user_urls, base], [pack.chosen_urls, chosen_base], [pack.shipped_urls, base]]) {
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
            // A game pack takes no overrides; otherwise they belong to the chosen pack.
            folder: "file://" + pack.user_dir + "/" + (pack.game ? "none" : pack.choice || pack.style_name || "none")
            nameFilters: ["*.wav", "*.ogg", "*.mp3"]
            showDirs: false
        }

        FolderListModel {
            id: other
            folder: Qt.resolvedUrl("../sounds/" + (!pack.game && pack.choice ? pack.choice : "none"))
            nameFilters: ["*.wav", "*.ogg", "*.mp3"]
            showDirs: false
        }
    }

    Instantiator {
        id: game_dirs
        model: Object.keys(root.games)
        delegate: QtObject {
            id: game_dir
            required property string modelData
            readonly property string key: game_dir.modelData
            readonly property var primary_urls: root.listing(primary)
            readonly property var urls: Object.keys(game_dir.primary_urls).length > 0 ? game_dir.primary_urls : root.listing(legacy)

            readonly property FolderListModel primary: FolderListModel {
                folder: root.games[game_dir.modelData].dir
                nameFilters: ["*.wav", "*.ogg", "*.mp3"]
                showDirs: false
            }

            readonly property FolderListModel legacy: FolderListModel {
                folder: root.games[game_dir.modelData].legacy_dir || Qt.resolvedUrl("../sounds/none")
                nameFilters: ["*.wav", "*.ogg", "*.mp3"]
                showDirs: false
            }
        }
    }

    Pack { id: ui_pack; user_dir: root.user_dir; style_name: Style.saved_name; choice: root.pack_for(Style.saved_name) }
    Pack { id: login_pack; user_dir: root.user_dir; style_name: root.login_name }
    Pack { id: music_pack; user_dir: root.user_dir; style_name: root.music_on ? root.music_name : "" }

    // One pw-play per effect, a few at once: an idle mpv opened a new stream per file and dropped short or fast-repeated sounds.
    Instantiator {
        id: voices
        model: 4
        delegate: Process {
            id: voice_proc
            property var next: null

            function play(command) {
                if (voice_proc.running) {
                    voice_proc.next = command;
                    voice_proc.signal(15);
                    return;
                }
                voice_proc.command = command;
                voice_proc.running = true;
            }

            onExited: {
                if (!voice_proc.next) return;
                voice_proc.command = voice_proc.next;
                voice_proc.next = null;
                voice_proc.running = true;
            }
        }
    }

    MpvProcess {
        wanted: root.music_on && root.music_url !== "" && (root.lock_armed || root.music_level > 0)
        args: ["--loop-file=inf", root.music_url]
        volume: root.music_volume * root.music_level
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
                const music_saved = data.music_volume !== undefined ? data.music_volume : data.volume;
                const fx_saved = data.fx_volume !== undefined ? data.fx_volume : data.volume;
                if (root.volumes.indexOf(music_saved) >= 0) root.music_volume = music_saved;
                if (root.volumes.indexOf(fx_saved) >= 0) root.fx_volume = fx_saved;
                if (typeof data.pack === "string" && (Style.names.indexOf(data.pack) >= 0 || data.pack in root.extra_packs || data.pack in root.games)) root.choice = data.pack;
            } catch (e) {
                console.warn("ThemeAudio: invalid audio.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }

    Component.onCompleted: state_file.reload()
}
