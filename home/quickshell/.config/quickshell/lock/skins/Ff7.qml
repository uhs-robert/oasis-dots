// home/quickshell/.config/quickshell/lock/skins/Ff7.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../theme"

// Final Fantasy VII: the Buster Sword title menu, a save file per user, the password as a name entry and a battle swirl to unlock.
Item {
    id: root

    property var ctx: null
    readonly property int unlock_ms: 1600

    readonly property bool animate: !!root.ctx && root.ctx.animate
    readonly property string phase: root.ctx ? root.ctx.phase : "idle"
    readonly property bool can_step: !!root.ctx && "scene" in root.ctx
    readonly property string scene: root.can_step ? root.ctx.scene : ""
    readonly property int typed: root.ctx ? root.ctx.buffer_length : 0
    readonly property bool checking: !!root.ctx && root.ctx.checking
    readonly property string prompt: root.ctx && root.ctx.prompt ? root.ctx.prompt : ""
    readonly property bool login: !!root.ctx && root.ctx.login === true

    // title, files, pw, saver or unlock.
    readonly property string screen: {
        if (root.phase === "saver") return "saver";
        if (root.phase === "unlock") return "unlock";
        if (root.typed > 0 || root.checking || root.phase === "wrong" || root.prompt !== "" || root.scene === "pw") return "pw";
        if (root.scene.startsWith("files")) return "files";
        return "title";
    }
    readonly property bool on_new: root.scene === "title:new"

    // Users as {name, full}; the lock only ever has its own.
    readonly property var users: {
        const list = root.ctx && Array.isArray(root.ctx.users) && root.ctx.users.length > 0 ? root.ctx.users : [{ name: root.ctx ? root.ctx.user : "", full: "" }];
        return list;
    }
    readonly property int user_index: Math.max(0, root.users.findIndex(u => root.ctx && u.name === root.ctx.user))
    readonly property var current: root.users[root.user_index] || { name: "", full: "" }
    readonly property int slot_count: Math.max(3, root.users.length)
    readonly property int file_sel: root.scene.startsWith("files:") ? Math.min(root.slot_count - 1, Math.max(0, parseInt(root.scene.split(":")[1]) || 0)) : root.user_index
    readonly property int page: Math.floor(root.file_sel / 3) * 3

    readonly property bool sound_on: !!root.ctx && root.ctx.sound === true
    readonly property bool owns_sound: root.sound_on && root.ctx.sound_owner === root
    readonly property string music_track: !root.owns_sound || root.ctx.music === false || root.phase === "saver" || root.phase === "unlock" ? "" : "title"
    property int heard_typed: 0
    property bool heard_unlock: false
    property bool dying: false

    readonly property string ui_font: "Nunito"
    readonly property color white: Theme.fg_strong
    readonly property color shadow: Theme.bg_shadow
    readonly property color label: Qt.tint(Theme.blue, Qt.alpha(Theme.theme_primary_light, 0.8))
    readonly property color dim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_strong, 0.6))
    readonly property color rim: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.fg_strong, 0.85))
    readonly property color win_top: Qt.tint(Theme.bg_shadow, Qt.alpha(Theme.blue, 0.48))
    readonly property color win_mid: Qt.tint(Theme.bg_shadow, Qt.alpha(Theme.theme_primary_strong, 0.3))
    readonly property color win_end: Qt.tint(Theme.bg_shadow, Qt.alpha(Theme.theme_primary_strong, 0.14))

    // Lifestream: ribbons of braided strands flowing across the screen, split into a back and a front canvas so they weave past the sword.
    readonly property bool stream_on: root.screen === "saver"
    property real stream_t: 0
    // Canvas resolution against the screen; the glow hides the upscale.
    readonly property real stream_res: 0.5
    readonly property var stream: {
        let seed = 7;
        const rnd = () => {
            seed = (seed * 16807) % 2147483647;
            return (seed - 1) / 2147483646;
        };
        const bands = [
            { y: 300, amp: 70, k: 0.0042, w: 0.35, spread: 46, twist: 0.0031, tilt: -0.06, n: 11, ph: 0.4 },
            { y: 520, amp: 105, k: 0.0033, w: 0.28, spread: 62, twist: 0.0026, tilt: 0.05, n: 14, ph: 2.1 },
            { y: 720, amp: 60, k: 0.0048, w: 0.4, spread: 38, twist: 0.0036, tilt: -0.03, n: 9, ph: 4.2 }
        ];
        for (const b of bands) {
            b.strands = [];
            for (let i = 0; i < b.n; i++) b.strands.push({ o: (i / (b.n - 1) - 0.5) * 2, wob: 3 + rnd() * 8, f: rnd() * 6, lit: 0.35 + rnd() * 0.65 });
            b.sparks = [];
            for (let i = 0; i < 55; i++) b.sparks.push({ u: rnd(), o: (rnd() * 2 - 1) * 1.5, v: 40 + rnd() * 70, tw: rnd() * 6, size: 0.8 + rnd() * 1.8 });
        }
        const motes = [];
        for (let i = 0; i < 70; i++) motes.push({ x: rnd() * 1600, y: rnd() * 900, v: 10 + rnd() * 26, sway: 10 + rnd() * 40, f: 0.2 + rnd() * 0.5, size: 0.8 + rnd() * 1.8 });
        return { bands: bands, motes: motes };
    }

    // A band's point at design x for strand offset o, and its depth (over the sword when positive).
    function band_at(b, x, o, wob, f, t) {
        const centre = b.y + (x - 800) * b.tilt + b.amp * Math.sin(b.k * x - b.w * t + b.ph) + b.amp * 0.35 * Math.sin(b.k * 2.3 * x + b.w * 0.6 * t);
        const pinch = Math.cos(b.twist * x - b.w * 1.4 * t + b.ph * 2);
        return [centre + b.spread * o * pinch + wob * Math.sin(x * 0.011 + f + t * 0.7), Math.sin(x * 0.0024 + b.ph * 1.7 + t * 0.15)];
    }

    function paint_stream(ctx, w, h, front) {
        ctx.reset();
        const k = Math.max(w / 1600, h / 900);
        const ox = (w - 1600 * k) / 2;
        const oy = (h - 900 * k) / 2;
        const t = root.stream_t;
        const green = String(Theme.ok), teal = String(Theme.hint), white = String(root.white);
        ctx.globalCompositeOperation = "lighter";
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        if (!front) {
            ctx.fillStyle = green;
            for (const m of root.stream.motes) {
                const y = ((m.y - m.v * t) % 900 + 900) % 900;
                const x = m.x + Math.sin(t * m.f + m.x) * m.sway;
                ctx.globalAlpha = 0.25 + 0.25 * Math.sin(t * m.f * 3 + m.y);
                ctx.beginPath();
                ctx.arc(ox + x * k, oy + y * k, m.size * k, 0, Math.PI * 2);
                ctx.fill();
            }
        }
        const fade = (c) => {
            const g = ctx.createLinearGradient(0, 0, w, 0);
            g.addColorStop(0, "transparent");
            g.addColorStop(0.12, c);
            g.addColorStop(0.88, c);
            g.addColorStop(1, "transparent");
            return g;
        };
        const step = 40;
        // Traces strand offset o across the screen; where the depth side flips, both canvases meet at the segment's midpoint.
        const trace = (b, o, wob, f) => {
            ctx.beginPath();
            let prev = null;
            for (let x = -40; x <= 1640; x += step) {
                const [y, d] = root.band_at(b, x, o, wob, f, t);
                const mine = (d >= 0) === front;
                const px = ox + x * k, py = oy + y * k;
                if (prev && prev.mine !== mine) {
                    const mx = (prev.x + px) / 2, my = (prev.y + py) / 2;
                    if (mine) ctx.moveTo(mx, my);
                    else ctx.lineTo(mx, my);
                }
                if (mine) {
                    if (prev && prev.mine) ctx.lineTo(px, py);
                    else if (!prev) ctx.moveTo(px, py);
                    else ctx.lineTo(px, py);
                }
                prev = { x: px, y: py, mine: mine };
            }
        };
        for (const b of root.stream.bands) {
            ctx.lineCap = "butt";
            ctx.strokeStyle = fade(green);
            ctx.globalAlpha = 0.07;
            ctx.lineWidth = b.spread * 1.6 * k;
            trace(b, 0, 0, 0);
            ctx.stroke();
            ctx.globalAlpha = 0.1;
            ctx.lineWidth = b.spread * 0.6 * k;
            trace(b, 0, 0, 0);
            ctx.stroke();
            ctx.lineCap = "round";
            for (const s of b.strands) {
                ctx.strokeStyle = fade(s.lit > 0.85 ? white : s.lit > 0.55 ? teal : green);
                ctx.globalAlpha = 0.18 * s.lit;
                ctx.lineWidth = 5 * k;
                trace(b, s.o, s.wob, s.f);
                ctx.stroke();
                ctx.globalAlpha = 0.75 * s.lit;
                ctx.lineWidth = 1.3 * k;
                trace(b, s.o, s.wob, s.f);
                ctx.stroke();
            }
            for (const [color, bright] of [[green, false], [white, true]]) {
                ctx.fillStyle = color;
                ctx.globalAlpha = bright ? 0.9 : 0.7;
                ctx.beginPath();
                b.sparks.forEach((p, i) => {
                    if ((i % 4 === 0) !== bright) return;
                    const x = ((p.u * 1760 + p.v * t) % 1760) - 80;
                    const [y, d] = root.band_at(b, x, p.o, 0, 0, t);
                    if ((d >= 0) !== front) return;
                    const r = p.size * k * (0.6 + 0.4 * Math.sin(t * 2.5 + p.tw));
                    if (r <= 0) return;
                    ctx.moveTo(ox + x * k + r, oy + y * k);
                    ctx.arc(ox + x * k, oy + y * k, r, 0, Math.PI * 2);
                });
                ctx.fill();
            }
        }
    }

    function display_name(u) {
        const full = String(u && u.full || "").split(",")[0].trim().split(/\s+/)[0];
        const name = full || String(u && u.name || "");
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function face_urls(name) {
        return name && root.ctx && typeof root.ctx.face_urls === "function" ? root.ctx.face_urls(name) : [];
    }

    function cue(name) {
        if (root.sound_on) root.ctx.cue(name);
    }

    function claim_sound() {
        if (root.sound_on && !root.dying && !root.ctx.sound_owner) root.ctx.sound_owner = root;
    }

    function handle_key(event) {
        const c = root.ctx;
        if (!root.can_step || c.buffer_length > 0 || c.checking || c.granted) return false;
        const ctrl = (event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier);
        const enter = !ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space);
        const up = event.key === Qt.Key_Up || event.key === Qt.Key_Down;
        const printable = !ctrl && event.text !== "" && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127;
        if (root.screen === "pw") {
            if (event.key !== Qt.Key_Escape) return false;
            c.scene = "files:" + root.user_index;
            root.cue("cancel");
            return true;
        }
        if (root.screen === "files") {
            if (up) {
                const step = event.key === Qt.Key_Down ? 1 : root.slot_count - 1;
                c.scene = "files:" + (root.file_sel + step) % root.slot_count;
                root.cue("cursor");
                return true;
            }
            if (enter) {
                const u = root.users[root.file_sel];
                if (!u) {
                    root.cue("buzzer");
                    return true;
                }
                if (u.name !== c.user && typeof c.user_request === "function") c.user_request(u.name);
                c.scene = "pw";
                root.cue("select");
                return true;
            }
            if (event.key === Qt.Key_Escape) {
                c.scene = "";
                root.cue("cancel");
                return true;
            }
            if (printable) {
                const u = root.users[root.file_sel];
                if (u && u.name !== c.user && typeof c.user_request === "function") c.user_request(u.name);
                c.scene = "pw";
            }
            return false;
        }
        if (root.screen !== "title") return false;
        if (up) {
            c.scene = root.on_new ? "" : "title:new";
            root.cue("cursor");
            return true;
        }
        if (enter) {
            if (root.on_new) {
                root.cue("buzzer");
            } else {
                c.scene = "files:" + root.user_index;
                root.cue("select");
            }
            return true;
        }
        if (printable) c.scene = "pw";
        return false;
    }

    // Plays the swirl, or pins its last frame when loops are off; leaving unlock puts the title back.
    function set_warp() {
        warp.stop();
        const still = root.phase === "unlock" && !root.animate;
        swirl.t = still ? 1 : 0;
        flash.opacity = still ? 0.85 : 0;
        scene_layer.rotation = 0;
        scene_layer.scale = 1;
        if (root.phase === "unlock" && root.animate) warp.start();
    }

    clip: true
    Component.onCompleted: {
        root.claim_sound();
        root.set_warp();
    }
    Component.onDestruction: {
        root.dying = true;
        if (root.ctx && root.ctx.sound_owner === root) root.ctx.sound_owner = null;
    }

    Loader {
        id: audio_loader
        active: root.owns_sound
        source: Qt.resolvedUrl("ff7/Ff7Audio.qml")
        onLoaded: audio_loader.item.track = Qt.binding(() => root.music_track)
    }

    onPhaseChanged: {
        if (root.phase === "saver" && root.can_step) root.ctx.scene = "";
        if (root.phase === "unlock") {
            if (!root.heard_unlock && root.owns_sound && audio_loader.item) audio_loader.item.play("swirl");
            root.heard_unlock = true;
        }
        root.set_warp();
    }

    Connections {
        target: root.ctx
        ignoreUnknownSignals: true
        function onBuffer_lengthChanged() {
            if (root.owns_sound && root.typed > root.heard_typed && audio_loader.item) audio_loader.item.play("cursor");
            root.heard_typed = root.typed;
            if (root.typed > 0) root.heard_unlock = false;
        }
        function onSound_ownerChanged() { root.claim_sound(); }
        function onCue(name) {
            if (root.owns_sound && audio_loader.item) audio_loader.item.play(name);
        }
        function onRejected() {
            if (root.owns_sound && audio_loader.item) audio_loader.item.play("buzzer");
            if (root.can_step) root.ctx.scene = "pw";
            if (root.animate) {
                shake.restart();
                miss_pop.restart();
            }
        }
    }

    // A design-space stage centred on its parent: `cover` fills it and crops, else it fits whole.
    component Stage: Item {
        id: stage
        property bool cover: false
        readonly property real kx: stage.parent ? stage.parent.width / 1600 : 1
        readonly property real ky: stage.parent ? stage.parent.height / 900 : 1
        width: 1600
        height: 900
        x: stage.parent ? (stage.parent.width - 1600) / 2 : 0
        y: stage.parent ? (stage.parent.height - 900) / 2 : 0
        scale: stage.cover ? Math.max(stage.kx, stage.ky) : Math.min(stage.kx, stage.ky)
    }

    // Menu text with the game's hard drop shadow.
    component SText: Text {
        id: st
        property int wght: 700
        color: root.white
        font.family: root.ui_font
        font.pixelSize: 24
        font.weight: st.wght
        font.variableAxes: ({ wght: st.wght })
        renderType: Text.QtRendering
        Text {
            x: 2.4
            y: 2.4
            z: -1
            width: st.width
            text: st.text
            font: st.font
            color: root.shadow
            renderType: Text.QtRendering
            horizontalAlignment: st.horizontalAlignment
            elide: st.elide
        }
    }

    component Lbl: SText {
        color: root.label
    }

    // The blue menu window: 135deg gradient, light rim, dark inner ring and a drop shadow.
    component Win: Item {
        id: win
        default property alias content: body.data
        property real pad: 20
        readonly property real r: 11

        Rectangle {
            x: 6
            y: 7
            width: win.width
            height: win.height
            radius: win.r
            color: Qt.alpha(root.shadow, 0.7)
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 3.5
                strokeColor: root.rim
                fillGradient: LinearGradient {
                    x1: win.width / 2 - (win.width + win.height) / 4
                    y1: win.height / 2 - (win.width + win.height) / 4
                    x2: win.width / 2 + (win.width + win.height) / 4
                    y2: win.height / 2 + (win.width + win.height) / 4
                    GradientStop { position: 0; color: root.win_top }
                    GradientStop { position: 0.55; color: root.win_mid }
                    GradientStop { position: 1; color: root.win_end }
                }
                PathRectangle { x: 1.75; y: 1.75; width: win.width - 3.5; height: win.height - 3.5; radius: win.r }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3.5
            radius: win.r - 3
            color: "transparent"
            border.width: 2
            border.color: Qt.tint(root.shadow, Qt.alpha(Theme.fg_dim, 0.7))
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: win.pad
        }
    }

    // The white glove cursor, nudging left and back.
    component Glove: Item {
        id: glove
        width: 58
        height: 37
        property real nudge: 0

        SequentialAnimation on nudge {
            running: root.animate && glove.visible
            loops: Animation.Infinite
            PropertyAction { value: -5.6 }
            PauseAnimation { duration: 400 }
            PropertyAction { value: 0 }
            PauseAnimation { duration: 400 }
        }

        Shape {
            x: glove.nudge + 2
            y: 2.5
            width: 22
            height: 14
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { xScale: glove.width / 22; yScale: glove.height / 14 }
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: root.shadow
                PathSvg { path: "M0.5 2.5 L8.6 2.5 Q10 1.5 11.6 1.5 L20 1.5 A1.8 1.8 0 0 1 20 5.1 L12.6 5.1 A1.3 1.3 0 0 1 12.6 7.7 A1.3 1.3 0 0 1 12.3 10.3 A1.25 1.25 0 0 1 11.6 12.8 L0.5 12.8 Z" }
            }
        }

        Shape {
            x: glove.nudge
            width: 22
            height: 14
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { xScale: glove.width / 22; yScale: glove.height / 14 }
            ShapePath {
                strokeWidth: 0.7
                strokeColor: Qt.tint(root.shadow, Qt.alpha(Theme.fg_dim, 0.4))
                fillColor: root.white
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M3 2.5 L8.6 2.5 Q10 1.5 11.6 1.5 L20 1.5 A1.8 1.8 0 0 1 20 5.1 L12.6 5.1 A1.3 1.3 0 0 1 12.6 7.7 A1.3 1.3 0 0 1 12.3 10.3 A1.25 1.25 0 0 1 11.6 12.8 L4.6 12.8 Q3 12.8 3 11.2 Z" }
            }
            ShapePath {
                strokeWidth: 0.7
                strokeColor: Qt.tint(root.shadow, Qt.alpha(Theme.fg_dim, 0.4))
                fillColor: root.white
                PathSvg { path: "M0.5 3 L3 3 L3 12.3 L0.5 12.3 Z" }
            }
            ShapePath {
                strokeWidth: 0.6
                strokeColor: Qt.tint(root.shadow, Qt.alpha(Theme.fg_dim, 0.6))
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathSvg { path: "M12.6 7.7 L10 7.7 M12.3 10.3 L10 10.3 M8.6 2.5 Q7.4 4.2 9.4 5.1" }
            }
        }
    }

    // A user's picture from the ctx's face_urls, tried in order, else a spiky silhouette.
    component Portrait: Rectangle {
        id: pic
        property string user_name: ""
        readonly property var urls: root.face_urls(pic.user_name)
        property int attempt: 0
        onUrlsChanged: pic.attempt = 0
        radius: 4
        border.width: 2.4
        border.color: Qt.alpha(root.white, 0.6)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary_strong, 0.5)) }
            GradientStop { position: 1; color: root.shadow }
        }

        Shape {
            visible: face.status !== Image.Ready
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2.4
            width: 60
            height: 60
            scale: pic.width * 0.9 / 60
            transformOrigin: Item.Bottom
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.bright_yellow, 0.6))
                PathSvg { path: "M14 30 l4 -18 l6 8 l6 -14 l6 14 l6 -8 l4 18 z M18 34 a12 12 0 1 0 24 0 a12 12 0 1 0 -24 0" }
            }
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.theme_primary, 0.3))
                PathSvg { path: "M8 60 q2 -16 22 -16 q20 0 22 16 z" }
            }
        }

        Image {
            id: face
            anchors.fill: parent
            anchors.margins: pic.border.width
            source: pic.urls[pic.attempt] || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            onStatusChanged: if (face.status === Image.Error && pic.attempt < pic.urls.length) pic.attempt += 1
        }
    }

    // An HP-style gauge.
    component Gauge: Rectangle {
        id: g
        property real value: 1
        width: 128
        height: 7.2
        color: root.shadow
        border.width: 1.3
        border.color: Qt.alpha(Theme.fg_dim, 0.6)
        Rectangle {
            x: 1.3
            y: 1.3
            height: g.height - 2.6
            width: (g.width - 2.6) * Math.max(0, Math.min(1, g.value))
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.blue, 0.6)) }
                GradientStop { position: 1; color: Theme.bright_blue }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: root.shadow }
            GradientStop { position: 0.45; color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary_strong, 0.1)) }
            GradientStop { position: 1; color: root.shadow }
        }
    }

    // Everything the battle swirl spins away: the sword and the title menu.
    Item {
        id: scene_layer
        anchors.fill: parent
        transformOrigin: Item.Center

        Stage {
            cover: true
            visible: root.stream_on

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: 0.8 + 0.2 * Math.sin(root.stream_t * 0.8)
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 800
                        centerY: 427
                        focalX: 800
                        focalY: 427
                        centerRadius: 620
                        GradientStop { position: 0; color: Qt.alpha(Theme.ok, 0.16) }
                        GradientStop { position: 0.5; color: Qt.alpha(Theme.hint, 0.06) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    PathRectangle { width: 1600; height: 900 }
                }
            }
        }

        Canvas {
            id: stream_back
            visible: root.stream_on
            width: parent.width * root.stream_res
            height: parent.height * root.stream_res
            scale: 1 / root.stream_res
            transformOrigin: Item.TopLeft
            onPaint: root.paint_stream(stream_back.getContext("2d"), stream_back.width, stream_back.height, false)
        }

        Stage {
            cover: true

            Item {
                id: sword
                width: 240
                height: 1100
                x: 800 - 120
                y: 450 - 550 - 23
                scale: 1152 / 1100
                rotation: 54
                opacity: 0.9
                visible: root.screen !== "files"
                property real glint_y: -400

                NumberAnimation on glint_y {
                    running: root.animate && root.screen !== "unlock"
                    loops: Animation.Infinite
                    from: -1200
                    to: 1300
                    duration: 6000
                    easing.type: Easing.InOutSine
                }

                SequentialAnimation on rotation {
                    running: root.animate && root.screen === "saver"
                    loops: Animation.Infinite
                    NumberAnimation { from: 54; to: 56; duration: 12000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 56; to: 52; duration: 24000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 52; to: 54; duration: 12000; easing.type: Easing.InOutSine }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 44
                            x2: 196
                            GradientStop { position: 0; color: Theme.bg_mantle }
                            GradientStop { position: 0.55; color: Theme.bg_surface }
                            GradientStop { position: 1; color: Theme.bg_mantle }
                        }
                        PathSvg { path: "M44 282 H196 V960 L44 1092 Z" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.tint(Theme.bg_mantle, Qt.alpha(root.shadow, 0.55))
                        PathSvg { path: "M44 282 H68 V1071 L44 1092 Z" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_dim, 0.45))
                        PathSvg { path: "M182 282 H196 V960 L44 1092 L44 1076 L182 956 Z" }
                    }
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Qt.alpha(Theme.fg_dim, 0.55)
                        fillColor: "transparent"
                        PathSvg { path: "M68 300 V1060 M182 300 V950" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            y1: sword.glint_y
                            y2: sword.glint_y + 220
                            GradientStop { position: 0; color: Qt.alpha(root.white, 0) }
                            GradientStop { position: 0.5; color: Qt.alpha(root.white, root.animate ? 0.22 : 0) }
                            GradientStop { position: 1; color: Qt.alpha(root.white, 0) }
                        }
                        PathSvg { path: "M44 282 H196 V960 L44 1092 Z" }
                    }
                    ShapePath {
                        strokeWidth: 2
                        strokeColor: Qt.alpha(Theme.fg_dim, 0.5)
                        fillColor: root.shadow
                        PathSvg { path: "M110 336 a15 15 0 1 0 30 0 a15 15 0 1 0 -30 0 M110 388 a15 15 0 1 0 30 0 a15 15 0 1 0 -30 0" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.bright_yellow, 0.2))
                        PathSvg { path: "M110 34 h20 q4 0 4 4 v200 q0 4 -4 4 h-20 q-4 0 -4 -4 v-200 q0 -4 4 -4 z" }
                    }
                    ShapePath {
                        strokeWidth: 3
                        strokeColor: Qt.alpha(root.shadow, 0.7)
                        fillColor: "transparent"
                        PathSvg { path: "M106 44 L134 54 M106 60 L134 70 M106 76 L134 86 M106 92 L134 102 M106 108 L134 118 M106 124 L134 134 M106 140 L134 150 M106 156 L134 166 M106 172 L134 182 M106 188 L134 198 M106 204 L134 214 M106 220 L134 230" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.bg_surface, 0.8))
                        PathSvg { path: "M62 252 h116 q4 0 4 4 v22 q0 4 -4 4 h-116 q-4 0 -4 -4 v-22 q0 -4 4 -4 z M101 240 h38 q3 0 3 3 v8 q0 3 -3 3 h-38 q-3 0 -3 -3 v-8 q0 -3 3 -3 z M106 14 h28 q6 0 6 6 v10 q0 6 -6 6 h-28 q-6 0 -6 -6 v-10 q0 -6 6 -6 z M111 10 a9 9 0 1 0 18 0 a9 9 0 1 0 -18 0" }
                    }
                }
            }

            Shape {
                visible: root.screen === "title" || root.screen === "unlock"
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillGradient: RadialGradient {
                        centerX: 800
                        centerY: 594
                        focalX: 800
                        focalY: 594
                        centerRadius: 640
                        GradientStop { position: 0; color: Qt.alpha(root.shadow, 0.75) }
                        GradientStop { position: 0.8; color: Qt.alpha(root.shadow, 0) }
                    }
                    PathRectangle { width: 1600; height: 900 }
                }
            }
        }

        Canvas {
            id: stream_front
            visible: root.stream_on
            width: parent.width * root.stream_res
            height: parent.height * root.stream_res
            scale: 1 / root.stream_res
            transformOrigin: Item.TopLeft
            onPaint: root.paint_stream(stream_front.getContext("2d"), stream_front.width, stream_front.height, true)
        }

        Stage {
            visible: root.screen === "title" || root.screen === "unlock"

            Column {
                x: 800 - width / 2
                y: 560
                spacing: 0

                Repeater {
                    model: [{ t: "NEW GAME", k: "new" }, { t: "CONTINUE", k: "continue" }]
                    Item {
                        id: row
                        required property var modelData
                        readonly property bool picked: root.on_new === (row.modelData.k === "new")
                        width: 220
                        height: 54.4

                        Glove {
                            visible: row.picked
                            x: -76.8
                            y: 9.6
                        }

                        SText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.t
                            font.pixelSize: 34
                            font.letterSpacing: 4
                            color: row.modelData.k === "new" ? root.dim : root.white
                        }
                    }
                }
            }

            SText {
                x: 0
                width: 1600
                y: 900 - 41.6 - height
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 18
                font.letterSpacing: 3.2
                wght: 500
                color: root.dim
                textFormat: Text.StyledText
                text: {
                    const c = root.ctx;
                    if (!c) return "";
                    const parts = ["<b>" + c.time_text + "</b>", c.date_text];
                    if (c.has_battery) parts.push(c.battery_percent + "%" + (c.charging ? " charging" : ""));
                    if (c.has_weather) parts.push(c.weather_temp);
                    if (c.notifications > 0) parts.push(c.notifications + " mail");
                    if (root.login && c.host) parts.push(c.host);
                    return parts.join("  ·  ");
                }
            }
        }
    }

    // A greeter or lock note (power confirm, preview) over the title and file screens.
    Stage {
        visible: !!root.ctx && root.ctx.message !== "" && root.phase !== "wrong" && (root.screen === "title" || root.screen === "files")

        Win {
            x: 800 - width / 2
            y: 32
            width: Math.max(480, note.implicitWidth + 48)
            height: 64
            pad: 0
            SText {
                id: note
                anchors.centerIn: parent
                text: root.ctx ? root.ctx.message : ""
            }
        }
    }

    // Load: one save file per user, the rest EMPTY.
    Stage {
        visible: root.screen === "files"

        Win {
            x: 41.6
            y: 32
            width: 1080
            height: 64
            pad: 0
            SText {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: "Select a file."
            }
        }

        Win {
            x: 1140
            y: 32
            width: 418.4
            height: 64
            pad: 0
            SText {
                anchors.centerIn: parent
                text: "Slot " + (Math.floor(root.file_sel / 3) + 1)
            }
        }

        Repeater {
            model: 3
            Item {
                id: file
                required property int index
                readonly property int slot: root.page + file.index
                readonly property var who: root.users[file.slot] || null
                readonly property bool picked: file.slot === root.file_sel
                visible: file.slot < root.slot_count
                x: 128
                y: 120 + file.index * 244
                width: 1430.4
                height: 228

                Glove {
                    visible: file.picked
                    x: -86
                    y: 44
                }

                Win {
                    anchors.fill: parent
                    pad: 22

                    SText {
                        visible: !file.who
                        anchors.verticalCenter: parent.verticalCenter
                        x: 28
                        text: "EMPTY"
                        font.pixelSize: 30
                        font.letterSpacing: 3
                        color: root.dim
                    }

                    Item {
                        visible: !!file.who
                        anchors.fill: parent

                        Portrait {
                            user_name: file.who ? file.who.name : ""
                            x: 0
                            y: 0
                            width: 118
                            height: 132
                        }

                        Column {
                            x: 146
                            y: 4
                            spacing: 6
                            SText {
                                text: root.display_name(file.who)
                                font.pixelSize: 34
                                font.letterSpacing: 1.5
                            }
                            Row {
                                spacing: 14
                                Lbl { text: "Level"; font.pixelSize: 24 }
                                SText { text: "99"; font.pixelSize: 24 }
                            }
                            Row {
                                spacing: 14
                                Lbl { text: "HP"; font.pixelSize: 24 }
                                SText { text: "9999/9999"; font.pixelSize: 24 }
                            }
                        }

                        Column {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 4
                            spacing: 6
                            Row {
                                anchors.right: parent.right
                                spacing: 22
                                Lbl { text: "Time"; font.pixelSize: 26 }
                                SText { text: root.ctx ? root.ctx.time_text : ""; font.pixelSize: 26; width: 110; horizontalAlignment: Text.AlignRight }
                            }
                            Row {
                                anchors.right: parent.right
                                spacing: 22
                                Lbl { text: "Gil"; font.pixelSize: 26 }
                                SText { text: file.who ? String(1000 + file.slot * 337 + root.display_name(file.who).length * 71) : ""; font.pixelSize: 26; width: 110; horizontalAlignment: Text.AlignRight }
                            }
                        }

                        Rectangle {
                            x: 146
                            y: 146
                            width: parent.width - 146
                            height: 1.6
                            color: Qt.alpha(root.white, 0.25)
                        }

                        SText {
                            x: 146
                            y: 156
                            text: root.ctx ? root.ctx.host || "Midgar" : ""
                            font.pixelSize: 24
                        }
                    }
                }
            }
        }
    }

    // Name entry: the password as the character naming screen, with the save slot's stats.
    Stage {
        visible: root.screen === "pw"

        Win {
            x: 41.6
            y: 32
            width: 1516.8
            height: 64
            pad: 0
            SText {
                anchors.centerIn: parent
                text: {
                    const c = root.ctx;
                    if (!c) return "";
                    if (root.prompt !== "") return root.prompt;
                    if (root.phase === "wrong") return (c.message && c.message !== "Wrong password" ? c.message + ". " : "The password was wrong. ") + "Attempt " + c.fail_count + ". Try again.";
                    if (root.checking) return "Please wait...";
                    return "Enter the password for " + root.display_name(root.current) + "." + (c.caps_lock ? "  CAPS LOCK is on." : "");
                }
                font.pixelSize: 24
                color: root.phase === "wrong" ? Theme.bright_red : root.white
            }
        }

        Win {
            id: pw_win
            x: 41.6
            y: 134.4
            width: 704
            height: 330
            pad: 22

            Lbl {
                text: "Password"
            }

            Row {
                id: field
                x: 80
                y: 48
                spacing: 14.4

                Repeater {
                    model: 10
                    Item {
                        id: cell
                        required property int index
                        readonly property bool cur: cell.index === Math.min(root.typed, 10) && !root.checking
                        width: 30.4
                        height: 48

                        SText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 2
                            visible: cell.index < root.typed
                            text: "*"
                            font.pixelSize: 38
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 3.2
                            color: cell.cur ? Theme.yellow : Qt.alpha(root.white, 0.7)
                            opacity: cell.cur && root.animate && blink.on ? 0.25 : 1
                        }
                    }
                }
            }

            Glove {
                x: 4
                y: field.y + 8
            }

            Grid {
                x: 0
                y: 128
                width: parent.width
                columns: 13
                columnSpacing: 6.4
                rowSpacing: 2.4

                Repeater {
                    model: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".split("")
                    Item {
                        id: key
                        required property var modelData
                        required property int index
                        readonly property bool on: root.phase !== "wrong" && key.index === (root.typed * 17 + 17) % 52
                        width: (660 - 12 * 6.4) / 13
                        height: 32

                        Rectangle {
                            anchors.fill: parent
                            visible: key.on
                            color: "transparent"
                            border.width: 1.9
                            border.color: Qt.alpha(root.white, 0.6)
                        }

                        SText {
                            anchors.centerIn: parent
                            text: key.modelData
                            font.pixelSize: 19
                            color: key.on ? root.white : Qt.alpha(root.white, 0.5)
                        }
                    }
                }
            }

            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: pw_win; property: "x"; to: 41.6 - 12.8; duration: 110 }
                NumberAnimation { target: pw_win; property: "x"; to: 41.6 + 12.8; duration: 225 }
                NumberAnimation { target: pw_win; property: "x"; to: 41.6; duration: 110 }
            }
        }

        SText {
            id: miss
            visible: root.phase === "wrong"
            x: 393.6 - width / 2
            y: 600
            text: "Miss"
            font.pixelSize: 70
            wght: 900
            font.italic: true
            font.letterSpacing: 2.4
            style: Text.Outline
            styleColor: root.shadow

            SequentialAnimation {
                id: miss_pop
                PropertyAction { target: miss; property: "opacity"; value: 0 }
                PropertyAction { target: miss; property: "y"; value: 624 }
                ParallelAnimation {
                    NumberAnimation { target: miss; property: "y"; to: 584; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 3 }
                    NumberAnimation { target: miss; property: "opacity"; to: 1; duration: 200 }
                }
                NumberAnimation { target: miss; property: "y"; to: 600; duration: 210; easing.type: Easing.OutQuad }
            }
        }

        Win {
            x: 1600 - 41.6 - 704
            y: 900 - 41.6 - height
            width: 704
            height: 214
            pad: 22

            Portrait {
                user_name: root.current.name
                x: 0
                y: 0
                width: 102.4
                height: 115.2
            }

            Column {
                x: 123
                y: -2
                spacing: 0
                SText { text: root.display_name(root.current); font.pixelSize: 27; font.letterSpacing: 1.6 }
                Row {
                    spacing: 9.6
                    Lbl { text: "LV"; font.pixelSize: 20 }
                    SText { text: "99"; font.pixelSize: 20 }
                }
                Row {
                    spacing: 9.6
                    Lbl { text: "HP"; font.pixelSize: 20; anchors.verticalCenter: parent.verticalCenter }
                    SText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ctx && root.ctx.has_battery ? root.ctx.battery_percent + "/100" : "9999/9999"
                        font.pixelSize: 20
                    }
                    Gauge {
                        anchors.verticalCenter: parent.verticalCenter
                        value: root.ctx && root.ctx.has_battery ? root.ctx.battery_percent / 100 : 1
                    }
                }
                Row {
                    spacing: 9.6
                    Lbl { text: "MP"; font.pixelSize: 20 }
                    SText {
                        text: !root.ctx || !root.ctx.has_battery ? "999/999" : root.ctx.charging ? "Charging" : "On battery"
                        font.pixelSize: 20
                    }
                }
            }

            Column {
                anchors.right: parent.right
                y: -2
                Lbl { anchors.right: parent.right; text: "Time"; font.pixelSize: 20 }
                SText { anchors.right: parent.right; text: root.ctx ? root.ctx.time_text : ""; font.pixelSize: 42 }
                SText { anchors.right: parent.right; text: root.ctx ? root.ctx.date_text : ""; font.pixelSize: 20 }
            }

            Rectangle {
                x: 0
                y: 128
                width: parent.width
                height: 1.6
                color: Qt.alpha(root.white, 0.25)
            }

            Flow {
                x: 0
                y: 136
                width: parent.width
                spacing: 25.6

                Row {
                    spacing: 9.6
                    Lbl { text: "Location"; font.pixelSize: 18 }
                    SText { text: root.ctx ? root.ctx.host : ""; font.pixelSize: 18 }
                }
                Row {
                    visible: !!root.ctx && root.ctx.has_weather
                    spacing: 9.6
                    Lbl { text: "Sky"; font.pixelSize: 18 }
                    SText { text: root.ctx ? root.ctx.weather_temp + " " + root.ctx.weather_cond : ""; font.pixelSize: 18 }
                }
                Row {
                    visible: !!root.ctx && !root.login
                    spacing: 9.6
                    Lbl { text: "Mail"; font.pixelSize: 18 }
                    SText { text: root.ctx ? String(root.ctx.notifications) : ""; font.pixelSize: 18 }
                }
                Row {
                    visible: !!root.ctx && root.ctx.has_media
                    spacing: 9.6
                    Lbl { text: "Music"; font.pixelSize: 18 }
                    SText { text: root.ctx ? root.ctx.media_status + ": " + root.ctx.media_title : ""; font.pixelSize: 18; elide: Text.ElideRight; width: Math.min(implicitWidth, 420) }
                }
            }
        }
    }

    // Screensaver: the sword drifts and a play-time window walks the corners.
    Stage {
        visible: root.screen === "saver"

        Win {
            id: timebox
            property int spot: 0
            readonly property var spots: [[41.6, 900 - 41.6 - 132], [1600 - 41.6 - 416, 900 - 41.6 - 132], [1600 - 41.6 - 416, 41.6], [41.6, 41.6]]
            x: timebox.spots[timebox.spot][0]
            y: timebox.spots[timebox.spot][1]
            width: 416
            height: 132
            pad: 20

            Timer {
                interval: 120000
                repeat: true
                running: root.screen === "saver"
                onTriggered: timebox.spot = (timebox.spot + 1) % 4
            }

            Column {
                width: parent.width
                spacing: 0
                Item {
                    width: parent.width
                    height: 34
                    Lbl { anchors.verticalCenter: parent.verticalCenter; text: "Time"; font.pixelSize: 20 }
                    SText { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.ctx ? root.ctx.time_text : ""; font.pixelSize: 29 }
                }
                Item {
                    visible: !root.login
                    width: parent.width
                    height: 30
                    Lbl { anchors.verticalCenter: parent.verticalCenter; text: "Mail"; font.pixelSize: 20 }
                    SText { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.ctx ? String(root.ctx.notifications) : ""; font.pixelSize: 20 }
                }
                SText {
                    font.pixelSize: 16
                    color: Qt.tint(Theme.fg_dim, Qt.alpha(root.white, 0.75))
                    text: {
                        const c = root.ctx;
                        if (!c) return "";
                        const parts = [c.date_text];
                        if (c.has_battery) parts.push(c.battery_percent + "%" + (c.charging ? " charging" : ""));
                        if (c.has_weather) parts.push(c.weather_temp);
                        return parts.join("  ·  ");
                    }
                }
            }
        }
    }

    // Battle swirl: the title spins and zooms away under white wedges, then a white flash.
    Item {
        id: swirl
        visible: root.screen === "unlock"
        anchors.centerIn: parent
        width: Math.hypot(root.width, root.height) * 1.2
        height: width
        property real t: 0
        rotation: 540 * swirl.t
        scale: 0.3 + 1.3 * swirl.t
        opacity: Math.min(1, swirl.t / 0.3)

        Repeater {
            model: 12
            Shape {
                id: wedge
                required property int index
                anchors.fill: parent
                rotation: wedge.index * 30
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: Qt.alpha(root.white, 0.55)
                    startX: swirl.width / 2
                    startY: swirl.height / 2
                    PathLine { x: swirl.width / 2 + swirl.width / 2; y: swirl.height / 2 }
                    PathLine { x: swirl.width / 2 + swirl.width / 2 * Math.cos(Math.PI * 8 / 180); y: swirl.height / 2 + swirl.width / 2 * Math.sin(Math.PI * 8 / 180) }
                }
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: Qt.alpha(Theme.blue, 0.3)
                    startX: swirl.width / 2
                    startY: swirl.height / 2
                    PathLine { x: swirl.width / 2 + swirl.width / 2 * Math.cos(Math.PI * 8 / 180); y: swirl.height / 2 + swirl.width / 2 * Math.sin(Math.PI * 8 / 180) }
                    PathLine { x: swirl.width / 2 + swirl.width / 2 * Math.cos(Math.PI * 16 / 180); y: swirl.height / 2 + swirl.width / 2 * Math.sin(Math.PI * 16 / 180) }
                }
            }
        }
    }

    Rectangle {
        id: flash
        visible: root.screen === "unlock"
        anchors.fill: parent
        color: root.white
        opacity: 0
    }

    ParallelAnimation {
        id: warp
        NumberAnimation { target: swirl; property: "t"; from: 0; to: 1; duration: root.unlock_ms; easing.type: Easing.InCubic }
        NumberAnimation { target: scene_layer; property: "rotation"; from: 0; to: -60; duration: root.unlock_ms; easing.type: Easing.InCubic }
        NumberAnimation { target: scene_layer; property: "scale"; from: 1; to: 2.2; duration: root.unlock_ms; easing.type: Easing.InCubic }
        SequentialAnimation {
            PauseAnimation { duration: root.unlock_ms * 0.55 }
            NumberAnimation { target: flash; property: "opacity"; from: 0; to: 1; duration: root.unlock_ms * 0.3 }
        }
    }

    Timer {
        interval: 40
        repeat: true
        running: root.stream_on && root.animate
        property double start: 0
        onRunningChanged: if (running) start = Date.now() - root.stream_t * 1000
        onTriggered: root.stream_t = (Date.now() - start) / 1000
    }

    onStream_tChanged: {
        stream_back.requestPaint();
        stream_front.requestPaint();
    }
    onStream_onChanged: {
        if (!root.stream_on) return;
        stream_back.requestPaint();
        stream_front.requestPaint();
    }

    QtObject {
        id: blink
        property bool on: false
    }

    Timer {
        interval: 500
        repeat: true
        running: root.animate && root.screen === "pw"
        onTriggered: blink.on = !blink.on
        onRunningChanged: blink.on = false
    }
}
