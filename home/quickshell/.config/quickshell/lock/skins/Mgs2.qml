// home/quickshell/.config/quickshell/lock/skins/Mgs2.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import "mgs2/Art.js" as Art

// Metal Gear Solid 2 recast for the Oasis desktop: the title, the main menu, DATA LOAD picks the user, NAME ENTRY takes the password.
Item {
    id: root

    property var ctx: null
    readonly property int unlock_ms: 3550

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
    // The title theme plays only on the login screen; the menu theme from the main menu until unlock or the saver.
    readonly property string music_track: {
        if (!root.owns_sound || root.ctx.music === false || root.phase === "saver" || root.phase === "unlock") return "";
        if (root.screen === "menu" || root.screen === "load" || root.screen === "name") return "menu";
        return root.ctx.login === true ? "title" : "";
    }
    property int heard_typed: 0
    // Set once the accept sound has played for this attempt; a new password clears it.
    property bool heard_unlock: false
    property bool dying: false

    readonly property bool can_step: !!root.ctx && "scene" in root.ctx
    readonly property string scene: root.can_step ? root.ctx.scene : ""
    readonly property int typed: root.ctx ? root.ctx.buffer_length : 0
    readonly property bool checking: !!root.ctx && root.ctx.checking
    readonly property bool granted: root.phase === "unlock"
    // title, menu, load, name or saver. Options counts as "menu": it swaps the menu's list.
    readonly property string screen: {
        if (root.phase === "saver") return "saver";
        if (root.phase === "unlock" || root.phase === "wrong" || root.typed > 0 || root.checking) return "name";
        if (root.scene.startsWith("menu") || root.scene.startsWith("opt:")) return "menu";
        if (root.scene.startsWith("load")) return "load";
        return root.scene === "name" ? "name" : "title";
    }
    // Black once the unlock caption starts.
    property bool captioning: false
    readonly property string view: root.captioning ? "unlock" : root.screen
    // The page on show: the view, with Options as its own page; it trails `page` while a transition runs.
    readonly property string page: root.view === "menu" && root.in_options ? "opt" : root.view
    property string shown: ""
    // 1 is the frame fully open; a transition folds it up to 0, switches `shown`, then unfolds it from the top-right.
    property real fold: 1
    property bool unfolding: false
    property real content_alpha: 1
    property real title_alpha: 1
    property int tx_fold_out: 0
    property int tx_title_out: 0
    property int tx_fold_in: 0
    property int tx_title_in: 0

    // The menu's cursor and note live in the scene as "menu:<item>:<note>" so every output agrees.
    readonly property var menu_items: ["load", "options", "reboot", "poweroff"]
    readonly property var menu_labels: ({ load: "LOAD GAME", options: "OPTIONS", reboot: "REBOOT", poweroff: "SHUT DOWN" })
    readonly property var menu_descs: ({ load: "Load your saved data and sign in.", options: "Session and firmware setup.", reboot: "Restart the computer.", poweroff: "Turn off the computer." })
    readonly property bool in_menu: root.scene === "menu" || root.scene.startsWith("menu:")
    readonly property string menu_item: root.scene.startsWith("menu:") ? root.scene.split(":")[1] : "load"
    readonly property string menu_note: root.scene.startsWith("menu:") ? (root.scene.split(":")[2] || "") : ""
    readonly property var power_words: ({ reboot: "reboot", poweroff: "shut down" })

    // The Options list's cursor and note live in the scene as "opt:<item>:<note>". Greeter-only entries are hidden on the lock.
    readonly property bool ctx_login: !!root.ctx && root.ctx.login === true
    readonly property var opt_items: root.ctx_login ? ["session", "safe", "text", "firmware", "back"] : ["firmware", "back"]
    readonly property bool in_options: root.scene.startsWith("opt:")
    readonly property string opt_item: root.in_options ? root.scene.split(":")[1] : (root.opt_items[0] || "")
    readonly property string opt_note: root.in_options ? (root.scene.split(":")[2] || "") : ""
    readonly property var opt_words: ({ firmware: "reboot to firmware setup", text: "switch to the text login" })
    readonly property var opt_descs: ({ session: "Pick the session to start.", safe: "Start the safe session.", text: "Switch to the text login.", firmware: "Restart into firmware setup.", back: "Return to the main menu." })

    function opt_label(item) {
        switch (item) {
        case "session": return "SESSION " + (root.ctx && "session_name" in root.ctx ? root.ctx.session_name : "");
        case "safe": return "SAFE SESSION";
        case "text": return "TEXT LOGIN";
        case "firmware": return "FIRMWARE SETUP";
        default: return "BACK";
        }
    }

    // DATA LOAD rows: the greeter's login users, else only this user; the cursor lives in the scene as "load:<index>".
    readonly property var users: {
        const list = root.ctx && Array.isArray(root.ctx.users) && root.ctx.users.length > 0 ? root.ctx.users : [{ name: root.ctx ? root.ctx.user : "", full: "" }];
        return list.slice(0, 6);
    }
    readonly property int user_index: Math.max(0, root.users.findIndex(u => root.ctx && u.name === root.ctx.user))
    readonly property int load_sel: root.scene.startsWith("load:") ? Math.min(root.users.length - 1, parseInt(root.scene.split(":")[1]) || 0) : root.user_index
    readonly property string user_name: root.ctx ? root.ctx.user : ""
    readonly property var face_urls: root.ctx && typeof root.ctx.face_urls === "function" ? root.ctx.face_urls(root.user_name) : []
    readonly property string host: root.ctx ? root.ctx.host : ""

    readonly property date now: root.ctx ? root.ctx.now : new Date()
    readonly property string clock_text: Qt.formatTime(root.now, "HH:mm")
    readonly property string day_text: Qt.formatDate(root.now, "yyyy/MM/dd")
    readonly property string caption_text: root.host + ", " + root.clock_text + "..."
    property int caption_chars: 0
    property real caption_alpha: 1

    // The description line under every menu screen, as [text, tone] with tone "", "red" or "green".
    readonly property var desc: {
        const c = root.ctx;
        if (!c) return ["", ""];
        if (root.screen === "name") {
            if (root.granted) return ["Password accepted.", "green"];
            if (c.prompt) return [c.prompt, ""];
            if (root.checking) return ["Checking...", ""];
            if (root.phase === "wrong") {
                const msg = c.message !== "" && c.message !== "Wrong password" ? c.message : "Password incorrect.";
                return [msg + (c.fail_count > 1 ? " Attempt " + c.fail_count + "." : " Try again."), "red"];
            }
            if (c.caps_lock) return ["Caps Lock is on.", "red"];
            return [root.typed > 0 ? "Press Enter to confirm." : "Enter your password.", ""];
        }
        if (root.screen === "load") return ["Sign in as " + ((root.users[root.load_sel] || {}).name || root.user_name) + ".", ""];
        if (root.screen !== "menu") return ["", ""];
        if (root.in_options) {
            const w = root.opt_words[root.opt_item];
            if (root.opt_note === "armed") return ["Press Enter again to " + w + ".", "red"];
            if (root.opt_note === "running") return [w.charAt(0).toUpperCase() + w.slice(1) + "...", "red"];
            if (root.opt_note === "preview") return ["The real screen would " + w + " now.", ""];
            return [root.opt_descs[root.opt_item] || "", ""];
        }
        const w = root.power_words[root.menu_item];
        if (root.menu_note === "armed") return ["Press Enter again to " + w + ".", "red"];
        if (root.menu_note === "running") return [root.menu_item === "reboot" ? "Rebooting..." : "Shutting down...", "red"];
        if (root.menu_note === "preview") return ["The real screen would " + w + " now.", ""];
        return [root.menu_descs[root.menu_item] || "", ""];
    }

    readonly property string logo_font: "Barlow Condensed"
    readonly property string ui_font: "Liberation Sans"
    readonly property color line_color: "#9eaca3"
    readonly property color item_on: "#d3dbd4"
    readonly property color item_off: "#4a544c"
    readonly property color field_ink: "#b9c3bc"
    readonly property color ok_green: "#a0e0b0"
    readonly property color mol_red: "#d63126"

    // Each screen's frame: the vertical rule, the rail beside the box, the box and the horizontal rule.
    readonly property var frames: ({
        menu: { v: 62, rail: [62, 140], box: [140, 46, 1540, 756], h: 756 },
        load: { v: 62, rail: [88, 140], box: [140, 62, 1500, 690], h: 690 },
        name: { v: 56, rail: [56, 140], box: [140, 66, 1530, 775], h: 775 }
    })
    readonly property var frame: root.frames[root.shown === "opt" ? "menu" : root.shown] || null
    property var last_frame: root.frames.menu
    onFrameChanged: if (root.frame) root.last_frame = root.frame
    // The frame as drawn: the box keeps its top edge, its bottom follows `fold`, and while unfolding its left edge sweeps in from the right.
    readonly property var fb: {
        const f = root.last_frame, k = root.fold;
        const dx = root.unfolding ? (f.box[2] - f.box[0]) * (1 - k) : 0;
        return { v: f.v + dx, r0: f.rail[0] + dx, r1: f.rail[1] + dx, x0: f.box[0] + dx, y0: f.box[1], x1: f.box[2], y1: f.box[1] + (f.box[3] - f.box[1]) * k };
    }

    function is_framed(p) {
        return p === "menu" || p === "opt" || p === "load" || p === "name";
    }

    // Folds the old page away and unfolds the new one; unlock, the saver and still screens switch at once.
    function turn_page() {
        const to = root.page, from = root.shown;
        tx.stop();
        const still = !root.animate || from === "" || [to, from].some(p => p === "unlock" || p === "saver");
        if (to === from || still) {
            root.shown = to;
            root.fold = 1;
            root.unfolding = false;
            root.content_alpha = 1;
            root.title_alpha = 1;
            return;
        }
        root.tx_fold_out = root.is_framed(from) ? Math.round(250 * root.fold) : 0;
        root.tx_title_out = from === "title" ? 400 : 0;
        root.tx_fold_in = root.is_framed(to) ? 300 : 0;
        root.tx_title_in = to === "title" ? 400 : 0;
        if (root.owns_sound && audio_loader.item) audio_loader.item.play("page");
        tx.restart();
    }

    onPageChanged: root.turn_page()

    readonly property var mol_sets: ({
        title: [[21, 1080, 180, 1.3], [4, 90, 780, 0.9], [9, 1300, 470, 1.0]],
        menu: [[5, 640, 150, 1.45], [8, 980, 250, 1.6], [12, 720, 470, 1.2]],
        load: [[14, 1300, 760, 0.9]],
        name: [[17, 1260, 470, 1.2], [19, 1000, 560, 0.9], [2, 40, 60, 0.9]]
    })
    readonly property var molecules: {
        const out = [];
        for (const set in root.mol_sets) root.mol_sets[set].forEach((m, i) => out.push(Object.assign({ set: set, i: i }, Art.molecule(m[0], m[1], m[2], m[3]))));
        return out;
    }
    readonly property var diagram: Art.diagram()
    // Molecules drawn around the origin for the screensaver's drifters to pick from.
    readonly property var saver_pool: [2, 4, 5, 8, 9, 12, 14, 17, 19, 21, 23, 27].map((seed, i) => Art.molecule(seed, 0, 0, 0.8 + (i % 4) * 0.2))
    readonly property var blobs: {
        const r = Art.rng(11), out = [];
        for (let i = 0; i < 14; i++) out.push({ x: r() * 1600, y: r() * 900, rx: 160 + r() * 380, ry: 80 + r() * 200, light: r() >= 0.5, a: 0.1 + r() * 0.22, s: (r() - 0.5) * 0.02 });
        return out;
    }

    readonly property var code_labels: [
        "P5JJAF9BD9RE",
        root.ctx && root.ctx.has_battery ? "BATT " + String(root.ctx.battery_percent).padStart(3, "0") : "BATT ---",
        "P5JJAF9BD9RE",
        "MSG " + String(root.ctx ? root.ctx.notifications : 0).padStart(3, "0"),
        "PEKRJOLHREJ00LE",
        root.ctx && root.ctx.has_weather ? (root.ctx.weather_temp.replace("°", "") + " " + root.ctx.weather_cond).toUpperCase() : "NO SIGNAL",
        "P5JJAF9BD9RE"
    ]
    readonly property var code_offsets: {
        const r = Art.rng(3);
        return root.code_labels.map(() => r() * 30);
    }

    // Enter steps title, menu, DATA LOAD and NAME ENTRY; Escape steps back; j/k or arrows move; a printable key jumps to NAME ENTRY and still types.
    function handle_key(event) {
        const c = root.ctx;
        if (!root.can_step || c.buffer_length > 0 || c.checking || c.granted) return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        const enter = !ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter);
        const listing = root.screen === "menu" || root.screen === "load";
        const down = event.key === Qt.Key_Down || (listing && !ctrl && event.text === "j");
        const up = event.key === Qt.Key_Up || (listing && !ctrl && event.text === "k");
        if (root.screen === "name") {
            if (event.key === Qt.Key_Escape) {
                c.scene = "load";
                root.cue("cancel");
            }
            return false;
        }
        if (root.screen === "menu" && (up || down)) {
            const items = root.in_options ? root.opt_items : root.menu_items;
            const at = items.indexOf(root.in_options ? root.opt_item : root.menu_item);
            const next = items[(at + (down ? 1 : items.length - 1)) % items.length];
            c.scene = (root.in_options ? "opt:" : "menu:") + next;
            root.cue("move");
            return true;
        }
        if (root.screen === "menu" && enter) {
            root.cue("decide");
            if (root.in_options) root.opt_activate();
            else root.menu_activate();
            return true;
        }
        if (root.screen === "menu" && event.key === Qt.Key_Escape) {
            c.scene = root.in_options ? "menu:options" : "";
            root.cue("cancel");
            return true;
        }
        if (root.screen === "load" && (up || down)) {
            if (root.users.length > 1) {
                c.scene = "load:" + ((root.load_sel + (down ? 1 : root.users.length - 1)) % root.users.length);
                root.cue("move");
            }
            return true;
        }
        if (root.screen === "load" && enter) {
            const u = root.users[root.load_sel];
            if (u && u.name !== c.user && typeof c.user_request === "function") c.user_request(u.name);
            c.scene = "name";
            root.cue("decide");
            return true;
        }
        if (root.screen === "load" && event.key === Qt.Key_Escape) {
            c.scene = "menu";
            root.cue("cancel");
            return true;
        }
        if (root.screen === "title" && (enter || event.key === Qt.Key_Space)) {
            c.scene = "menu";
            root.cue("start");
            return true;
        }
        if (!ctrl && event.text !== "" && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127) c.scene = "name";
        return false;
    }

    function cue(name) {
        if (root.sound_on) root.ctx.cue(name);
    }

    function claim_sound() {
        if (root.sound_on && !root.dying && !root.ctx.sound_owner) root.ctx.sound_owner = root;
    }

    // Reboot and Shut down need a second press while the note shows; the ctx runs it unless it is a preview.
    function menu_activate() {
        const c = root.ctx;
        const item = root.menu_item;
        if (item === "load") {
            c.scene = "load";
        } else if (item === "options") {
            c.scene = "opt:" + root.opt_items[0];
        } else if (root.menu_note === "armed") {
            c.scene = "menu:" + item + (c.power_live ? ":running" : ":preview");
            if (c.power_live) c.power_request(item);
        } else {
            c.scene = "menu:" + item + ":armed";
        }
    }

    // Firmware and text login need a second press while the note shows; previews only show a note.
    function opt_activate() {
        const c = root.ctx;
        const item = root.opt_item;
        if (item === "back") {
            c.scene = "menu:options";
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
        root.shown = root.page;
        root.claim_sound();
        if (root.granted) root.start_unlock();
    }
    Component.onDestruction: {
        root.dying = true;
        if (root.ctx && root.ctx.sound_owner === root) root.ctx.sound_owner = null;
    }

    function start_unlock() {
        root.caption_chars = 0;
        root.caption_alpha = 1;
        if (root.animate) unlock_anim.restart();
    }

    Loader {
        id: audio_loader
        active: root.owns_sound
        source: Qt.resolvedUrl("mgs2/Mgs2Audio.qml")
        onLoaded: audio_loader.item.track = Qt.binding(() => root.music_track)
    }
    onPhaseChanged: {
        if (root.phase === "saver" && root.can_step) root.ctx.scene = "";
        if (root.phase === "unlock") {
            root.start_unlock();
            if (!root.heard_unlock && root.owns_sound && audio_loader.item) {
                root.heard_unlock = true;
                audio_loader.item.play("accept");
            }
        } else {
            unlock_anim.stop();
            root.captioning = false;
            black.opacity = 0;
        }
    }

    Timer {
        id: note_timer
        interval: 4000
        onTriggered: {
            if (!root.can_step || root.screen !== "menu") return;
            if (root.in_options) {
                if (root.opt_note !== "") root.ctx.scene = "opt:" + root.opt_item;
            } else if (root.menu_note !== "") {
                root.ctx.scene = "menu:" + root.menu_item;
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

    SequentialAnimation {
        id: tx
        ParallelAnimation {
            NumberAnimation { target: root; property: "fold"; to: 0; duration: root.tx_fold_out; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "title_alpha"; to: 0; duration: root.tx_title_out }
        }
        ScriptAction {
            script: {
                root.unfolding = true;
                root.fold = 0;
                root.content_alpha = 0;
                root.title_alpha = root.tx_title_in > 0 ? 0 : 1;
                root.shown = root.page;
            }
        }
        PauseAnimation { duration: 120 }
        NumberAnimation { target: root; property: "fold"; to: 1; duration: root.tx_fold_in; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "title_alpha"; to: 1; duration: root.tx_title_in }
        NumberAnimation { target: root; property: "content_alpha"; to: 1; duration: 150 }
        ScriptAction { script: root.unfolding = false }
    }

    // Green line, then black, the host and time typed out and held, then faded; all inside unlock_ms.
    SequentialAnimation {
        id: unlock_anim
        PauseAnimation { duration: 750 }
        NumberAnimation { target: black; property: "opacity"; from: 0; to: 1; duration: 200 }
        PropertyAction { target: root; property: "captioning"; value: true }
        NumberAnimation { target: root; property: "caption_chars"; from: 0; to: root.caption_text.length; duration: 800 }
        PauseAnimation { duration: 1500 }
        NumberAnimation { target: root; property: "caption_alpha"; to: 0; duration: 300 }
    }

    // A design-space stage, scaled to cover its parent and centred (SVG "slice").
    component Stage: Item {
        id: stage
        readonly property real k: stage.parent ? Math.max(stage.parent.width / 1600, stage.parent.height / 900) : 1
        width: 1600
        height: 900
        x: stage.parent ? (stage.parent.width - 1600) / 2 : 0
        y: stage.parent ? (stage.parent.height - 900) / 2 : 0
        scale: stage.k
    }

    // Text in the menu face; h is the cap height in stage units.
    component Seg: Item {
        id: seg
        property string text
        property real h: 24
        property real sw: 0.75
        property real gap: 3
        property color color: root.field_ink
        readonly property var g: Art.seg(seg.text, seg.gap, seg.sw)
        readonly property real k: seg.h / seg.g.vh
        width: seg.g.vw * seg.k
        height: seg.h

        Shape {
            width: seg.g.vw
            height: seg.g.vh
            scale: seg.k
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: seg.color
                strokeWidth: seg.sw
                capStyle: ShapePath.SquareCap
                joinStyle: ShapePath.MiterJoin
                PathSvg { path: seg.g.d }
            }

            ShapePath {
                strokeWidth: -1
                fillColor: seg.color
                PathSvg { path: seg.g.fill }
            }
        }
    }

    // A DATA LOAD cell; the selected row is red.
    component Cell: Text {
        property bool sel: false
        color: sel ? "#c9313b" : "#8f9892"
        style: sel ? Text.Outline : Text.Normal
        styleColor: "#40c9313b"
        font.family: root.ui_font
        font.pixelSize: 36
        font.letterSpacing: 0.7
    }

    // A NAME ENTRY row: the label, then its value in the menu face; children follow the value.
    component Field: Item {
        id: field
        property string label
        property string value
        property bool active: false
        default property alias extra: value_row.data
        width: 370 + 880
        height: 34

        Seg {
            y: 34 - 24
            text: field.label
            h: 24
            color: field.active ? root.field_ink : "#7c8880"
        }

        Row {
            id: value_row
            x: 370
            y: 34 - 24
            height: 24

            Seg {
                visible: field.value !== ""
                text: field.value
                h: 24
                color: field.active ? "#dfe7e0" : root.field_ink
            }
        }

        Rectangle {
            visible: field.active
            x: 370
            y: 34 + 7
            width: 880
            height: 1.5
            color: "#bfbec8c2"
        }
    }

    // The square cursor beside a menu row.
    component Marker: Rectangle {
        width: 16
        height: 13
        color: "#c7d0c9"
    }

    // A menu heading with its rule underneath.
    component Head: Item {
        id: head
        property string text
        width: head_seg.width
        height: 26

        Seg {
            id: head_seg
            text: head.text
            h: 17
            color: root.field_ink
        }

        Rectangle {
            y: 24
            width: head.width
            height: 1.5
            color: "#b3b9c3bc"
        }
    }

    // The murky grey-green ground, the dark jagged band on the left and film grain; drawn once.
    // The murky grey-green ground: drifting light and dark blobs, the dark jagged band on the left, and scrolling film grain.
    component Murk: Item {
        id: murk
        // Seconds since the skin loaded; it drives the drift and the grain.
        property real t: 0
        width: 1600
        height: 900

        NumberAnimation on t {
            running: root.animate && murk.visible
            from: 0
            to: 3600
            duration: 3600000
            loops: Animation.Infinite
        }

        Rectangle {
            anchors.fill: parent
            color: "#171d1a"
        }

        Repeater {
            model: root.blobs

            Shape {
                id: blob
                required property var modelData
                x: blob.modelData.x + Math.sin(murk.t * blob.modelData.s * 50 + blob.modelData.y) * 60 - blob.modelData.rx
                y: blob.modelData.y - blob.modelData.rx
                width: blob.modelData.rx * 2
                height: blob.modelData.rx * 2
                preferredRendererType: Shape.CurveRenderer
                transform: Scale { origin.y: blob.modelData.rx; yScale: blob.modelData.ry / blob.modelData.rx }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: blob.modelData.rx
                        centerY: blob.modelData.rx
                        focalX: blob.modelData.rx
                        focalY: blob.modelData.rx
                        centerRadius: blob.modelData.rx
                        focalRadius: 0
                        GradientStop { position: 0; color: blob.modelData.light ? Qt.rgba(0.47, 0.54, 0.494, blob.modelData.a) : Qt.rgba(0, 0, 0, Math.min(1, blob.modelData.a * 2.2)) }
                        GradientStop { position: 1; color: "#00000000" }
                    }
                    PathRectangle { width: blob.width; height: blob.height }
                }
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: "#bf040605"
                PathSvg { path: "M330 -10 L390 -10 L390 90 L250 200 L250 420 L130 520 L130 900 L60 900 L60 500 L190 390 L190 170 L330 70 Z" }
            }

            ShapePath {
                strokeWidth: -1
                fillColor: "#99030504"
                PathSvg { path: "M0 610 H1600 V622 H0 Z M0 170 H1600 V176 H0 Z" }
            }
        }

        // One 800x450 grain tile, drawn once and repeated 3x3 so the scroll always covers the stage.
        Canvas {
            id: grain
            width: 800
            height: 450
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const c = getContext("2d");
                const r = Art.rng(7);
                for (let i = 0; i < 6000; i++) {
                    const v = Math.floor(r() * 255);
                    c.fillStyle = "rgba(" + v + "," + v + "," + v + ",0.12)";
                    c.fillRect(Math.floor(r() * 400) * 2, Math.floor(r() * 225) * 2, 2, 2);
                }
            }
        }

        Item {
            x: -((murk.t * 60) % 800)
            y: -((murk.t * 35) % 450)

            Repeater {
                model: 9

                ShaderEffectSource {
                    required property int index
                    x: (index % 3) * 800
                    y: Math.floor(index / 3) * 450
                    width: 800
                    height: 450
                    sourceItem: grain
                    hideSource: true
                }
            }
        }
    }

    // The red painted face behind the title logo; drawn once at quarter size so the scale-up softens it.
    component Paint: Item {
        width: 1600
        height: 900

        Canvas {
            width: 400
            height: 225
            scale: 4
            transformOrigin: Item.TopLeft
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const c = getContext("2d");
                c.scale(0.25, 0.25);
                const r = Art.rng(1987);
                const stroke = (x, y, len, w, ang, col) => {
                    c.strokeStyle = col;
                    c.lineWidth = w;
                    c.lineCap = "round";
                    c.beginPath();
                    c.moveTo(x, y);
                    const mx = x + Math.cos(ang) * len * 0.5 + (r() - 0.5) * 60, my = y + Math.sin(ang) * len * 0.5 + (r() - 0.5) * 60;
                    c.quadraticCurveTo(mx, my, x + Math.cos(ang) * len, y + Math.sin(ang) * len);
                    c.stroke();
                };
                const cx = 800, cy = 520;
                for (let i = 0; i < 300; i++) {
                    const a = r() * Math.PI * 2, d = Math.pow(r(), 0.7);
                    const hot = 1 - d;
                    stroke(cx + Math.cos(a) * d * 470, cy + Math.sin(a) * d * 210, 60 + r() * 160, 14 + r() * 40, -0.9 + (r() - 0.5) * 1.1, "rgba(" + Math.floor(150 + hot * 80) + "," + Math.floor(12 + hot * 22) + "," + Math.floor(14 + hot * 12) + "," + (0.12 + hot * 0.35) + ")");
                }
                for (let i = 0; i < 70; i++) {
                    const a = r() * Math.PI * 2, d = Math.pow(r(), 0.8);
                    stroke(cx + Math.cos(a) * d * 440, cy + Math.sin(a) * d * 200, 40 + r() * 120, 6 + r() * 18, -0.8 + (r() - 0.5) * 1.4, "rgba(10,4,4," + (0.2 + r() * 0.4) + ")");
                }
                for (let i = 0; i < 26; i++) stroke(1180 + r() * 300, 380 + r() * 260, 40 + r() * 130, 3 + r() * 10, -0.5 + (r() - 0.5), "rgba(160,24,20," + (0.15 + r() * 0.25) + ")");
                c.globalCompositeOperation = "destination-in";
                const fade = c.createRadialGradient(cx, cy, 120, cx, cy, 620);
                fade.addColorStop(0, "rgba(0,0,0,1)");
                fade.addColorStop(1, "rgba(0,0,0,0)");
                c.fillStyle = fade;
                c.fillRect(0, 0, 1600, 900);
                c.globalCompositeOperation = "source-over";
            }
        }
    }

    // The title art: a red hex grid on the right, and the user's face cut to four reds, else the painted smear.
    component TitleArt: Item {
        id: art
        // The face_urls entry being tried; past the end means none loaded.
        property int face_at: 0
        readonly property string face_url: root.face_urls[art.face_at] || ""
        readonly property bool has_face: face_image.status === Image.Ready && face_shader.status !== ShaderEffect.Error
        width: 1600
        height: 900

        Canvas {
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const c = getContext("2d");
                const R = 34, w = Math.sqrt(3) * R;
                c.lineWidth = 1.6;
                for (let row = -1; row < 16; row++) {
                    for (let col = -1; col < 30; col++) {
                        const x = 560 + col * w + (row % 2 ? w / 2 : 0), y = 60 + row * R * 1.5;
                        const d = Math.hypot((x - 1180) / 1.25, y - 430) / 560;
                        if (d >= 1) continue;
                        c.strokeStyle = "rgba(200,36,28," + (0.34 * Math.pow(1 - d, 1.6)).toFixed(3) + ")";
                        c.beginPath();
                        for (let i = 0; i < 6; i++) {
                            const a = Math.PI / 6 + i * Math.PI / 3;
                            if (i === 0) c.moveTo(x + R * Math.cos(a), y + R * Math.sin(a));
                            else c.lineTo(x + R * Math.cos(a), y + R * Math.sin(a));
                        }
                        c.closePath();
                        c.stroke();
                    }
                }
            }
        }

        Paint {
            visible: !art.has_face
        }

        // Cut to four reds and faded at 110px, then scaled up so the stretch softens it like paint.
        Item {
            id: face
            readonly property int n: 110
            readonly property real size: 960
            width: face.n
            height: face.n
            x: 780 - face.n / 2
            y: 500 - face.n / 2
            scale: face.size / face.n
            rotation: -5.7
            visible: art.has_face
            layer.enabled: true
            layer.smooth: true

            Image {
                id: face_image
                anchors.fill: parent
                source: art.face_url
                sourceSize: Qt.size(face.n * 2, face.n * 2)
                fillMode: Image.PreserveAspectCrop
                visible: false
                onStatusChanged: if (face_image.status === Image.Error) art.face_at += 1
            }

            ShaderEffect {
                id: face_shader
                anchors.fill: parent
                property variant source: face_image
                fragmentShader: Qt.resolvedUrl("mgs2/face.frag.qsb")
            }

            Canvas {
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                onPaint: {
                    const c = getContext("2d");
                    const n = face.n, u = face.size / n, r = Art.rng(1987);
                    c.lineCap = "round";
                    for (let i = 0; i < 60; i++) {
                        const a = r() * Math.PI * 2, d = 0.75 * Math.pow(r(), 0.8), sx = n / 2 + Math.cos(a) * d * 380 / u, sy = n / 2 + Math.sin(a) * d * 320 / u, ang = -0.8 + (r() - 0.5) * 1.2, len = (40 + r() * 110) / u;
                        c.strokeStyle = "rgba(10,4,4," + (0.12 + r() * 0.25) + ")";
                        c.lineWidth = (5 + r() * 14) / u;
                        c.beginPath();
                        c.moveTo(sx, sy);
                        c.lineTo(sx + Math.cos(ang) * len, sy + Math.sin(ang) * len);
                        c.stroke();
                    }
                }
            }
        }
    }

    // Everything below draws on the 1600x900 stage.
    Rectangle {
        anchors.fill: parent
        color: root.shown === "unlock" ? "#000000" : "#0c100e"
    }

    Stage {
        id: stage

        Murk {
            opacity: root.shown === "load" ? 0.45 : 1
            visible: root.shown !== "unlock"
        }

        Rectangle {
            anchors.fill: parent
            visible: root.shown === "saver"
            color: "#66000000"
        }

        // The grey structure diagram behind NAME ENTRY.
        Item {
            anchors.fill: parent
            opacity: root.shown === "name" ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 500 } }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: "#598b9990"
                    strokeWidth: 1.5
                    PathSvg { path: root.diagram.d }
                }
            }

            Repeater {
                model: root.diagram.labels

                Text {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y - 15
                    text: modelData.t
                    color: "#808b9990"
                    font.family: root.ui_font
                    font.pixelSize: 17
                }
            }
        }

        // Red molecule line art, fading in one after another on each screen.
        Repeater {
            model: root.molecules

            Item {
                id: mol
                required property var modelData
                readonly property bool on: (root.shown === "opt" ? "menu" : root.shown) === mol.modelData.set
                anchors.fill: parent
                opacity: mol.on ? 0.55 + mol.modelData.i * 0.1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    enabled: root.animate
                    SequentialAnimation {
                        PauseAnimation { duration: mol.on ? mol.modelData.i * 450 + 200 : 0 }
                        NumberAnimation { duration: 900 }
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: "#40d63126"
                        strokeWidth: 7
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: mol.modelData.d }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.mol_red
                        strokeWidth: 2.2
                        joinStyle: ShapePath.MiterJoin
                        PathSvg { path: mol.modelData.d }
                    }
                }

                Repeater {
                    model: mol.modelData.labels

                    Text {
                        required property var modelData
                        x: modelData.x
                        y: modelData.y - 14
                        text: modelData.t
                        color: root.mol_red
                        font.family: root.ui_font
                        font.pixelSize: 15
                    }
                }
            }
        }

        // Status codes down the right: battery, unread count and weather among the noise.
        Item {
            anchors.fill: parent
            visible: ["title", "menu", "opt", "name"].indexOf(root.shown) >= 0

            Repeater {
                model: 20

                Seg {
                    required property int index
                    x: 1030
                    y: 30 + index * 46
                    text: "--"
                    h: 5
                    sw: 0.9
                    color: "#b8c4bc"
                    opacity: 0.22
                }
            }

            Repeater {
                model: root.code_labels

                Item {
                    id: code
                    required property int index
                    required property string modelData
                    readonly property real code_y: 36 + code.index * 128 + root.code_offsets[code.index]

                    Seg {
                        x: 1210
                        y: code.code_y
                        text: code.modelData
                        h: 9
                        sw: 0.8
                        gap: 2.2
                        color: "#b8c4bc"
                        opacity: 0.3
                    }

                    Rectangle {
                        x: 1200
                        y: code.code_y + 22
                        width: 180
                        height: 1
                        color: "#2e9aa69e"
                    }
                }
            }

            Repeater {
                model: 6

                Seg {
                    required property int index
                    x: 1000 + index * 150
                    y: 700
                    text: "N"
                    h: 10
                    sw: 0.8
                    color: "#b8c4bc"
                    opacity: 0.25
                }
            }
        }

        // The frame lines, folded and unfolded between pages like the game's menus.
        Item {
            anchors.fill: parent
            visible: root.is_framed(root.shown) && root.fold > 0.001

            Rectangle {
                x: root.fb.v
                width: 1.5
                height: 900
                color: root.line_color
                opacity: 0.55
            }

            Rectangle {
                y: root.fb.y1
                width: 1600
                height: 1.5
                color: root.line_color
                opacity: 0.55
            }

            Rectangle {
                x: root.fb.r0
                y: root.fb.y0
                width: root.fb.r1 - root.fb.r0
                height: root.fb.y1 - root.fb.y0
                color: "#14aabab0"

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: "#8c9eaca3"
                }
            }

            Rectangle {
                x: root.fb.x0
                y: root.fb.y0
                width: root.fb.x1 - root.fb.x0
                height: root.fb.y1 - root.fb.y0
                color: "transparent"
                border.width: 1.5
                border.color: "#8c9eaca3"
            }
        }

        Loader {
            anchors.fill: parent
            active: root.shown === "title"
            opacity: root.title_alpha
            sourceComponent: title_view
        }

        // Framed pages show only inside the box and rail, so folding the box wipes them away.
        Item {
            id: page_clip
            x: root.fb.v
            y: root.fb.y0
            width: Math.max(0, root.fb.x1 + 20 - root.fb.v)
            height: Math.max(0, root.fb.y1 - root.fb.y0)
            clip: true
            visible: root.is_framed(root.shown)

            Item {
                x: -page_clip.x
                y: -page_clip.y
                width: 1600
                height: 900
                opacity: root.unfolding ? root.content_alpha : 1

                Loader {
                    anchors.fill: parent
                    active: root.shown === "menu" || root.shown === "opt"
                    sourceComponent: menu_view
                }

                Loader {
                    anchors.fill: parent
                    active: root.shown === "load"
                    sourceComponent: load_view
                }

                Loader {
                    anchors.fill: parent
                    active: root.shown === "name"
                    sourceComponent: name_view
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: root.shown === "saver"
            sourceComponent: saver_view
        }

        Text {
            x: 158
            y: 790
            visible: root.is_framed(root.shown)
            opacity: root.unfolding ? root.content_alpha : root.fold
            width: 1300
            text: root.desc[0]
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.desc[1] === "red" ? "#ff5a55" : root.desc[1] === "green" ? "#7fe39a" : "#eef0ee"
            style: Text.Outline
            styleColor: root.desc[1] === "green" ? "#3062d49c" : "#000000"
            font.family: root.ui_font
            font.pixelSize: 40
        }

        // The unlock caption, typed out on black like the game's opening cards.
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 200
            y: 790
            visible: root.shown === "unlock"
            opacity: root.caption_alpha
            text: root.caption_text.slice(0, root.animate ? root.caption_chars : root.caption_text.length)
            textFormat: Text.PlainText
            color: "#f2f2f2"
            font.family: root.ui_font
            font.pixelSize: 34
        }
    }

    // A red molecule that fades in somewhere, drifts and turns a little, fades out, then comes back elsewhere.
    component Drifter: Item {
        id: drifter
        required property int index
        readonly property int life: 9000 + drifter.index * 900
        property var mol: root.saver_pool[drifter.index]
        property real x0: 0
        property real y0: 0
        property real x1: 0
        property real y1: 0
        property real r0: 0
        property real turn: 0
        property real t: root.animate ? 0 : 0.5
        x: drifter.x0 + (drifter.x1 - drifter.x0) * drifter.t
        y: drifter.y0 + (drifter.y1 - drifter.y0) * drifter.t
        rotation: drifter.r0 + drifter.turn * drifter.t
        transformOrigin: Item.TopLeft
        opacity: 0.7 * Math.min(1, drifter.t / 0.2, (1 - drifter.t) / 0.2)

        function respawn() {
            drifter.mol = root.saver_pool[Math.floor(Math.random() * root.saver_pool.length)];
            drifter.x0 = 100 + Math.random() * 1300;
            drifter.y0 = 80 + Math.random() * 700;
            const a = Math.random() * Math.PI * 2, d = 120 + Math.random() * 200;
            drifter.x1 = drifter.x0 + Math.cos(a) * d;
            drifter.y1 = drifter.y0 + Math.sin(a) * d * 0.6;
            drifter.r0 = (Math.random() - 0.5) * 60;
            drifter.turn = (Math.random() - 0.5) * 30;
        }

        Component.onCompleted: drifter.respawn()

        SequentialAnimation {
            running: root.animate
            PauseAnimation { duration: drifter.index * 2200 }
            SequentialAnimation {
                loops: Animation.Infinite
                ScriptAction { script: drifter.respawn() }
                NumberAnimation { target: drifter; property: "t"; from: 0; to: 1; duration: drifter.life; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 800 }
            }
        }

        Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: "#40d63126"
                strokeWidth: 7
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: drifter.mol.d }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.mol_red
                strokeWidth: 2.2
                joinStyle: ShapePath.MiterJoin
                PathSvg { path: drifter.mol.d }
            }
        }

        Repeater {
            model: drifter.mol.labels

            Text {
                required property var modelData
                x: modelData.x
                y: modelData.y - 14
                text: modelData.t
                color: root.mol_red
                font.family: root.ui_font
                font.pixelSize: 15
            }
        }
    }

    Component {
        id: saver_view

        // The title with its text gone: dimmed paint, drifting molecules and a faint wandering clock.
        Item {
            id: saver
            property real t: 0

            NumberAnimation on t {
                running: root.animate
                from: 0
                to: 3600
                duration: 3600000
                loops: Animation.Infinite
            }

            TitleArt {
                opacity: 0.45
            }

            Repeater {
                model: 5

                Drifter {}
            }

            Seg {
                x: 1300 - width / 2 + Math.sin(saver.t / 23) * 160
                y: 780 + Math.sin(saver.t / 17) * 50
                text: root.clock_text
                h: 30
                gap: 3.2
                color: "#c9d1c9"
                opacity: 0.3
            }
        }
    }

    Component {
        id: title_view

        Item {
            TitleArt {
                opacity: 0.8
            }

            Column {
                y: 70
                width: 1600
                spacing: 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: font.letterSpacing / 2
                    text: "TACTICAL TILING ACTION"
                    color: "#b4b7b6"
                    font.family: root.ui_font
                    font.bold: true
                    font.pixelSize: 19
                    font.letterSpacing: 25.8
                }

                Item {
                    width: 1
                    height: 28
                }

                Item {
                    id: logo
                    readonly property real gap: 44
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: logo_metrics.advanceWidth + logo.gap + two_metrics.advanceWidth
                    height: 160

                    TextMetrics {
                        id: logo_metrics
                        text: "OASIS GEAR SOLID"
                        font.family: root.logo_font
                        font.weight: Font.Medium
                        font.pixelSize: 190
                    }

                    TextMetrics {
                        id: two_metrics
                        text: "2"
                        font: logo_metrics.font
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: -1
                            fillGradient: LinearGradient {
                                y1: 20
                                y2: 160
                                GradientStop { position: 0; color: "#b4b6b5" }
                                GradientStop { position: 0.55; color: "#a2a3a2" }
                                GradientStop { position: 1; color: "#87898a" }
                            }
                            PathText { text: logo_metrics.text; font: logo_metrics.font }
                        }

                        ShapePath {
                            strokeWidth: -1
                            fillColor: "#ab2121"
                            PathText { x: logo_metrics.advanceWidth + logo.gap; text: "2"; font: logo_metrics.font }
                        }
                    }

                    Text {
                        x: logo_metrics.advanceWidth + 6
                        y: 18
                        text: "®"
                        color: "#c4c6c5"
                        font.family: root.ui_font
                        font.pixelSize: 30
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        text: root.distro.toUpperCase()
                        color: "#b9bcbb"
                        font.family: root.ui_font
                        font.bold: true
                        font.pixelSize: 44
                        font.letterSpacing: 13.2
                    }

                    Text {
                        text: "TM"
                        color: "#b9bcbb"
                        font.family: root.ui_font
                        font.bold: true
                        font.pixelSize: 16
                    }
                }
            }

            Seg {
                x: (1600 - width) / 2
                y: 698
                text: "PRESS START BUTTON"
                h: 24
                gap: 3.2
                color: "#c9d1c9"

                SequentialAnimation on opacity {
                    running: root.animate
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 1200; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 1200; easing.type: Easing.InOutSine }
                }
            }

            Text {
                y: 780
                width: 1600
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.StyledText
                text: "<font color=\"#d4d8d6\">" + root.clock_text + "</font>&nbsp;&nbsp;&nbsp; " + Qt.formatDate(root.now, "dddd, MMMM d, yyyy")
                color: "#b3b7b5"
                font.family: root.ui_font
                font.pixelSize: 27
            }
        }
    }

    Component {
        id: menu_view

        Item {
            id: menu
            readonly property bool opts: root.shown === "opt"
            readonly property var items: menu.opts ? root.opt_items : root.menu_items
            readonly property string sel: menu.opts ? root.opt_item : root.menu_item
            readonly property real list_y: menu.opts ? 150 : 104

            Head {
                x: 178
                y: 96
                visible: menu.opts
                text: "OPTIONS"
            }

            Repeater {
                model: menu.items

                Seg {
                    required property int index
                    required property string modelData
                    x: 178
                    y: menu.list_y + index * 53
                    text: (menu.opts ? root.opt_label(modelData) : root.menu_labels[modelData]) || ""
                    h: 26
                    color: modelData === menu.sel ? root.item_on : root.item_off
                }
            }

            Marker {
                x: 118
                y: menu.list_y + Math.max(0, menu.items.indexOf(menu.sel)) * 53 + 7

                Behavior on y {
                    enabled: root.animate
                    NumberAnimation { duration: 90 }
                }
            }
        }
    }

    Component {
        id: load_view

        Item {
            id: load
            readonly property real uptime_base: parseFloat(uptime_file.text().split(" ")[0]) || 0
            readonly property real read_at: Date.now()
            property int uptime: 0

            FileView {
                id: uptime_file
                path: "/proc/uptime"
                blockLoading: true
                printErrors: false
            }

            Timer {
                interval: 1000
                repeat: true
                running: true
                triggeredOnStart: true
                onTriggered: load.uptime = Math.floor(load.uptime_base + (Date.now() - load.read_at) / 1000)
            }

            function pad(n, w) {
                return String(n).padStart(w, "0");
            }

            Head {
                x: 180
                y: 92
                text: "DATA LOAD"
            }

            Column {
                x: 180
                y: 150
                width: 1280

                Item {
                    width: parent.width
                    height: 50

                    Text {
                        y: 50 - 12 - height
                        text: "MEMORY CARD slot1"
                        color: "#eceeed"
                        font.family: root.ui_font
                        font.bold: true
                        font.pixelSize: 38
                    }

                    Row {
                        anchors.right: parent.right
                        y: 14
                        spacing: 22

                        Seg { anchors.verticalCenter: parent.verticalCenter; text: "PAGE"; h: 16; color: "#c8cfc9" }
                        Seg { anchors.verticalCenter: parent.verticalCenter; text: "01/01"; h: 24; color: "#c8cfc9" }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1.5
                        color: "#bfbec8c2"
                    }
                }

                Item {
                    width: parent.width
                    height: 64

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.host
                        color: "#e6e9e7"
                        font.family: root.ui_font
                        font.pixelSize: 38
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1.5
                        color: "#bfbec8c2"
                    }
                }

                Item {
                    width: 1
                    height: 22
                }

                Repeater {
                    model: root.users

                    Item {
                        id: row
                        required property int index
                        required property var modelData
                        readonly property bool sel: row.index === root.load_sel
                        width: 1280
                        height: 50

                        Cell { sel: row.sel; x: 0; text: load.pad(row.index, 2) }
                        Cell { sel: row.sel; x: 110; width: 380; elide: Text.ElideRight; text: row.modelData.name }
                        Cell { sel: row.sel; x: 510; text: root.day_text.replace(/\//g, ".") }
                        Cell {
                            sel: row.sel
                            anchors.right: parent.right
                            visible: row.sel
                            text: load.pad(Math.floor(load.uptime / 3600), 4) + ":" + load.pad(Math.floor(load.uptime / 60) % 60, 2) + ":" + load.pad(load.uptime % 60, 2)
                        }
                    }
                }
            }

            Marker {
                x: 108
                y: 150 + 50 + 64 + 22 + root.load_sel * 50 + 16
            }
        }
    }

    Component {
        id: name_view

        Item {
            id: name
            readonly property bool ready: (root.typed > 0 && !root.checking) || root.granted

            Head {
                x: 178
                y: 96
                text: "NAME ENTRY"
            }

            Column {
                x: 178
                y: 170
                spacing: 26

                Field { label: "CODENAME :"; value: root.user_name }

                Field {
                    label: "PASSWORD :"
                    value: "#".repeat(Math.min(root.granted || root.checking ? Math.max(root.typed, 8) : root.typed, 40))
                    active: true

                    Rectangle {
                        visible: !root.checking && !root.granted
                        width: 32
                        height: 26
                        color: "transparent"

                        Rectangle {
                            x: 10
                            y: -1
                            width: 22
                            height: 26
                            color: "#dfe7e0"

                            SequentialAnimation on opacity {
                                running: root.animate
                                loops: Animation.Infinite
                                PropertyAction { value: 1 }
                                PauseAnimation { duration: 500 }
                                PropertyAction { value: 0 }
                                PauseAnimation { duration: 500 }
                            }
                        }
                    }
                }

                Field { label: "HOST :"; value: root.host }
                Field { label: "DATE :"; value: root.day_text }
            }

            Rectangle {
                x: 118
                y: 735
                width: 16
                height: 13
                color: "#c7d0c9"
            }

            Seg {
                x: 178
                y: 728
                text: "OK"
                h: 26
                color: name.ready ? root.ok_green : "#56615a"
            }
        }
    }

    Rectangle {
        id: flash
        anchors.fill: parent
        visible: root.phase === "wrong" && root.shown === "name"
        color: "#c01a1a"
        opacity: root.animate ? 0 : 0.12

        NumberAnimation {
            id: flash_anim
            target: flash
            property: "opacity"
            from: 0.45
            to: 0
            duration: 700
            easing.type: Easing.OutQuad
        }
    }

    Rectangle {
        id: black
        anchors.fill: parent
        color: "#000000"
        opacity: 0
        visible: opacity > 0 && !root.captioning
    }

    // Scanlines at output resolution, then a soft vignette.
    Canvas {
        id: scan
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onWidthChanged: scan.requestPaint()
        onHeightChanged: scan.requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.clearRect(0, 0, width, height);
            c.fillStyle = "rgba(0,0,0,0.28)";
            for (let y = 2; y < height; y += 3) c.fillRect(0, y, width, 1);
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: root.height * 0.45
                focalX: root.width / 2
                focalY: root.height * 0.45
                centerRadius: Math.hypot(root.width, root.height) / 2
                focalRadius: 0
                GradientStop { position: 0.55; color: "#00000000" }
                GradientStop { position: 1; color: "#8c000000" }
            }
            PathRectangle { width: root.width; height: root.height }
        }
    }
}
