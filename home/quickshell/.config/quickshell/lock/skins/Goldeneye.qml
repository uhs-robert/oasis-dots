// home/quickshell/.config/quickshell/lock/skins/Goldeneye.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../../theme"
import "goldeneye" as GE
import "../../theme/Watch.js" as Watch

// GoldenEye 007's pause watch: the arm lifts and the view zooms into the dial; the panel takes the user and password, OPTIONS RESTART POWEROFF sit under the header.
Item {
    id: root

    property var ctx: null
    // Set by the host to this surface's output, which picks its desktop screenshot.
    property string screen_name: ""
    readonly property int unlock_ms: 1600

    readonly property bool animate: !!root.ctx && root.ctx.animate
    // The screensaver phase is treated as idle.
    readonly property string phase: root.ctx && root.ctx.phase !== "saver" ? root.ctx.phase : "idle"
    readonly property bool login: !!root.ctx && root.ctx.login === true
    readonly property bool motion: root.animate && !!root.ctx && root.ctx.sound === true

    property FileView version_file: FileView {
        path: Qt.resolvedUrl("../../VERSION")
        blockLoading: true
        printErrors: false
    }
    readonly property string version: root.version_file.text().trim() || "0.0"
    readonly property string data_path: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/quickshell/goldeneye-frames"
    readonly property string local_dir: Qt.resolvedUrl("goldeneye/frames").toString().replace(/\/$/, "")
    property FileView data_count: FileView {
        path: root.data_path + "/count.txt"
        blockLoading: true
        printErrors: false
    }
    property FileView local_count: FileView {
        path: Qt.resolvedUrl("goldeneye/frames/count.txt")
        blockLoading: true
        printErrors: false
    }
    readonly property bool data_has_frames: (parseInt(root.data_count.text()) || 0) > 0
    readonly property string frames_dir: root.data_has_frames ? "file://" + root.data_path : root.local_dir
    readonly property int n_frames: parseInt((root.data_has_frames ? root.data_count : root.local_count).text()) || 0

    readonly property bool has_music: true
    readonly property bool sound_on: !!root.ctx && root.ctx.sound === true
    readonly property bool owns_sound: root.sound_on && root.ctx.sound_owner === root
    readonly property bool music_on: root.owns_sound && root.ctx.music !== false && root.ctx.music_armed !== false && root.phase !== "unlock"
    property bool dying: false
    property bool heard_unlock: false
    property int heard_typed: 0

    readonly property bool can_step: !!root.ctx && "scene" in root.ctx
    readonly property string scene: root.can_step ? root.ctx.scene : ""
    readonly property int typed: root.ctx ? root.ctx.buffer_length : 0
    readonly property bool checking: !!root.ctx && root.ctx.checking
    readonly property bool granted: root.phase === "unlock"
    readonly property bool wrong: root.phase === "wrong"
    readonly property string user_name: root.ctx ? root.ctx.user : ""
    readonly property string host: root.ctx ? root.ctx.host || "" : ""
    readonly property date now: root.animate ? new Date(root.tick) : root.ctx ? root.ctx.now : new Date()
    property real tick: Date.now()

    // The row under the header and the Options list keep their cursor and note in the scene as "nav:<item>:<note>" and "opt:<item>:<note>".
    readonly property var nav_items: ["options", "reboot", "poweroff"]
    readonly property var nav_labels: ({ options: "OPTIONS", reboot: "RESTART", poweroff: "POWEROFF" })
    readonly property var power_words: ({ reboot: "restart", poweroff: "power off" })
    readonly property bool in_nav: root.scene.startsWith("nav:")
    readonly property string nav_item: root.in_nav ? root.scene.split(":")[1] : ""
    readonly property string nav_note: root.in_nav ? (root.scene.split(":")[2] || "") : ""
    readonly property var opt_items: root.login ? ["session", "safe", "text", "firmware", "back"] : ["firmware", "back"]
    readonly property bool in_options: root.scene.startsWith("opt:")
    readonly property string opt_item: root.in_options ? root.scene.split(":")[1] : ""
    readonly property string opt_note: root.in_options ? (root.scene.split(":")[2] || "") : ""
    readonly property var opt_words: ({ firmware: "firmware", text: "text login" })

    function opt_label(item) {
        switch (item) {
        case "session": return "SESSION " + (root.ctx && "session_name" in root.ctx ? root.ctx.session_name : "");
        case "safe": return "SAFE SESSION";
        case "text": return "TEXT LOGIN";
        case "firmware": return "FIRMWARE SETUP";
        default: return "BACK";
        }
    }

    readonly property var users: {
        const list = root.ctx && Array.isArray(root.ctx.users) && root.ctx.users.length > 0 ? root.ctx.users : [{ name: root.user_name, full: "" }];
        return list.slice(0, 5);
    }
    readonly property int user_index: Math.max(0, root.users.findIndex(u => u.name === root.user_name))
    readonly property int user_sel: root.scene.startsWith("user:") ? Math.min(root.users.length - 1, parseInt(root.scene.split(":")[1]) || 0) : root.user_index

    // [text, tone] for the second line; tone is "", "red" or "dim".
    readonly property var status: {
        const c = root.ctx;
        if (!c) return ["", ""];
        if (root.granted) return ["ACCESS GRANTED", ""];
        if (root.in_options) {
            if (root.opt_note === "armed") return ["ENTER AGAIN FOR " + (root.opt_words[root.opt_item] || "THIS").toUpperCase(), "red"];
            if (root.opt_note === "preview") return ["PREVIEW: NO " + (root.opt_words[root.opt_item] || "ACTION").toUpperCase(), "dim"];
            if (root.opt_note === "running") return [(root.opt_words[root.opt_item] || "WORKING").toUpperCase() + "...", ""];
            return ["OPTIONS", ""];
        }
        if (root.in_nav) {
            const w = (root.power_words[root.nav_item] || "").toUpperCase();
            if (root.nav_note === "armed") return ["ENTER AGAIN TO " + w, "red"];
            if (root.nav_note === "preview") return ["PREVIEW: NO " + w, "dim"];
            if (root.nav_note === "running") return [w + "...", ""];
        }
        if (c.prompt) return [c.prompt, ""];
        if (root.checking) return ["VERIFYING...", ""];
        if (root.wrong) {
            const msg = c.message !== "" && c.message !== "Wrong password" ? c.message : "ACCESS DENIED";
            return [msg.toUpperCase() + (c.fail_count > 1 ? " X" + c.fail_count : ""), "red"];
        }
        if (c.caps_lock) return ["CAPS LOCK ON", "red"];
        return [(root.host !== "" ? root.host.toUpperCase() : "STATUS") + ": " + (root.login ? "LOGIN" : "LOCKED"), ""];
    }

    // The Watch colours option reaches the skin on the ctx; Classic is the fixed green, and a ctx without the field stays Classic.
    readonly property bool tinted: !!root.ctx && root.ctx.watch_colors === "Theme"
    readonly property color hue_src: root.ctx && root.ctx.tint !== "primary" ? root.ctx.tint_base : Theme.theme_primary
    readonly property var ramp: Watch.theme_ramp(Math.max(0, root.hue_src.hslHue), Watch.sat_of(root.hue_src), [Theme.bg_surface.r, Theme.bg_surface.g, Theme.bg_surface.b], [Theme.bg_mantle.r, Theme.bg_mantle.g, Theme.bg_mantle.b], 0.8, [0, 0, 0])

    function rgba(a) {
        return Qt.rgba(a[0], a[1], a[2], a.length > 3 ? a[3] : 1);
    }

    readonly property color green: root.tinted ? root.rgba(root.ramp.lit) : Watch.green
    readonly property color green_dim: root.tinted ? root.rgba(root.ramp.dim) : Watch.green_dim
    readonly property color green_mid: root.tinted ? root.rgba(root.ramp.mid) : Watch.green_mid
    readonly property color red: root.tinted ? Theme.error : Watch.red
    readonly property color bar_on: root.tinted ? root.rgba(root.ramp.bar_on) : Watch.bar_on
    readonly property color bar_off: root.tinted ? root.rgba(root.ramp.bar_off) : Watch.bar_off
    readonly property color tile_on: root.tinted ? root.rgba(root.ramp.tile_on) : "#0c3a14"
    readonly property color tile_off: root.tinted ? root.rgba(root.ramp.tile_off) : "#06200a"
    readonly property color panel_top: root.tinted ? root.rgba(root.ramp.panel_top) : Qt.rgba(Watch.panel_top[0], Watch.panel_top[1], Watch.panel_top[2], Watch.panel_top[3])
    readonly property color panel_bottom: root.tinted ? root.rgba(root.ramp.panel_bottom) : Qt.rgba(Watch.panel_bottom[0], Watch.panel_bottom[1], Watch.panel_bottom[2], Watch.panel_bottom[3])
    readonly property string head_font: Watch.head_font
    readonly property string mono_font: Watch.mono_font
    readonly property string digit_font: Watch.digit_font

    // intro_t runs 0 (black) to 1 (the settled face); frames play over its first 88% and the face fades in after.
    property real intro_t: 1
    property bool intro_busy: false
    // Loaded while the intro runs and from the first key on, so the unlock can start at once.
    readonly property bool frames_on: root.has_frames && root.motion && (root.intro_busy || root.typed > 0 || root.checking || root.granted)
    property int motion_dir: 0
    readonly property bool has_frames: root.n_frames > 0
    readonly property int frame_at: Math.max(0, Math.min(root.n_frames - 1, Math.floor(root.intro_t / 0.88 * root.n_frames)))
    readonly property real face_alpha: root.has_frames ? Math.max(0, Math.min(1, (root.intro_t - 0.84) / 0.16)) : root.intro_t

    readonly property string backdrop_file: root.ctx && root.ctx.backdrops && !root.login ? root.ctx.backdrops[root.screen_name] || "" : ""
    readonly property real backdrop_alpha: root.has_frames ? 1 - root.ease(0.42, 0.8, root.intro_t) : 0

    property real burst_level: 0
    property int noise_step: 0
    property int burst_interval: 30000
    readonly property bool burst_ok: root.animate && root.phase !== "unlock" && root.intro_t >= 1 && !root.in_options

    function sfx(name) {
        if (root.owns_sound && audio_loader.item) audio_loader.item.play(name);
    }

    function cue(name) {
        if (root.sound_on) root.ctx.cue(name);
    }

    function claim_sound() {
        if (root.sound_on && !root.dying && !root.ctx.sound_owner) root.ctx.sound_owner = root;
    }

    function run_burst() {
        if (!burst_anim.running) burst_anim.restart();
    }

    function ease(a, b, v) {
        const t = Math.max(0, Math.min(1, (v - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    // Starts the frames once they have loaded (or 600 ms have passed) so the first frame is not black.
    function play_motion(dir) {
        root.motion_dir = dir;
        root.intro_busy = dir > 0 && root.has_frames;
        frames_wait.since = Date.now();
        frames_wait.cap = dir > 0 ? 600 : 250;
        if (root.has_frames && !root.frames_ready()) frames_wait.restart();
        else root.begin_motion();
    }

    function frames_ready() {
        return !!frames_loader.item && frames_loader.item.ready >= root.n_frames * 2;
    }

    function begin_motion() {
        const dir = root.motion_dir;
        frames_wait.stop();
        motion_anim.stop();
        motion_anim.from = dir > 0 ? 0 : root.intro_t;
        motion_anim.to = dir > 0 ? 1 : 0;
        motion_anim.duration = dir > 0 ? 1400 : Math.round(1300 * root.intro_t);
        motion_anim.start();
        root.sfx(dir > 0 ? "lock_close" : "lock_open");
    }

    // Enter steps the cursor row (Up or Tab to reach it, Escape back), arrows move, a printable key still types.
    function handle_key(event) {
        const c = root.ctx;
        if (!root.can_step || c.buffer_length > 0 || c.checking || c.granted) return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        const k = event.key;
        const enter = !ctrl && (k === Qt.Key_Return || k === Qt.Key_Enter);
        const menu = root.in_nav || root.in_options;
        const letter = !ctrl && menu ? event.text : "";
        const left = k === Qt.Key_Left || letter === "h";
        const right = k === Qt.Key_Right || letter === "l";
        const up = k === Qt.Key_Up || letter === "k";
        const down = k === Qt.Key_Down || letter === "j";
        if (root.in_options) {
            if (up || down) {
                const at = root.opt_items.indexOf(root.opt_item);
                c.scene = "opt:" + root.opt_items[(at + (down ? 1 : root.opt_items.length - 1)) % root.opt_items.length];
                root.cue("select");
                return true;
            }
            if (enter) {
                root.opt_activate();
                return true;
            }
            if (k === Qt.Key_Escape) {
                c.scene = "nav:options";
                root.cue("back");
                return true;
            }
        } else if (root.in_nav) {
            if (left || right) {
                const at = root.nav_items.indexOf(root.nav_item);
                c.scene = "nav:" + root.nav_items[(at + (right ? 1 : root.nav_items.length - 1)) % root.nav_items.length];
                root.cue("select");
                return true;
            }
            if (enter) {
                root.nav_activate();
                return true;
            }
            if (k === Qt.Key_Escape || down) {
                c.scene = "";
                root.cue("back");
                return true;
            }
        } else {
            if (up || k === Qt.Key_Tab) {
                c.scene = "nav:options";
                root.cue("select");
                return true;
            }
            if (root.login && root.users.length > 1 && (left || right)) {
                const to = (root.user_sel + (k === Qt.Key_Right ? 1 : root.users.length - 1)) % root.users.length;
                c.scene = "user:" + to;
                root.cue("select");
                return true;
            }
            if (root.login && enter && root.users[root.user_sel] && root.users[root.user_sel].name !== root.user_name) {
                if (typeof c.user_request === "function") c.user_request(root.users[root.user_sel].name);
                c.scene = "";
                root.cue("confirm");
                return true;
            }
        }
        if (menu && !ctrl && event.text !== "" && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) c.scene = "";
        return false;
    }

    // Restart and Power off need a second press while the note shows; the ctx runs it unless it is a preview.
    function nav_activate() {
        const c = root.ctx;
        const item = root.nav_item;
        root.cue("confirm");
        if (item === "options") {
            c.scene = "opt:" + root.opt_items[0];
        } else if (root.nav_note === "armed") {
            c.scene = "nav:" + item + (c.power_live ? ":running" : ":preview");
            if (c.power_live) c.power_request(item);
        } else {
            c.scene = "nav:" + item + ":armed";
        }
    }

    // Firmware and text login need a second press while the note shows; previews only show a note.
    function opt_activate() {
        const c = root.ctx;
        const item = root.opt_item;
        root.cue(item === "back" ? "back" : "confirm");
        if (item === "back") {
            c.scene = "nav:options";
        } else if (item === "session") {
            if ("session_request" in c) c.session_request();
        } else if (item === "safe") {
            if ("safe_request" in c) c.safe_request();
            c.scene = "";
        } else if (root.opt_note === "armed") {
            c.scene = "opt:" + item + (c.power_live ? ":running" : ":preview");
            if (c.power_live) {
                if (item === "firmware") c.power_request("firmware");
                else if (item === "text" && "fallback_request" in c) c.fallback_request();
            }
        } else {
            c.scene = "opt:" + item + ":armed";
        }
    }

    clip: true
    Component.onCompleted: {
        root.claim_sound();
        if (root.granted) root.intro_t = 0;
        else if (root.motion && root.has_frames) {
            root.intro_t = 0;
            root.play_motion(1);
        } else if (root.motion) {
            root.sfx("lock_close");
        }
    }
    Component.onDestruction: {
        root.dying = true;
        if (root.ctx && root.ctx.sound_owner === root) root.ctx.sound_owner = null;
    }
    onPhaseChanged: {
        if (root.phase !== "unlock") return;
        if (!root.heard_unlock) {
            root.heard_unlock = true;
            motion_anim.stop();
            if (root.motion) root.play_motion(-1);
            else root.sfx("lock_open");
        }
    }

    Loader {
        id: audio_loader
        active: root.owns_sound
        source: Qt.resolvedUrl("goldeneye/GoldeneyeAudio.qml")
        onLoaded: {
            audio_loader.item.playing = Qt.binding(() => root.music_on);
            audio_loader.item.music_setting = Qt.binding(() => root.ctx.music_volume);
        }
    }

    Timer {
        id: note_timer
        interval: 4000
        onTriggered: {
            if (!root.can_step) return;
            if (root.in_options && root.opt_note !== "") root.ctx.scene = "opt:" + root.opt_item;
            else if (root.in_nav && root.nav_note !== "") root.ctx.scene = "nav:" + root.nav_item;
        }
    }

    Connections {
        target: root.ctx
        ignoreUnknownSignals: true
        function onSceneChanged() { note_timer.restart(); }
        function onBuffer_lengthChanged() {
            if (root.typed > 0) root.heard_unlock = false;
            const step = root.typed - root.heard_typed;
            root.heard_typed = root.typed;
            if (step === 1 || (step === -1 && !root.checking && !root.wrong)) root.sfx("type");
        }
        function onSound_ownerChanged() { root.claim_sound(); }
        function onCheckingChanged() {
            if (root.checking) root.sfx("confirm");
        }
        function onCue(name) {
            if (root.owns_sound && audio_loader.item) audio_loader.item.play(name);
        }
        function onRejected() {
            root.sfx("error");
            if (root.can_step) root.ctx.scene = "";
            if (root.animate) flash_anim.restart();
        }
    }

    Timer {
        id: frames_wait
        property real since: 0
        property int cap: 600
        interval: 40
        repeat: true
        onTriggered: {
            if (root.frames_ready() || Date.now() - frames_wait.since > frames_wait.cap) root.begin_motion();
        }
    }

    NumberAnimation {
        id: motion_anim
        target: root
        property: "intro_t"
        onFinished: if (root.motion_dir > 0) root.intro_busy = false
    }

    // Fires on the wall-clock second so every output ticks together.
    Timer {
        id: clock_timer
        function sync() {
            root.tick = Date.now();
            clock_timer.interval = 1000 - root.tick % 1000;
        }
        running: root.animate && root.intro_t >= 1
        repeat: true
        onRunningChanged: if (clock_timer.running) clock_timer.sync()
        onTriggered: clock_timer.sync()
    }

    Timer {
        running: root.burst_ok
        interval: root.burst_interval
        repeat: true
        onTriggered: root.run_burst()
    }

    Timer {
        id: noise_timer
        running: burst_anim.running
        interval: 70
        repeat: true
        onTriggered: root.noise_step += 1
    }

    SequentialAnimation {
        id: burst_anim
        ScriptAction { script: root.sfx("static") }
        NumberAnimation { target: root; property: "burst_level"; to: 1; duration: 120 }
        PauseAnimation { duration: 1260 }
        NumberAnimation { target: root; property: "burst_level"; to: 0; duration: 120 }
    }

    SequentialAnimation {
        id: flash_anim
        NumberAnimation { target: field; property: "flash"; from: 1; to: 0; duration: 700; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // The desktop as it was when the lock engaged, behind the arm until the watch fills the screen.
    Image {
        anchors.fill: parent
        source: root.backdrop_file !== "" && (root.intro_t < 1 || root.frames_on) ? root.backdrop_file : ""
        cache: false
        asynchronous: true
        fillMode: Image.Stretch
        opacity: root.backdrop_alpha
        visible: opacity > 0
    }

    // The 1020 x 720 plate scaled to fit, black around it.
    Item {
        id: stage
        readonly property real k: root.width > 0 && root.height > 0 ? Math.min(root.width / 1020, root.height / 720) : 1
        width: 1020
        height: 720
        x: (root.width - 1020) / 2
        y: (root.height - 720) / 2
        scale: stage.k

        Loader {
            id: frames_loader
            active: root.frames_on
            anchors.fill: parent
            sourceComponent: Item {
                id: sheet
                property int ready: 0
                readonly property int total: root.n_frames

                Repeater {
                    id: colors
                    model: sheet.total

                    Image {
                        id: arm
                        required property int index
                        source: root.frames_dir + "/arm_" + String(arm.index).padStart(2, "0") + ".jpg"
                        sourceSize.width: Math.round(Math.min(1020, 1020 * stage.k))
                        cache: false
                        asynchronous: true
                        visible: false
                        onStatusChanged: if (arm.status === Image.Ready) sheet.ready += 1
                    }
                }

                Repeater {
                    id: masks
                    model: sheet.total

                    Image {
                        id: cut
                        required property int index
                        source: root.frames_dir + "/mask_" + String(cut.index).padStart(2, "0") + ".png"
                        sourceSize.width: Math.round(Math.min(1020, 1020 * stage.k))
                        cache: false
                        asynchronous: true
                        visible: false
                        onStatusChanged: if (cut.status === Image.Ready) sheet.ready += 1
                    }
                }

                // Covers the whole output; past the frame's edge the arm runs on from its edge pixels until the watch fills the view.
                ShaderEffect {
                    width: root.width / stage.k
                    height: root.height / stage.k
                    x: (1020 - width) / 2
                    y: (720 - height) / 2
                    property real span_x: width / 1020
                    property real span_y: height / 720
                    property real reach: 1 - root.ease(0.55, 0.78, root.intro_t)
                    property real hue_shift: root.tinted && Watch.sat_of(root.hue_src) > 0 ? Math.max(0, root.hue_src.hslHue) * 6.283185 - 2.094395 : 0
                    property variant color_src: colors.count > 0 ? colors.itemAt(root.frame_at) : null
                    property variant mask_src: masks.count > 0 ? masks.itemAt(root.frame_at) : null
                    visible: !!color_src && !!mask_src && sheet.ready >= sheet.total * 2
                    fragmentShader: Qt.resolvedUrl("goldeneye/frame.frag.qsb")
                }
            }
        }

        Item {
            id: face
            anchors.fill: parent
            opacity: root.face_alpha

            Image {
                id: plate
                anchors.fill: parent
                source: root.has_frames ? root.frames_dir + "/plate.jpg" : ""
                sourceSize.width: Math.round(Math.min(1020, 1020 * stage.k))
                cache: false
                asynchronous: true
                visible: root.has_frames
            }

            Loader {
                anchors.fill: parent
                active: !root.has_frames
                sourceComponent: Bezel {}
            }

            Panel {}

            GE.WatchHands {
                id: hands
                now: root.now
                opacity: root.in_options || root.login ? 0.3 : 1
            }

            ShaderEffectSource {
                id: hands_src
                sourceItem: hands
                sourceRect: Qt.rect(190, 118, 640, 485)
                live: burst_anim.running
                hideSource: false
                visible: false
            }

            ShaderEffect {
                x: 190
                y: 118
                width: 640
                height: 485
                visible: root.burst_level > 0
                property variant source: hands_src
                property real level: root.burst_level
                property real tick: root.noise_step
                property real calm: 0
                property real tint_amt: root.tinted ? 1 : 0
                property color tint_col: root.green_mid
                fragmentShader: Qt.resolvedUrl("goldeneye/static.frag.qsb")
            }

            Item {
                id: texts
                anchors.fill: parent
                opacity: 1 - 0.35 * root.burst_level

                Text {
                    x: 255
                    width: 510
                    y: 134
                    horizontalAlignment: Text.AlignHCenter
                    text: "OASIS WATCH v" + root.version
                    color: root.green
                    font.family: root.head_font
                    font.pixelSize: 19
                    font.letterSpacing: 1
                    renderType: Text.QtRendering
                }

                Text {
                    x: 235
                    width: 550
                    y: 186
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.status[0]
                    color: root.status[1] === "red" ? root.red : root.status[1] === "dim" ? root.green_dim : root.green
                    font.family: root.head_font
                    font.pixelSize: 16
                    renderType: Text.QtRendering
                }

                Repeater {
                    model: root.nav_items

                    Item {
                        id: nav
                        required property string modelData
                        required property int index
                        readonly property bool on: root.nav_item === nav.modelData
                        x: 235 + nav.index * 170
                        y: 222
                        width: 150
                        height: 28

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.alpha(root.green, 0.22)
                            border.width: 1
                            border.color: Qt.alpha(root.green, 0.7)
                            visible: nav.on
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.nav_labels[nav.modelData]
                            color: nav.on ? root.green : root.green_mid
                            font.family: root.head_font
                            font.pixelSize: 15
                            renderType: Text.QtRendering
                        }
                    }
                }

                Item {
                    id: options
                    visible: root.in_options
                    x: 290
                    y: 290
                    width: 440

                    Repeater {
                        model: root.opt_items

                        Item {
                            id: opt
                            required property string modelData
                            required property int index
                            readonly property bool on: root.opt_item === opt.modelData
                            y: opt.index * 38
                            width: 440
                            height: 32

                            Rectangle {
                                anchors.fill: parent
                                color: Qt.alpha(root.green, 0.22)
                                border.width: 1
                                border.color: Qt.alpha(root.green, 0.7)
                                visible: opt.on
                            }

                            Text {
                                anchors.centerIn: parent
                                text: root.opt_label(opt.modelData)
                                color: opt.on ? root.green : root.green_mid
                                font.family: root.head_font
                                font.pixelSize: 16
                                renderType: Text.QtRendering
                            }
                        }
                    }
                }

                Item {
                    id: picker
                    visible: root.login && !root.in_options

                    Repeater {
                        model: root.users

                        Item {
                            id: person
                            required property var modelData
                            required property int index
                            readonly property bool on: root.user_sel === person.index
                            readonly property var urls: root.ctx && typeof root.ctx.face_urls === "function" ? root.ctx.face_urls(person.modelData.name) : []
                            property int attempt: 0
                            x: 510 + (person.index - (root.users.length - 1) / 2) * 140 - 48
                            y: 282
                            width: 96
                            height: 130
                            opacity: person.on ? 1 : 0.85
                            onUrlsChanged: person.attempt = 0

                            Rectangle {
                                width: 96
                                height: 96
                                color: person.on ? root.tile_on : root.tile_off
                                border.width: person.on ? 3 : 2
                                border.color: person.on ? root.green : root.green_mid

                                Rectangle {
                                    visible: face_image.status !== Image.Ready
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 22
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: root.green_mid
                                }

                                Rectangle {
                                    visible: face_image.status !== Image.Ready
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 58
                                    width: 56
                                    height: 36
                                    radius: 18
                                    color: root.green_mid
                                }

                                Image {
                                    id: face_image
                                    anchors.fill: parent
                                    anchors.margins: person.on ? 3 : 1
                                    source: person.urls[person.attempt] || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    onStatusChanged: if (face_image.status === Image.Error && person.attempt < person.urls.length) person.attempt += 1
                                }
                            }

                            Text {
                                y: 104
                                width: 96
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: person.modelData.name.toUpperCase()
                                color: person.on ? root.green : root.green_mid
                                font.family: root.mono_font
                                font.pixelSize: 16
                                renderType: Text.QtRendering
                            }
                        }
                    }
                }

                Item {
                    id: field
                    property real flash: 0
                    readonly property color tone: root.wrong ? root.red : Qt.tint(root.green, Qt.alpha(root.red, field.flash))
                    x: 250
                    y: 492
                    width: 250
                    height: 70

                    Text {
                        width: field.width
                        elide: Text.ElideRight
                        text: root.user_name.toUpperCase()
                        color: field.tone
                        font.family: root.head_font
                        font.pixelSize: 15
                        renderType: Text.QtRendering
                    }

                    Rectangle {
                        y: 52
                        width: field.width
                        height: 1
                        color: Qt.alpha(field.tone, 0.6)
                    }

                    Row {
                        y: 31
                        spacing: 4

                        Repeater {
                            model: Math.min(root.typed, 16)

                            Rectangle {
                                width: 11
                                height: 14
                                color: field.tone
                            }
                        }

                        Text {
                            visible: root.typed > 16
                            text: "+" + (root.typed - 16)
                            color: field.tone
                            font.family: root.mono_font
                            font.pixelSize: 16
                            renderType: Text.QtRendering
                        }

                        Rectangle {
                            visible: root.typed === 0 && !root.checking && !root.in_nav && !root.in_options
                            width: 11
                            height: 3
                            y: 11
                            color: Qt.alpha(field.tone, 0.8)
                            opacity: 1

                            SequentialAnimation on opacity {
                                running: root.animate && root.typed === 0 && root.intro_t >= 1
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.15; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                    }
                }

                Text {
                    x: 560
                    width: 200
                    y: 502
                    horizontalAlignment: Text.AlignRight
                    text: Qt.formatTime(root.now, "HH:mm")
                    color: root.green
                    opacity: 0.8
                    font.family: root.digit_font
                    font.pixelSize: 30
                    renderType: Text.QtRendering
                }

                Repeater {
                    model: 5

                    Rectangle {
                        id: bar
                        required property int index
                        x: 300 + bar.index * 88
                        y: 576
                        width: 70
                        height: 14
                        color: bar.index < Math.max(1, root.granted ? 5 : Math.min(5, root.typed)) ? root.bar_on : root.bar_off
                    }
                }
            }
        }
    }

    // The panel's translucent green octagon over the bezel: the dots and the white bars show through its edge.
    component Panel: Item {
        id: panel
        readonly property var edge: [[294, 118], [272, 144], [250, 168], [232, 200], [212, 232], [200, 264], [194, 296], [188, 340], [188, 380], [194, 420], [204, 460], [214, 492], [234, 524], [251, 556], [274, 580], [294, 603]]
        readonly property var outline: panel.edge.map(p => Qt.point(p[0], p[1])).concat(panel.edge.slice().reverse().map(p => Qt.point(1020 - p[0], p[1])))
        anchors.fill: parent

        Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 118
                    x2: 0
                    y2: 603
                    GradientStop { position: 0; color: root.panel_top }
                    GradientStop { position: 1; color: root.panel_bottom }
                }
                PathPolyline { path: panel.outline }
            }
        }

        Rectangle {
            x: 188
            y: 347
            width: 62
            height: 26
            color: Qt.rgba(0.7, 0.78, 0.7, 0.26)
        }

        Rectangle {
            x: 770
            y: 347
            width: 62
            height: 26
            color: Qt.rgba(0.7, 0.78, 0.7, 0.26)
        }
    }

    // Without the plate: its bezel facets, arcs, ticks, bars and studs, drawn to the same geometry.
    component Bezel: ShaderEffect {
        property real soft: Math.max(1.5, 1 / stage.k)
        property real rows: 720
        property real minutes: 0
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("goldeneye/plate.frag.qsb")
    }
}
