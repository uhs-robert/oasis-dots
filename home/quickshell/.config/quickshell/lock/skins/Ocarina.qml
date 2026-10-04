// home/quickshell/.config/quickshell/lock/skins/Ocarina.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Io

// Ocarina of Time: the title over a clock-driven sky; PRESS START leads to file select, then name entry takes the password.
Item {
    id: root

    property var ctx: null
    readonly property int unlock_ms: 1600

    readonly property bool animate: !!root.ctx && root.ctx.animate
    readonly property string phase: root.ctx ? root.ctx.phase : "idle"

    property FileView os_release: FileView {
        path: "/etc/os-release"
    }
    readonly property string distro: {
        const m = root.os_release.text().match(/^NAME="?([^"\n]*)"?$/m);
        return m ? m[1] : "Linux";
    }

    readonly property bool has_music: true
    readonly property bool sound_on: !!root.ctx && root.ctx.sound === true
    readonly property bool owns_sound: root.sound_on && root.ctx.sound_owner === root
    // The title theme plays only on the login screen; the fountain from the white fade until unlock, the title or the saver.
    readonly property string music_track: {
        if (!root.owns_sound || root.ctx.music === false || root.ctx.music_armed === false || root.phase === "saver" || root.phase === "unlock") return "";
        if (root.screen === "file" || root.screen === "name") return "fairy";
        return root.ctx.login === true ? "title" : "";
    }
    property int heard_typed: 0
    // Set once the accept sound has played for this attempt; a new password clears it.
    property bool heard_unlock: false
    property bool dying: false

    readonly property bool can_step: !!root.ctx && "scene" in root.ctx
    readonly property string scene: root.can_step ? root.ctx.scene : ""
    readonly property int typed: root.ctx ? root.ctx.buffer_length : 0
    readonly property bool lit: root.scene === "lit"
    readonly property bool checking: !!root.ctx && root.ctx.checking
    // title, file, name or saver. Options counts as "file" too: it's a floating panel over file select.
    readonly property string screen: {
        if (root.phase === "saver") return "saver";
        if (root.phase === "unlock" || root.typed > 0 || root.checking) return "name";
        if (root.scene === "file" || root.scene.startsWith("file:") || root.scene.startsWith("opt:")) return "file";
        return root.scene === "name" ? "name" : "title";
    }

    // File select's cursor and note live in the scene as "file:<item>:<note>" so every output agrees.
    readonly property var file_items: ["file1", "reboot", "poweroff", "options"]
    readonly property string file_item: root.scene.startsWith("file:") ? root.scene.split(":")[1] : "file1"
    readonly property string file_note: root.scene.startsWith("file:") ? (root.scene.split(":")[2] || "") : ""
    readonly property var power_words: ({ reboot: "reboot", poweroff: "shut down" })

    // The Options menu's cursor and note live in the scene as "opt:<item>:<note>". Greeter-only entries are hidden on the lock.
    readonly property bool ctx_login: !!root.ctx && root.ctx.login === true
    readonly property var opt_items: root.ctx_login ? ["session", "safe", "text", "firmware", "back"] : ["firmware", "back"]
    readonly property bool in_options: root.scene.startsWith("opt:")
    readonly property string opt_item: root.in_options ? root.scene.split(":")[1] : (root.opt_items[0] || "")
    readonly property string opt_note: root.in_options ? (root.scene.split(":")[2] || "") : ""
    readonly property var opt_words: ({ firmware: "reboot to firmware setup", text: "switch to the text login" })

    function opt_label(item) {
        switch (item) {
        case "session": return "Session: " + (root.ctx && "session_name" in root.ctx ? root.ctx.session_name : "");
        case "safe": return "Safe session";
        case "text": return "Text login";
        case "firmware": return "Firmware setup";
        default: return "Back";
        }
    }

    // The title stays on show under the PRESS START fade to white; the view follows `screen` otherwise.
    property bool holding_title: false
    readonly property string view: root.holding_title ? "title" : root.screen
    property string last_screen: "title"

    readonly property string tod: {
        const d = root.ctx ? root.ctx.now : new Date();
        const h = d.getHours() + d.getMinutes() / 60;
        if (h >= 5 && h < 10) return "dawn";
        if (h >= 10 && h < 14) return "day";
        if (h >= 14 && h < 20.5) return "dusk";
        return "night";
    }
    readonly property var palettes: ({
        dawn: { sky: ["#2c3466", "#b46a84", "#f6a65c"], hills: ["#6a4a66", "#33222e", "#160e12"] },
        day: { sky: ["#2a6ad0", "#6aa6ea", "#cfe6f7"], hills: ["#6f8fb0", "#3f6a30", "#1e3a14"] },
        dusk: { sky: ["#2e2f52", "#6a5f7e", "#c89a8a"], hills: ["#3a3550", "#221f30", "#110f18"] },
        night: { sky: ["#02040d", "#0b1230", "#1f2a55"], hills: ["#151b33", "#0b0f1e", "#04060c"] }
    })
    // One phase (0..1 per cycle) drives the whole sky: the sun crosses its arc over -0.03..0.40 (dawn, day, dusk), the moon over 0.37..1.03 (night).
    // It starts at the clock's time of day and runs on a wall clock; the animation only ticks while the title shows. Without animate it stays pinned to the clock.
    readonly property int cycle_ms: 150000
    property real sky_phase: 0
    property real cycle_start: 0
    property real cycle_epoch: 0
    property bool cycle_armed: false
    readonly property bool sky_live: root.animate && (root.view === "title" || root.view === "saver")
    readonly property var tod_phase: ({ dawn: 0.0692, day: 0.185, dusk: 0.3008, night: 0.7 })
    readonly property real cyc: root.animate ? root.sky_phase - Math.floor(root.sky_phase) : root.tod_phase[root.tod]
    // v is each body's time across the sky, 0 rising to 1 setting; t is its eased place on the arc, slow near the horizons and quick over the top.
    readonly property real sun_v: (root.cyc + 0.03) / 0.43
    readonly property real moon_v: ((root.cyc - 0.37 + 1) % 1) / 0.66
    readonly property real sun_t: root.glide(root.sun_v)
    readonly property real moon_t: root.glide(root.moon_v)
    readonly property point sun_at: root.arc(root.sun_t)
    readonly property point moon_at: root.arc(root.moon_t)
    readonly property real sun_alpha: root.sun_v >= 0 && root.sun_v <= 1 ? 1 : 0
    readonly property real moon_alpha: root.moon_v >= 0 && root.moon_v <= 1 ? 1 : 0
    // Day holds while the sun is within 60 degrees of straight up on its arc (10 to 2 o'clock).
    readonly property real sun_angle: Math.abs(root.sun_t - 0.5) * 180
    readonly property real day_w: root.sun_alpha > 0 ? 1 - root.ease(55, 65, root.sun_angle) : 0
    readonly property real night_w: root.sun_alpha === 0 ? 1 : root.sun_t < 0.5 ? 1 - root.ease(0, 0.02, root.sun_t) : root.ease(0.98, 1, root.sun_t)
    readonly property var shade_keys: ({ dawn: root.shades("dawn"), day: root.shades("day"), dusk: root.shades("dusk"), night: root.shades("night") })
    property color sky0: root.blend("sky", 0)
    property color sky1: root.blend("sky", 1)
    property color sky2: root.blend("sky", 2)
    property color hill0: root.blend("hills", 0)
    property color hill1: root.blend("hills", 1)
    property color hill2: root.blend("hills", 2)
    readonly property real star_alpha: root.night_w + (1 - root.night_w) * (1 - root.day_w) * 0.2
    readonly property real cloud_alpha: 1 - 0.55 * root.night_w
    readonly property real day_cloud_alpha: root.day_w * (1 - root.night_w)

    function ease(a, b, v) {
        const t = Math.max(0, Math.min(1, (v - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    function shades(t) {
        return { sky: root.palettes[t].sky.map(root.rgb), hills: root.palettes[t].hills.map(root.rgb) };
    }

    function rgb(hex) {
        return [1, 3, 5].map(i => parseInt(hex.substr(i, 2), 16) / 255);
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    // The low sun's colours (dawn before noon, dusk after), toward day as it climbs, toward night as it sets.
    function blend(kind, i) {
        const low = root.shade_keys[root.sun_v < 0.5 ? "dawn" : "dusk"][kind][i], day = root.shade_keys.day[kind][i], night = root.shade_keys.night[kind][i];
        return Qt.rgba(...[0, 1, 2].map(c => root.lerp(root.lerp(low[c], day[c], root.day_w), night[c], root.night_w)), 1);
    }

    // Left horizon to right horizon behind the hills; the peak (v = 0.5) sits right of the logo.
    function glide(v) {
        const c = Math.cos(Math.PI * Math.max(0, Math.min(1, v)));
        return 0.5 - 0.5 * Math.sign(c) * Math.pow(Math.abs(c), 0.6);
    }

    function arc(v) {
        const t = Math.max(0, v);
        return Qt.point(800 - 760 * Math.cos(Math.PI * Math.pow(t, 0.515)), 780 - 650 * Math.sin(Math.PI * t));
    }

    function start_cycle() {
        root.cycle_start = root.tod_phase[root.tod];
        root.cycle_epoch = Date.now();
        root.sync_cycle();
    }

    // Catches the phase up with the wall clock, then lets the animation run on from there.
    function sync_cycle() {
        root.cycle_armed = false;
        if (!root.sky_live) return;
        root.sky_phase = root.cycle_start + (Date.now() - root.cycle_epoch) / root.cycle_ms;
        sky_anim.from = root.sky_phase;
        sky_anim.to = root.sky_phase + 1;
        root.cycle_armed = true;
    }

    onAnimateChanged: if (root.animate) root.start_cycle()
    onSky_liveChanged: root.sync_cycle()

    NumberAnimation on sky_phase {
        id: sky_anim
        running: root.sky_live && root.cycle_armed
        duration: root.cycle_ms
        loops: Animation.Infinite
    }

    readonly property string ui_font: "Rounded Mplus 1c"
    readonly property string key_font: "Belleza"

    readonly property var stars: root.scatter(5, 90, rnd => ({ x: rnd() * 1600, y: Math.pow(rnd(), 1.5) * 520, r: 0.8 + rnd() * 1.5, a: 0.35 + rnd() * 0.6 }))
    readonly property var drift_clouds: root.scatter(17, 10, rnd => root.cloud(rnd, 2, 26))
    readonly property var menu_puffs: root.scatter(23, 12, rnd => {
        const rx = 90 + rnd() * 170;
        return { x: rnd() * 1280, y: rnd() * 560, rx: rx, ry: rx * (0.22 + rnd() * 0.2), a: 0.12 + rnd() * 0.16 };
    })

    readonly property var key_rows: ["ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "abcdefghijklm", "nopqrstuvwxyz", "1234567890.–"]
    readonly property var key_baselines: [274, 324, 373, 422, 464]
    readonly property var keys: {
        const out = [];
        root.key_rows.forEach((row, r) => row.split("").forEach((ch, c) => out.push({ ch: ch, r: r, c: c })));
        return out;
    }
    // Moves with the length only, never with what was typed.
    readonly property int selected_key: root.phase === "unlock" || root.phase === "wrong" ? -1 : (root.typed * 23) % root.keys.length
    readonly property int marks: root.phase === "unlock" || root.checking ? 8 : Math.min(root.typed, 8)

    function scatter(seed, n, make) {
        let s = seed;
        const rnd = () => {
            s = (s * 16807) % 2147483647;
            return (s - 1) / 2147483646;
        };
        const out = [];
        for (let i = 0; i < n; i++) out.push(make(rnd));
        return out;
    }

    // Stage units: 1 cqw of the 1600 wide title is 16.
    function cloud(rnd, top, spread) {
        const w = (24 + rnd() * 30) * 16;
        return { x: (rnd() * 110 - 25) * 16, y: (top + rnd() * spread) * 16, w: w, h: w * (0.16 + rnd() * 0.1), dur: Math.round(90 + rnd() * 70) * 1000, lead: rnd() * 150 * 1000 };
    }

    // Enter or Space ignites the title, then steps to file select and name entry; Escape steps back; a printable key jumps to name entry and still types.
    function handle_key(event) {
        const c = root.ctx;
        if (!root.can_step || c.buffer_length > 0 || c.checking || c.granted) return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        if (c.scene === "name") {
            if (event.key === Qt.Key_Escape) {
                c.scene = "file";
                root.cue("cancel");
            }
            return false;
        }
        const on_file = root.screen === "file";
        const in_opts = root.in_options;
        if (on_file && !in_opts && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            const i = root.file_items.indexOf(root.file_item);
            const next = root.file_items[(i + (event.key === Qt.Key_Down ? 1 : root.file_items.length - 1)) % root.file_items.length];
            c.scene = next === "file1" ? "file" : "file:" + next;
            root.cue("move");
            return true;
        }
        if (in_opts && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            const items = root.opt_items;
            const i = items.indexOf(root.opt_item);
            const next = items[(i + (event.key === Qt.Key_Down ? 1 : items.length - 1)) % items.length];
            c.scene = "opt:" + next;
            root.cue("move");
            return true;
        }
        if (in_opts && !ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.cue("decide");
            root.opt_activate();
            return true;
        }
        if (in_opts && event.key === Qt.Key_Escape) {
            c.scene = "file:options";
            root.cue("cancel");
            return true;
        }
        if (!ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_Space && !in_opts && !on_file))) {
            root.cue(on_file ? "decide" : "start");
            if (on_file) root.file_activate();
            else c.scene = c.scene === "lit" ? "file" : "lit";
            return true;
        }
        if ((on_file || c.scene === "lit") && !in_opts && event.key === Qt.Key_Escape) {
            c.scene = "";
            root.cue("cancel");
            return true;
        }
        if (!ctrl && event.text !== "" && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) c.scene = "name";
        return false;
    }

    function cue(name) {
        if (root.sound_on) root.ctx.cue(name);
    }

    function claim_sound() {
        if (root.sound_on && !root.dying && !root.ctx.sound_owner) root.ctx.sound_owner = root;
    }

    // Reboot and Shut down need a second press while the note shows; the ctx runs it unless it is a preview.
    function file_activate() {
        const c = root.ctx;
        const item = root.file_item;
        if (item === "file1") {
            c.scene = "name";
        } else if (item === "options") {
            c.scene = "opt:" + root.opt_items[0];
        } else if (root.file_note === "armed") {
            c.scene = "file:" + item + (c.power_live ? ":running" : ":preview");
            if (c.power_live) c.power_request(item);
        } else {
            c.scene = "file:" + item + ":armed";
        }
    }

    // Firmware and text login need a second press while the note shows, like Reboot/Shut down; previews only show a note.
    function opt_activate() {
        const c = root.ctx;
        const item = root.opt_item;
        if (item === "back") {
            c.scene = "file:options";
        } else if (item === "session") {
            if ("session_request" in c) c.session_request();
        } else if (item === "safe") {
            if ("safe_request" in c) c.safe_request();
            c.scene = "name";
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
        root.start_cycle();
    }
    Component.onDestruction: {
        root.dying = true;
        if (root.ctx && root.ctx.sound_owner === root) root.ctx.sound_owner = null;
    }

    Loader {
        id: audio_loader
        active: root.owns_sound
        source: Qt.resolvedUrl("ocarina/OcarinaAudio.qml")
        onLoaded: {
            audio_loader.item.track = Qt.binding(() => root.music_track);
            audio_loader.item.music_setting = Qt.binding(() => root.ctx.music_volume);
        }
    }
    onPhaseChanged: {
        if (root.phase === "saver" && root.can_step) root.ctx.scene = "";
        if (root.phase === "unlock" && !root.heard_unlock && root.owns_sound && audio_loader.item) {
            root.heard_unlock = true;
            audio_loader.item.play("decide");
        }
    }
    onScreenChanged: {
        const from = root.last_screen;
        root.last_screen = root.screen;
        if (from === "title" && (root.screen === "file" || root.screen === "name") && root.animate) {
            root.holding_title = true;
            start_fade.restart();
        } else if (start_fade.running && root.screen !== "file" && root.screen !== "name") {
            start_fade.stop();
            root.holding_title = false;
            start_white.opacity = 0;
        }
    }

    Timer {
        id: note_timer
        interval: 4000
        onTriggered: {
            if (!root.can_step || root.screen !== "file") return;
            if (root.in_options) {
                if (root.opt_note !== "") root.ctx.scene = "opt:" + root.opt_item;
            } else if (root.file_note !== "") {
                root.ctx.scene = "file:" + root.file_item;
            }
        }
    }

    Connections {
        target: root.ctx
        ignoreUnknownSignals: true
        function onSceneChanged() { note_timer.restart(); }
        function onBuffer_lengthChanged() {
            if (root.owns_sound && root.typed > root.heard_typed && audio_loader.item) audio_loader.item.play("letter");
            root.heard_typed = root.typed;
            if (root.typed > 0) root.heard_unlock = false;
        }
        function onSound_ownerChanged() { root.claim_sound(); }
        function onCue(name) {
            if (root.owns_sound && audio_loader.item) audio_loader.item.play(name);
        }
        function onRejected() {
            if (root.owns_sound && audio_loader.item) audio_loader.item.play("error");
            if (root.can_step) root.ctx.scene = "name";
            if (root.animate) flash_anim.restart();
        }
    }

    // A design-space stage, scaled to cover its parent and centred (SVG "slice").
    component Stage: Item {
        id: stage
        property real design_w: 1600
        property real design_h: 900
        readonly property real k: stage.parent ? Math.max(stage.parent.width / stage.design_w, stage.parent.height / stage.design_h) : 1
        width: stage.design_w
        height: stage.design_h
        x: stage.parent ? (stage.parent.width - stage.design_w) / 2 : 0
        y: stage.parent ? (stage.parent.height - stage.design_h) / 2 : 0
        scale: stage.k
    }

    // Text set by its baseline (base_y); fit_w stretches it to exactly that width, max_w only squeezes it.
    component FitText: Text {
        id: fit
        property real x0: 0
        property real base_y: 0
        property real fit_w: 0
        property real max_w: 0
        property bool centered: false
        readonly property real sx: fit.implicitWidth <= 0 ? 1 : fit.fit_w > 0 ? fit.fit_w / fit.implicitWidth : fit.max_w > 0 ? Math.min(1, fit.max_w / fit.implicitWidth) : 1
        x: fit.centered ? fit.x0 - fit.implicitWidth * fit.sx / 2 : fit.x0
        y: fit.base_y - fit.baselineOffset
        renderType: Text.QtRendering
        transform: Scale { xScale: fit.sx }
    }

    // A radial fade filling an ellipse centred on (cx, cy).
    component Radial: Shape {
        id: radial
        property real cx: 0
        property real cy: 0
        property real rx: 10
        property real ry: radial.rx
        property color inner: "white"
        property color middle: radial.inner
        property real mid: 0.5
        property color outer: Qt.rgba(radial.inner.r, radial.inner.g, radial.inner.b, 0)
        x: radial.cx - radial.rx
        y: radial.cy - radial.rx
        width: radial.rx * 2
        height: radial.rx * 2
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.y: radial.rx; yScale: radial.ry / radial.rx }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: radial.rx
                centerY: radial.rx
                focalX: radial.rx
                focalY: radial.rx
                centerRadius: radial.rx
                focalRadius: 0
                GradientStop { position: 0; color: radial.inner }
                GradientStop { position: radial.mid; color: radial.middle }
                GradientStop { position: 1; color: radial.outer }
            }
            PathRectangle { width: radial.width; height: radial.height }
        }
    }

    component Pulse: SequentialAnimation {
        loops: Animation.Infinite
        NumberAnimation { from: 0.6; to: 1; duration: 550; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.6; duration: 550; easing.type: Easing.InOutSine }
    }

    // The cyan cursor orb.
    component Orb: Radial {
        inner: "#ffffff"
        middle: "#f2b8ffff"
        mid: 0.35
        outer: "#006ff0ff"
    }

    // A heading with the game's soft black halo.
    component Heading: Item {
        id: heading
        property string text
        property real x0
        property real base_y
        property int size
        property real fit_w

        FitText {
            x0: heading.x0 + 1
            base_y: heading.base_y + 2
            fit_w: heading.fit_w
            text: heading.text
            opacity: 0.85
            color: "#000000"
            style: Text.Outline
            styleColor: "#000000"
            font.family: root.ui_font
            font.weight: 800
            font.pixelSize: heading.size
        }

        FitText {
            x0: heading.x0
            base_y: heading.base_y
            fit_w: heading.fit_w
            text: heading.text
            color: "#fbfbf6"
            style: Text.Outline
            styleColor: "#0a0a0a"
            font.family: root.ui_font
            font.weight: 800
            font.pixelSize: heading.size
        }
    }

    // A raised plate or button face: drop shadow, gradient, stroke and a top highlight.
    component Plate: Item {
        id: plate
        property real r: 10
        property bool lit: false
        property bool button: false
        property real shadow_x: 4

        Rectangle {
            x: plate.button ? 3 : plate.shadow_x
            y: plate.button ? 6 : 4
            width: plate.width
            height: plate.height
            radius: plate.r
            color: plate.button ? "#a6081030" : "#99081030"
        }

        Rectangle {
            width: plate.width
            height: plate.height
            radius: plate.r
            border.width: plate.lit ? 4 : 2
            border.color: plate.lit ? "#dcfeff" : "#1a2a66"
            gradient: Gradient {
                GradientStop { position: 0; color: plate.lit ? "#a8c6f4" : plate.button ? "#7094e6" : "#7e9ff0" }
                GradientStop { position: plate.button ? 0.5 : 0.45; color: plate.lit ? "#7c9fe0" : plate.button ? "#4a6cca" : "#5478d8" }
                GradientStop { position: 1; color: plate.lit ? "#5476c8" : plate.button ? "#2c479e" : "#3656b8" }
            }
        }

        Rectangle {
            visible: plate.button
            x: 7
            y: 5
            width: plate.width - 14
            height: plate.height - 12
            radius: Math.max(0, plate.r - 5)
            color: "transparent"
            border.width: 2
            border.color: "#8cb4ccff"
        }

        Rectangle {
            visible: plate.button
            x: plate.r
            y: plate.height - 5
            width: plate.width - 2 * plate.r
            height: 4
            color: "#b316245e"
        }

        Rectangle {
            visible: !plate.button
            x: 7
            y: 3.5
            width: plate.width - 14
            height: 3
            color: "#b3c8dcff"
        }
    }

    // A menu pill; label_x0, label_x1 and base_y are in stage units.
    component Pill: Item {
        id: pill
        property string label
        property real label_x0
        property real label_x1
        property real base_y
        property bool lit: false
        property bool dot: false

        Item {
            visible: pill.lit
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                anchors.margins: -8
                radius: 28
                color: "transparent"
                border.width: 4
                border.color: "#599ffcff"
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -5
                radius: 25
                color: "transparent"
                border.width: 4
                border.color: "#9ffcff"
            }

            Pulse on opacity {
                running: root.animate && pill.lit
            }
        }

        Plate {
            anchors.fill: parent
            r: 20
            button: true
            lit: pill.lit
        }

        FitText {
            x0: pill.label_x0 - pill.x
            base_y: pill.base_y - pill.y
            fit_w: pill.label_x1 > pill.label_x0 ? pill.label_x1 - pill.label_x0 : 0
            max_w: pill.width - 2 * (pill.label_x0 - pill.x)
            text: pill.label
            color: pill.lit ? "#6d97a6" : "#0d1840"
            style: Text.Outline
            styleColor: pill.lit ? "#c8f4ff" : "#6f8fdc"
            font.family: root.ui_font
            font.weight: 800
            font.pixelSize: 58
        }

        Rectangle {
            visible: pill.dot
            x: 452 - pill.x - 4
            y: pill.height / 2 + 2 - 4
            width: 8
            height: 8
            radius: 4
            color: "#0d1840"
            border.width: 1.5
            border.color: "#8fb0f0"
        }
    }

    // The blue menu backdrop shared by file select and name entry.
    component MenuSky: Item {
        width: 1280
        height: 720

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 0
                    x2: 192
                    y2: 720
                    GradientStop { position: 0; color: "#050d26" }
                    GradientStop { position: 0.45; color: "#0c2466" }
                    GradientStop { position: 0.85; color: "#1640b8" }
                    GradientStop { position: 1; color: "#1c4ee0" }
                }
                PathRectangle { width: 1280; height: 720 }
            }
        }

        Repeater {
            model: root.menu_puffs

            Radial {
                required property var modelData
                cx: modelData.x
                cy: modelData.y
                rx: modelData.rx * 1.25
                ry: modelData.ry * 1.25
                inner: Qt.rgba(0.373, 0.525, 0.878, modelData.a)
                mid: 0.55
                outer: Qt.rgba(0.373, 0.525, 0.878, 0)
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 820
                    y1: 270
                    x2: 1060
                    y2: 450
                    GradientStop { position: 0; color: "#008fb0ff" }
                    GradientStop { position: 0.5; color: "#298fb0ff" }
                    GradientStop { position: 1; color: "#008fb0ff" }
                }
                PathSvg { path: "M1060 -40 L1420 -40 L880 760 L400 760 Z" }
            }
        }
    }

    // The game's 4:3 menu frame, fitted inside its parent; children use menu (1280x720) units, centred on the panel.
    component PanelFrame: Item {
        id: frame
        default property alias content: menu_space.data
        readonly property real k: frame.parent ? 0.94 * Math.min(frame.parent.width / 960, frame.parent.height / 720) : 1
        width: 960
        height: 720
        x: frame.parent ? (frame.parent.width - 960) / 2 : 0
        y: frame.parent ? (frame.parent.height - 720) / 2 : 0
        scale: frame.k

        Item {
            id: menu_space
            x: -199
            y: -27
            width: 1280
            height: 720
        }
    }

    // The menu window; its right side dissolves into the sky. `k` is its on-screen scale.
    component MenuPanel: Item {
        id: panel
        property real k: 1
        x: 262
        y: 105
        width: 834
        height: 495
        layer.enabled: true
        layer.textureSize: Qt.size(Math.ceil(panel.width * panel.k), Math.ceil(panel.height * panel.k))
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: panel_fade
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Shape {
            x: -262
            y: -105
            width: 1280
            height: 720
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 760
                    y1: 0
                    x2: 180
                    y2: 720
                    GradientStop { position: 0; color: "#16265e" }
                    GradientStop { position: 0.55; color: "#2c4aa6" }
                    GradientStop { position: 1; color: "#4c78dc" }
                }
                PathSvg { path: "M297 113 H1078 Q1086 113 1086 121 V582 Q1086 590 1078 590 H294 L272 568 V137 Z" }
            }
            Stroke { strokeColor: "#6f98f4"; strokeWidth: 9; d: "M272 568 V137 L297 113 H1086" }
            Stroke { strokeColor: "#99b8d0ff"; strokeWidth: 2; d: "M277 565 V139 L299 118" }
            Stroke { strokeColor: "#0a1234"; strokeWidth: 6; d: "M294 590 H1080" }
            Stroke { strokeColor: "#08102e"; strokeWidth: 6; d: "M1086 203 H313 V560" }
            Stroke { strokeColor: "#807d9ee6"; strokeWidth: 2; d: "M1086 208 H318 V556" }
        }

        Rectangle {
            id: panel_fade
            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.6; color: "#ffffffff" }
                GradientStop { position: 1; color: "#00ffffff" }
            }
        }
    }

    component Stroke: ShapePath {
        property alias d: svg.path
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { id: svg }
    }

    Loader {
        anchors.fill: parent
        active: root.view === "title" || root.view === "saver"
        sourceComponent: title_view
    }

    Loader {
        anchors.fill: parent
        active: root.view === "file"
        sourceComponent: file_view
    }

    Loader {
        anchors.fill: parent
        active: root.view === "name"
        sourceComponent: name_view
    }

    Component {
        id: title_view

        Item {
            id: title
            readonly property bool saver: root.view === "saver"
            // Narrower than the stage (portrait), the logo and text shrink to fit while the sky still covers.
            readonly property real fit: Math.min(1, title.width / title_stage.k / 860)
            // There the sun and moon arc narrows to stay on screen.
            readonly property real arc_k: title.fit < 1 ? (title.width / title_stage.k / 2 - 40) / 760 : 1

            Stage {
                id: title_stage

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillGradient: LinearGradient {
                            x1: 0
                            y1: 0
                            x2: 320
                            y2: 900
                            GradientStop { position: 0; color: root.sky0 }
                            GradientStop { position: 0.55; color: root.sky1 }
                            GradientStop { position: 0.8; color: root.sky2 }
                        }
                        PathRectangle { width: 1600; height: 900 }
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: root.star_alpha > 0
                    opacity: root.star_alpha

                    Repeater {
                        model: root.stars

                        Rectangle {
                            required property var modelData
                            x: modelData.x - modelData.r
                            y: modelData.y - modelData.r
                            width: modelData.r * 2
                            height: modelData.r * 2
                            radius: modelData.r
                            color: "#ffffff"
                            opacity: modelData.a
                        }
                    }
                }

                Item {
                    width: 1600
                    height: 900
                    visible: root.moon_alpha > 0
                    opacity: root.moon_alpha
                    x: 800 + (root.moon_at.x - 800) * title.arc_k - 1370
                    y: root.moon_at.y - 150

                    Radial {
                        cx: 1370
                        cy: 150
                        rx: 170
                        inner: "#52fff6d8"
                        mid: 0.3
                    }

                    Shape {
                        x: 1370 - 66
                        y: 150 - 66
                        width: 132
                        height: 132
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillGradient: RadialGradient {
                                centerX: 0.42 * 132
                                centerY: 0.38 * 132
                                focalX: 0.42 * 132
                                focalY: 0.38 * 132
                                centerRadius: 0.7 * 132
                                focalRadius: 0
                                GradientStop { position: 0; color: "#f4ecd0" }
                                GradientStop { position: 0.7; color: "#d8cda6" }
                                GradientStop { position: 1; color: "#b2a784" }
                            }
                            PathAngleArc { centerX: 66; centerY: 66; radiusX: 66; radiusY: 66; startAngle: 0; sweepAngle: 360 }
                        }
                    }

                    Repeater {
                        model: [[1348, 128, 13], [1392, 172, 10], [1384, 118, 6], [1340, 176, 7]]

                        Rectangle {
                            required property var modelData
                            x: modelData[0] - modelData[2]
                            y: modelData[1] - modelData[2]
                            width: modelData[2] * 2
                            height: modelData[2] * 2
                            radius: modelData[2]
                            color: "#6b9a9072"
                        }
                    }
                }

                Item {
                    width: 1600
                    height: 900
                    visible: root.sun_alpha > 0
                    opacity: root.sun_alpha
                    x: 800 + (root.sun_at.x - 800) * title.arc_k - 1360
                    y: root.sun_at.y - 170

                    Radial {
                        cx: 1360
                        cy: 170
                        rx: 190
                        inner: "#e6fff4c8"
                        mid: 0.2
                        outer: "#00ffcf70"
                    }

                    Rectangle {
                        x: 1360 - 58
                        y: 170 - 58
                        width: 116
                        height: 116
                        radius: 58
                        color: "#fff8dc"
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: root.day_cloud_alpha > 0
                    opacity: root.day_cloud_alpha

                    Repeater {
                        model: [[170, 190, 120, 30], [250, 168, 80, 42], [1300, 330, 150, 30], [1380, 304, 90, 44]]

                        Radial {
                            required property var modelData
                            cx: modelData[0]
                            cy: modelData[1]
                            rx: modelData[2] + 10
                            ry: modelData[3] + 10
                            inner: "#d9ffffff"
                            mid: 0.7
                        }
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillColor: root.hill0
                        PathSvg { path: "M-10 640 L120 616 L230 628 L340 600 L450 622 L560 606 L700 630 L860 612 L1010 634 L1150 610 L1290 626 L1420 604 L1610 622 V910 H-10 Z" }
                    }
                    ShapePath {
                        strokeWidth: -1
                        fillColor: root.hill1
                        PathSvg { path: "M-10 700 C200 660 420 650 640 676 C860 702 1080 690 1280 664 C1420 648 1540 652 1610 660 V910 H-10 Z" }
                    }
                    ShapePath {
                        strokeWidth: -1
                        fillColor: root.hill2
                        PathSvg { path: "M-10 790 C240 752 520 760 800 782 C1080 804 1340 776 1610 758 V910 H-10 Z" }
                    }
                }

                Item {
                    anchors.fill: parent
                    opacity: root.cloud_alpha

                    Repeater {
                        model: root.drift_clouds

                        Radial {
                            id: drifting
                            required property var modelData
                            readonly property real lead: (modelData.lead % modelData.dur) / modelData.dur
                            property real tx: -640 + drifting.lead * 2880
                            cx: modelData.x + modelData.w / 2 + drifting.tx
                            cy: modelData.y + modelData.h / 2
                            rx: modelData.w / 2
                            ry: modelData.h / 2
                            inner: "#57ffffff"
                            middle: "#1fffffff"
                            mid: 0.6

                            SequentialAnimation on tx {
                                running: root.animate
                                NumberAnimation { to: 2240; duration: drifting.modelData.dur * (1 - drifting.lead) }
                                NumberAnimation { from: -640; to: 2240; duration: drifting.modelData.dur; loops: Animation.Infinite }
                            }
                        }
                    }
                }

                // Frames are 1120x929 around the 960px wide logo, offset 80 left and 140 up.
                Item {
                    id: fire
                    property real phase: 0
                    readonly property real k: logo.width / 960
                    x: logo.x - 80 * k
                    y: logo.y - 140 * k
                    width: 1120 * k
                    height: 929 * k
                    visible: root.lit
                    transformOrigin: Item.Bottom

                    Item {
                        anchors.fill: parent
                        transformOrigin: Item.Bottom

                        Repeater {
                            model: 5

                            Image {
                                required property int index
                                anchors.fill: parent
                                source: Qt.resolvedUrl("ocarina/fire" + index + ".png")
                                sourceSize.width: Math.round(fire.width * title_stage.k)
                                // Uncached, so the frames leave with the lock instead of staying in Qt's image cache.
                                cache: false
                                opacity: index === Math.floor(fire.phase) ? 1 : 0
                                asynchronous: true
                                smooth: true

                                Behavior on opacity {
                                    enabled: root.animate
                                    NumberAnimation { duration: 90 }
                                }
                            }
                        }

                        SequentialAnimation on scale {
                            running: root.animate && root.lit
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.02; duration: 300; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.99; duration: 260; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.015; duration: 340; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 280; easing.type: Easing.InOutSine }
                        }
                    }

                    NumberAnimation on phase {
                        running: root.animate && root.lit
                        from: 0
                        to: 4.99
                        duration: 500
                        loops: Animation.Infinite
                    }

                    ParallelAnimation {
                        id: ignite
                        NumberAnimation { target: fire; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutQuad }
                        NumberAnimation { target: fire; property: "scale"; from: 0.85; to: 1; duration: 300; easing.type: Easing.OutBack }
                    }
                }

                Connections {
                    target: root
                    function onLitChanged() {
                        if (root.lit && root.animate) {
                            ignite.restart();
                        } else {
                            ignite.stop();
                            fire.opacity = 1;
                            fire.scale = 1;
                        }
                    }
                }

                Image {
                    id: logo
                    width: 808.8 * 0.82 * title.fit
                    height: 631.2 * 0.82 * title.fit
                    x: 776.6 * title.fit + 800 * (1 - title.fit) - width / 2
                    y: 350.6 - height / 2
                    source: Qt.resolvedUrl("ocarina/logo.png")
                    sourceSize.width: Math.round(logo.width * title_stage.k)
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    layer.enabled: root.lit
                    layer.textureSize: Qt.size(logo.sourceSize.width, Math.round(logo.sourceSize.width * logo.height / logo.width))
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#ff9a24"
                        shadowBlur: 0.5
                        shadowScale: 1.015
                        blurMax: 24

                        SequentialAnimation on shadowOpacity {
                            running: root.animate
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.8; to: 1; duration: 180 }
                            NumberAnimation { from: 1; to: 0.75; duration: 220 }
                            NumberAnimation { from: 0.75; to: 0.8; duration: 160 }
                        }
                    }
                }

                // Placed from logo.json: centre 0.67878, baseline 0.77947, size 0.07224 and max width 0.50074 of the logo box.
                FitText {
                    x0: logo.x + 0.67878 * logo.width
                    base_y: logo.y + 0.77947 * logo.height
                    max_w: 0.50074 * logo.width
                    centered: true
                    text: (root.ctx ? root.ctx.host : "").toUpperCase()
                    color: "#f4f4f4"
                    style: Text.Outline
                    styleColor: "#1a1030"
                    font.family: "Cormorant SC"
                    font.weight: 600
                    font.pixelSize: Math.round(0.07224 * logo.height)
                    font.letterSpacing: 0.42
                }

                Item {
                    id: press_fade
                    anchors.fill: parent
                    opacity: title.saver ? 0 : 1

                    Behavior on opacity {
                        enabled: root.animate
                        NumberAnimation { duration: 1000 }
                    }

                    FitText {
                        id: press_start
                        visible: press_fade.opacity > 0
                        x0: 800
                        base_y: 752
                        centered: true
                        text: "PRESS START"
                        color: "#ff3a1e"
                        style: Text.Outline
                        styleColor: "#2a0400"
                        font.family: "Cinzel"
                        font.weight: 700
                        font.pixelSize: Math.round(42 * title.fit)
                        font.letterSpacing: 4 * title.fit

                        SequentialAnimation on opacity {
                            running: root.animate && !title.saver && !root.lit
                            loops: Animation.Infinite
                            onStopped: press_start.opacity = 1
                            PropertyAction { value: 1 }
                            PauseAnimation { duration: 650 }
                            PropertyAction { value: 0 }
                            PauseAnimation { duration: 650 }
                        }
                    }
                }

                FitText {
                    x0: 800
                    base_y: 838
                    centered: true
                    text: "© 1998 " + root.distro
                    color: "#ffffff"
                    style: Text.Outline
                    styleColor: "#000000"
                    font.family: root.ui_font
                    font.weight: 800
                    font.pixelSize: Math.round(30 * title.fit)
                    font.letterSpacing: title.fit
                }
            }

            NumberAnimation on opacity {
                running: root.animate
                from: 0
                to: 1
                duration: 250
            }
        }
    }

    Component {
        id: file_view

        Item {
            Stage {
                design_w: 1280
                design_h: 720

                MenuSky {}
            }

            PanelFrame {
                id: fs_frame

                MenuPanel {
                    k: fs_frame.k
                }

                Heading {
                    x0: 352
                    base_y: 182
                    size: 52
                    fit_w: 465
                    text: root.in_options ? "Options" : "Please select a file."
                }

                // The game's file list, scaled from its full-screen layout into the name entry frame.
                Item {
                    visible: !root.in_options
                    readonly property real s: 0.661
                    x: 313 - 172 * s
                    y: 203 - 120 * s
                    width: 1280
                    height: 720
                    scale: s
                    transformOrigin: Item.TopLeft

                    Plate {
                        x: 485
                        y: 148
                        width: 448
                        height: 62
                        r: 10
                        shadow_x: 5
                    }

                    FitText {
                        x0: 540
                        base_y: 205
                        text: (root.ctx ? root.ctx.user : "").slice(0, 8)
                        color: "#e6ecf6"
                        style: Text.Outline
                        styleColor: "#2a3c78"
                        font.family: root.key_font
                        font.pixelSize: 62
                        font.letterSpacing: 6
                    }

                    Pill { x: 202; y: 147; width: 276; height: 66; label: "File 1"; label_x0: 268; label_x1: 410; base_y: 204; lit: root.file_item === "file1" }

                    Rectangle {
                        x: 442
                        y: 169
                        width: 84
                        height: 31
                        radius: 15.5
                        color: "#2a3c86"
                        border.width: 3
                        border.color: "#0a1234"

                        Rectangle {
                            x: 10
                            y: 5
                            width: 60
                            height: 12
                            radius: 6
                            color: "#9ab8f2"
                        }
                    }

                    Pill { x: 203; y: 225; width: 277; height: 65; label: "File 2"; label_x0: 268; label_x1: 420; base_y: 281; dot: true }
                    Pill { x: 203; y: 298; width: 277; height: 65; label: "File 3"; label_x0: 268; label_x1: 420; base_y: 354; dot: true }
                    Pill { x: 203; y: 409; width: 275; height: 64; label: "Reboot"; label_x0: 243; label_x1: 438; base_y: 460; lit: root.file_item === "reboot" }
                    Pill { x: 203; y: 483; width: 275; height: 65; label: "Shut down"; label_x0: 228; label_x1: 453; base_y: 535; lit: root.file_item === "poweroff" }
                    Pill { x: 203; y: 594; width: 275; height: 67; label: "Options"; label_x0: 255; label_x1: 440; base_y: 645; lit: root.file_item === "options" }
                }

                // The Options menu, in file select's scaled layout so its rows match the file pills.
                Item {
                    visible: root.in_options
                    readonly property real s: 0.661
                    x: 313 - 172 * s
                    y: 203 - 120 * s
                    width: 1280
                    height: 720
                    scale: s
                    transformOrigin: Item.TopLeft

                    Repeater {
                        model: root.opt_items

                        Pill {
                            id: opt_row
                            required property int index
                            required property var modelData
                            x: 203
                            y: 147 + opt_row.index * 78
                            width: 480
                            height: 65
                            label: root.opt_label(opt_row.modelData)
                            label_x0: opt_row.x + 40
                            base_y: opt_row.y + 56
                            lit: root.opt_item === opt_row.modelData
                        }
                    }
                }

                Item {
                    id: note_box
                    readonly property string note: root.in_options ? root.opt_note : root.file_note
                    readonly property string word: (root.in_options ? root.opt_words[root.opt_item] : root.power_words[root.file_item]) || ""
                    readonly property var lines: {
                        const w = note_box.word;
                        switch (note_box.note) {
                        case "armed": return [w.charAt(0).toUpperCase() + w.slice(1) + (root.in_options ? "?" : " the <font color=\"#ff3c3c\">system</font>?"), "Press Enter again to " + w + "."];
                        case "running": return [({ reboot: "Rebooting...", poweroff: "Shutting down...", firmware: "Rebooting to setup...", text: "Switching..." })[root.in_options ? root.opt_item : root.file_item], "See you soon."];
                        case "preview": return ["Preview: would " + w + ".", "Nothing was run."];
                        default: return [];
                        }
                    }
                    visible: note_box.lines.length > 0

                    Rectangle {
                        x: 540
                        y: 420
                        width: 520
                        height: 120
                        radius: 14
                        color: "#c7000000"
                    }

                    FitText {
                        x0: 568
                        base_y: 465
                        max_w: 470
                        textFormat: Text.StyledText
                        text: note_box.lines[0] || ""
                        color: "#ffffff"
                        font.family: root.ui_font
                        font.weight: 500
                        font.pixelSize: 28
                    }

                    FitText {
                        x0: 568
                        base_y: 507
                        max_w: 470
                        textFormat: Text.PlainText
                        text: note_box.lines[1] || ""
                        color: "#ffffff"
                        font.family: root.ui_font
                        font.weight: 500
                        font.pixelSize: 28
                    }

                    Shape {
                        x: 1024
                        y: 518
                        width: 16
                        height: 11
                        visible: note_box.note === "armed"
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: "#3cd26a"
                            PathSvg { path: "M0 0 L16 0 L8 11 Z" }
                        }

                        SequentialAnimation on y {
                            running: root.animate
                            loops: Animation.Infinite
                            NumberAnimation { from: 518; to: 522; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 522; to: 518; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }

                FitText {
                    x0: 642
                    base_y: 651
                    centered: true
                    text: "↑↓ Select ● A-Decide ● B-Cancel"
                    color: "#8ff6ff"
                    style: Text.Outline
                    styleColor: "#03202c"
                    font.family: root.ui_font
                    font.weight: 800
                    font.pixelSize: 32
                }
            }

            NumberAnimation on opacity {
                running: root.animate
                from: 0
                to: 1
                duration: 250
            }
        }
    }

    Component {
        id: name_view

        Item {
            id: name_screen
            readonly property bool unlocking: root.phase === "unlock"
            readonly property string prompt: root.ctx && root.ctx.prompt ? root.ctx.prompt : ""
            readonly property bool dialog: (root.phase === "wrong" && root.typed === 0) || name_screen.prompt !== ""

            Stage {
                design_w: 1280
                design_h: 720

                MenuSky {}
            }

            PanelFrame {
                id: ne_frame

                MenuPanel {
                    k: ne_frame.k
                }

                Heading {
                    x0: 352
                    base_y: 182
                    size: 52
                    fit_w: 236
                    text: "Password ?"
                }

                Plate {
                    x: 623
                    y: 137
                    width: 290
                    height: 46
                    r: 8
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillColor: "#1a2a66"
                        PathSvg { path: "M634 156 L642 161 L634 166 Z" }
                    }
                }

                Repeater {
                    model: 8

                    Shape {
                        id: mark
                        required property int index
                        x: 670 + mark.index * 31 - 13
                        y: 160 - 13
                        width: 26
                        height: 26
                        visible: mark.index < root.marks
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "#ffe050"
                            strokeColor: "#8a5a02"
                            strokeWidth: 1.5
                            joinStyle: ShapePath.RoundJoin
                            PathSvg { path: "M13 0 L16.6 9.4 L26 13 L16.6 16.6 L13 26 L9.4 16.6 L0 13 L9.4 9.4 Z" }
                        }
                    }
                }

                Orb {
                    visible: !name_screen.unlocking
                    cx: 670 + root.marks * 31
                    cy: 160
                    rx: 26

                    Pulse on opacity {
                        running: root.animate
                    }
                }

                Repeater {
                    model: root.keys

                    Item {
                        id: key
                        required property int index
                        required property var modelData
                        readonly property bool picked: key.index === root.selected_key
                        readonly property real cx: 362 + 48.1 * key.modelData.c
                        readonly property real base_y: root.key_baselines[key.modelData.r]
                        anchors.fill: parent

                        Orb {
                            visible: key.picked
                            cx: key.cx
                            cy: key.base_y - 14
                            rx: 30

                            Pulse on opacity {
                                running: root.animate && key.picked
                            }
                        }

                        FitText {
                            x0: key.cx + 1
                            base_y: key.base_y + 2
                            centered: true
                            text: key.modelData.ch
                            color: "#0a1240"
                            opacity: 0.9
                            font.family: root.key_font
                            font.pixelSize: 43
                        }

                        FitText {
                            x0: key.cx
                            base_y: key.base_y
                            centered: true
                            text: key.modelData.ch
                            color: key.picked ? "#f4f020" : "#eef3ff"
                            style: Text.Outline
                            styleColor: key.picked ? "#f4f020" : "#eef3ff"
                            font.family: root.key_font
                            font.pixelSize: 43
                        }
                    }
                }

                Plate {
                    x: 732
                    y: 505
                    width: 76
                    height: 43
                    r: 8
                    button: true

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "#0d1840"
                            strokeColor: "#6f8fdc"
                            strokeWidth: 1.2
                            PathSvg { path: "M18 22 L32 12 V18 H58 V26 H32 V32 Z" }
                        }
                    }
                }

                Item {
                    x: 828
                    y: 505
                    width: 127
                    height: 45

                    Rectangle {
                        visible: name_screen.unlocking
                        x: -5
                        y: -5
                        width: 137
                        height: 55
                        radius: 12
                        color: "transparent"
                        border.width: 5
                        border.color: "#9ffcff"

                        Pulse on opacity {
                            running: root.animate && name_screen.unlocking
                        }
                    }

                    Plate {
                        anchors.fill: parent
                        r: 8
                        button: true
                        lit: name_screen.unlocking
                    }

                    FitText {
                        x0: 891 - 828
                        base_y: 540 - 505
                        centered: true
                        text: "END"
                        color: "#0d1840"
                        style: Text.Outline
                        styleColor: "#6f8fdc"
                        font.family: root.ui_font
                        font.weight: 800
                        font.pixelSize: 32
                        font.letterSpacing: 5
                    }
                }

                FitText {
                    readonly property bool caps: !!root.ctx && root.ctx.caps_lock
                    x0: caps ? 640 : 475
                    base_y: 651
                    centered: caps
                    fit_w: caps ? 0 : 335
                    text: caps ? "Caps Lock is on" : "A-Decide ● B-Cancel"
                    color: "#8ff6ff"
                    style: Text.Outline
                    styleColor: "#03202c"
                    font.family: root.ui_font
                    font.weight: 800
                    font.pixelSize: 36
                }

                Item {
                    visible: name_screen.dialog

                    Rectangle {
                        x: 300
                        y: 530
                        width: 680
                        height: 150
                        radius: 16
                        color: "#c7000000"
                    }

                    FitText {
                        x0: 340
                        base_y: 590
                        max_w: 600
                        textFormat: name_screen.prompt !== "" ? Text.PlainText : Text.StyledText
                        text: name_screen.prompt !== "" ? name_screen.prompt : "That's <font color=\"#ff3c3c\">not the right password</font>..."
                        color: "#ffffff"
                        font.family: root.ui_font
                        font.weight: 500
                        font.pixelSize: 32
                    }

                    FitText {
                        readonly property string message: root.ctx ? root.ctx.message : ""
                        visible: name_screen.prompt === ""
                        x0: 340
                        base_y: 636
                        max_w: 600
                        textFormat: Text.PlainText
                        text: message !== "" && message !== "Wrong password" ? message : "Attempt " + (root.ctx ? Math.max(1, root.ctx.fail_count) : 1) + ". Try entering it again."
                        color: "#ffffff"
                        font.family: root.ui_font
                        font.weight: 500
                        font.pixelSize: 32
                    }

                    Shape {
                        id: next_mark
                        x: 932
                        y: 652
                        width: 18
                        height: 12
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillColor: "#3cd26a"
                            PathSvg { path: "M0 0 L18 0 L9 12 Z" }
                        }

                        SequentialAnimation on y {
                            running: root.animate
                            loops: Animation.Infinite
                            NumberAnimation { from: 652; to: 656; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 656; to: 652; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }

            NumberAnimation on opacity {
                running: root.animate && !name_screen.unlocking
                from: 0
                to: 1
                duration: 250
            }
        }
    }

    Rectangle {
        id: flash
        anchors.fill: parent
        visible: root.phase === "wrong" && root.view === "name"
        color: "#e00c0c"
        opacity: root.animate ? 0 : 0.14

        SequentialAnimation {
            id: flash_anim
            NumberAnimation { target: flash; property: "opacity"; from: 0.62; to: 0.1; duration: 540; easing.type: Easing.OutQuad }
        }
    }

    Rectangle {
        id: start_white
        anchors.fill: parent
        visible: start_white.opacity > 0
        color: "#ffffff"
        opacity: 0

        SequentialAnimation {
            id: start_fade
            NumberAnimation { target: start_white; property: "opacity"; from: 0; to: 1; duration: 550; easing.type: Easing.InQuad }
            PropertyAction { target: root; property: "holding_title"; value: false }
            PauseAnimation { duration: 150 }
            NumberAnimation { target: start_white; property: "opacity"; to: 0; duration: 550; easing.type: Easing.OutQuad }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.phase === "unlock"
        color: "#ffffff"
        opacity: root.animate ? 0 : 0.9

        SequentialAnimation on opacity {
            running: root.animate && root.phase === "unlock"
            PauseAnimation { duration: 200 }
            NumberAnimation { from: 0; to: 1; duration: root.unlock_ms - 200; easing.type: Easing.InQuad }
        }
    }
}
