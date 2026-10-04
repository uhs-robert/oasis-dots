// home/quickshell/.config/quickshell/lock/skins/Ff7.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell.Io
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
    // The Prelude plays only on the login screen, on its title and screensaver.
    readonly property string music_track: root.owns_sound && root.login && root.ctx.music !== false && (root.screen === "title" || root.screen === "saver") ? "title" : ""
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

    // Lifestream: ribbons of braided strands flowing across the screen behind the sword.
    readonly property bool stream_on: root.screen === "saver"
    property real stream_t: 0

    // PS1-style 4x4 ordered dither: whole screen pixels, drawn in design units under a stage's scale of `k`.
    readonly property int dither_px: Math.max(1, Math.round(root.height / 540))
    readonly property real ui_k: Math.max(0.01, Math.min(root.width / 1600, root.height / 900))
    readonly property bool tall: root.height > root.width
    readonly property var title_frame: [480, 660, 560, 0.5]
    function dither_tile(cell) {
        const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
        let rects = "";
        for (let i = 0; i < 16; i++) rects += "<rect x='" + (i % 4) * cell + "' y='" + Math.floor(i / 4) * cell + "' width='" + cell + "' height='" + cell + "' fill-opacity='" + (bayer[i] / 16 * 0.32).toFixed(3) + "'/>";
        return "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='" + 4 * cell + "' height='" + 4 * cell + "'><g fill='" + Qt.rgba(root.shadow.r, root.shadow.g, root.shadow.b, 1) + "'>" + rects + "</g></svg>");
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
        const enter = !ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter);
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
        const go = enter || (!ctrl && event.key === Qt.Key_Space);
        if (up) {
            c.scene = root.on_new ? "" : "title:new";
            root.cue("cursor");
            return true;
        }
        if (go) {
            if (root.on_new) {
                root.cue("buzzer");
            } else {
                c.scene = "files:" + root.user_index;
                root.cue("loading");
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
        onLoaded: {
            audio_loader.item.track = Qt.binding(() => root.music_track);
            audio_loader.item.music_setting = Qt.binding(() => root.ctx.music_volume);
        }
    }

    onPhaseChanged: {
        if (root.phase === "saver" && root.can_step) root.ctx.scene = "";
        if (root.phase === "unlock") {
            if (!root.heard_unlock && root.owns_sound && audio_loader.item) audio_loader.item.play("loaded");
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
                if (pw_loader.item) pw_loader.item.play_miss();
            }
        }
    }

    // A design-space stage centred on its parent: `cover` fills it and crops, else it fits whole.
    // In portrait, `tall_frame` [x, width, y, at] spans design x..x+width across it with design y at `at` of its height.
    component Stage: Item {
        id: stage
        property bool cover: false
        property var tall_frame: null
        readonly property bool framed: root.tall && !!stage.tall_frame && !!stage.parent
        readonly property real kx: stage.parent ? stage.parent.width / 1600 : 1
        readonly property real ky: stage.parent ? stage.parent.height / 900 : 1
        readonly property real k: stage.framed ? stage.parent.width / stage.tall_frame[1] : stage.cover ? Math.max(stage.kx, stage.ky) : Math.min(stage.kx, stage.ky)
        readonly property real foot: stage.parent ? 450 + (stage.parent.height - stage.y - 450) / stage.k : 900
        width: 1600
        height: 900
        x: stage.framed ? -800 - (stage.tall_frame[0] - 800) * stage.k : stage.parent ? (stage.parent.width - 1600) / 2 : 0
        y: stage.framed ? stage.parent.height * stage.tall_frame[3] - 450 - (stage.tall_frame[2] - 450) * stage.k : stage.parent ? (stage.parent.height - 900) / 2 : 0
        scale: stage.k
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
        property real k: root.ui_k
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

        Repeater {
            readonly property real m: 3.5
            readonly property real c: win.r - 3
            model: [[m + c, m, win.width - 2 * (m + c), c], [m, m + c, win.width - 2 * m, win.height - 2 * (m + c)], [m + c, win.height - m - c, win.width - 2 * (m + c), c]]
            Item {
                id: band
                required property var modelData
                x: band.modelData[0]
                y: band.modelData[1]
                width: Math.max(0, band.modelData[2])
                height: Math.max(0, band.modelData[3])
                clip: true
                Image {
                    x: -band.x
                    y: -band.y
                    width: win.width
                    height: win.height
                    fillMode: Image.Tile
                    smooth: false
                    source: root.dither_tile(root.dither_px / win.k)
                }
            }
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
        property color lo: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.blue, 0.6))
        property color hi: Theme.bright_blue
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
                GradientStop { position: 0; color: g.lo }
                GradientStop { position: 1; color: g.hi }
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

        Loader {
            anchors.fill: parent
            active: root.stream_on
            sourceComponent: saver_back_view
        }

        Stage {
            cover: true
            tall_frame: root.title_frame

            // The warm pool of light the tip stands in.
            Item {
                visible: root.screen !== "files"
                x: 340
                y: 736
                width: 600
                height: 130

                Shape {
                    width: 600
                    height: 600
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale { yScale: 130 / 600 }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: RadialGradient {
                            centerX: 300
                            centerY: 300
                            focalX: 300
                            focalY: 300
                            centerRadius: 300
                            GradientStop { position: 0; color: Qt.alpha(Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.bright_yellow, 0.6)), 0.85) }
                            GradientStop { position: 0.6; color: Qt.alpha(Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.bright_yellow, 0.4)), 0.3) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        PathRectangle { width: 600; height: 600 }
                    }
                }
            }

            // The sword's shadow on the ground, cast straight down from above.
            Item {
                visible: root.screen !== "files"
                x: 596
                y: 756
                width: 440
                height: 46
                rotation: -3

                Shape {
                    width: 600
                    height: 600
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale { xScale: 440 / 600; yScale: 46 / 600 }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: RadialGradient {
                            centerX: 300
                            centerY: 300
                            focalX: 180
                            focalY: 300
                            centerRadius: 300
                            GradientStop { position: 0; color: Qt.alpha(root.shadow, 0.95) }
                            GradientStop { position: 0.7; color: Qt.alpha(root.shadow, 0.6) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        PathRectangle { width: 600; height: 600 }
                    }
                }
            }

            // The Buster Sword planted tip-down, as on the title screen, lit from the top right.
            Item {
                id: sword
                width: 240
                height: 1100
                x: 864 - 120
                y: 577 - 550
                scale: 637 / 1100
                rotation: 47
                visible: root.screen !== "files"
                property real glint_y: -400
                readonly property color steel_hi: Qt.tint(Theme.fg_dim, Qt.alpha(root.white, 0.7))
                readonly property color steel: Qt.tint(Theme.fg_dim, Qt.alpha(Theme.theme_primary_light, 0.35))
                readonly property color steel_lo: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.fg_dim, 0.45))

                NumberAnimation on glint_y {
                    running: root.animate && root.screen !== "unlock"
                    loops: Animation.Infinite
                    from: -1200
                    to: 1300
                    duration: 6000
                    easing.type: Easing.InOutSine
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: RadialGradient {
                            centerX: 150
                            centerY: 420
                            focalX: 150
                            focalY: 420
                            centerRadius: 380
                            GradientStop { position: 0; color: Qt.alpha(Qt.tint(Theme.info, Qt.alpha(root.white, 0.3)), 0.28) }
                            GradientStop { position: 0.5; color: Qt.alpha(Theme.info, 0.07) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        PathRectangle { x: -300; y: 0; width: 900; height: 900 }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 52
                            x2: 188
                            GradientStop { position: 0; color: sword.steel_hi }
                            GradientStop { position: 0.4; color: sword.steel }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M52 282 H188 V930 Q188 1040 64 1092 H52 Z" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            y1: 282
                            y2: 1092
                            GradientStop { position: 0; color: Qt.alpha(root.white, 0.14) }
                            GradientStop { position: 0.45; color: Qt.alpha(root.shadow, 0.05) }
                            GradientStop { position: 1; color: Qt.alpha(root.shadow, 0.45) }
                        }
                        PathSvg { path: "M52 282 H188 V930 Q188 1040 64 1092 H52 Z" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.tint(root.white, Qt.alpha(Theme.info, 0.35))
                        PathSvg { path: "M52 282 H61 V1092 H52 Z" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillColor: Qt.alpha(root.shadow, 0.35)
                        PathSvg { path: "M176 282 H188 V930 Q188 1040 64 1092 H52 Q174 1036 176 928 Z" }
                    }
                    ShapePath {
                        strokeWidth: 3
                        strokeColor: Qt.alpha(root.shadow, 0.22)
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: "M92 700 q12 30 4 60 M110 790 q-10 24 6 50 M88 880 l18 30 M126 860 q6 20 -4 40 M100 960 q10 18 2 36" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            y1: sword.glint_y
                            y2: sword.glint_y + 220
                            GradientStop { position: 0; color: Qt.alpha(root.white, 0) }
                            GradientStop { position: 0.5; color: Qt.alpha(root.white, root.animate ? 0.18 : 0) }
                            GradientStop { position: 1; color: Qt.alpha(root.white, 0) }
                        }
                        PathSvg { path: "M52 282 H188 V930 Q188 1040 64 1092 H52 Z" }
                    }
                    ShapePath {
                        strokeWidth: 2
                        strokeColor: Qt.alpha(sword.steel_lo, 0.8)
                        fillColor: root.shadow
                        PathSvg { path: "M109 334 a11 11 0 1 0 22 0 a11 11 0 1 0 -22 0 M109 378 a11 11 0 1 0 22 0 a11 11 0 1 0 -22 0" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 110
                            x2: 130
                            GradientStop { position: 0; color: Qt.tint(root.shadow, Qt.alpha(Theme.red, 0.5)) }
                            GradientStop { position: 0.4; color: Qt.tint(root.shadow, Qt.alpha(Theme.red, 0.72)) }
                            GradientStop { position: 1; color: Qt.tint(root.shadow, Qt.alpha(Theme.red, 0.35)) }
                        }
                        PathSvg { path: "M110 40 h20 v214 h-20 z" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            y1: 250
                            y2: 286
                            GradientStop { position: 0; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M42 250 h156 q4 0 4 4 v28 q0 4 -4 4 h-156 q-4 0 -4 -4 v-28 q0 -4 4 -4 z" }
                    }
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Qt.alpha(root.shadow, 0.65)
                        fillGradient: RadialGradient {
                            centerX: 59
                            centerY: 264
                            focalX: 59
                            focalY: 264
                            centerRadius: 10
                            GradientStop { position: 0; color: root.white }
                            GradientStop { position: 0.5; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M48 268 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0" }
                    }
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Qt.alpha(root.shadow, 0.65)
                        fillGradient: RadialGradient {
                            centerX: 91
                            centerY: 264
                            focalX: 91
                            focalY: 264
                            centerRadius: 10
                            GradientStop { position: 0; color: root.white }
                            GradientStop { position: 0.5; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M80 268 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0" }
                    }
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Qt.alpha(root.shadow, 0.65)
                        fillGradient: RadialGradient {
                            centerX: 123
                            centerY: 264
                            focalX: 123
                            focalY: 264
                            centerRadius: 10
                            GradientStop { position: 0; color: root.white }
                            GradientStop { position: 0.5; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M112 268 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0" }
                    }
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Qt.alpha(root.shadow, 0.65)
                        fillGradient: RadialGradient {
                            centerX: 155
                            centerY: 264
                            focalX: 155
                            focalY: 264
                            centerRadius: 10
                            GradientStop { position: 0; color: root.white }
                            GradientStop { position: 0.5; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M144 268 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0" }
                    }
                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: Qt.alpha(root.shadow, 0.65)
                        fillGradient: RadialGradient {
                            centerX: 187
                            centerY: 264
                            focalX: 187
                            focalY: 264
                            centerRadius: 10
                            GradientStop { position: 0; color: root.white }
                            GradientStop { position: 0.5; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M176 268 a8 8 0 1 0 16 0 a8 8 0 1 0 -16 0" }
                    }
                    ShapePath {
                        strokeWidth: 0
                        strokeColor: "transparent"
                        fillGradient: RadialGradient {
                            centerX: 124
                            centerY: 16
                            focalX: 124
                            focalY: 16
                            centerRadius: 20
                            GradientStop { position: 0; color: root.white }
                            GradientStop { position: 0.45; color: sword.steel_hi }
                            GradientStop { position: 1; color: sword.steel_lo }
                        }
                        PathSvg { path: "M104 28 a16 16 0 1 0 32 0 a16 16 0 1 0 -32 0" }
                    }
                }
            }
        }

        Image {
            anchors.fill: parent
            fillMode: Image.Tile
            smooth: false
            source: root.dither_tile(root.dither_px)
        }

        Loader {
            id: title_loader
            anchors.fill: parent
            active: root.screen === "title" || root.screen === "unlock"
            sourceComponent: title_view
        }
    }

    Component {
        id: saver_back_view

        Item {
            Stage {
                cover: true

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

            ShaderEffect {
                anchors.fill: parent
                property real t: root.stream_t
                property vector2d res: Qt.vector2d(width, height)
                property color green: Theme.ok
                property color teal: Theme.hint
                property color white: root.white
                fragmentShader: Qt.resolvedUrl("ff7/lifestream.frag.qsb")
            }
        }
    }

    Component {
        id: title_view

        Item {
            Stage {
                id: title_stage
                tall_frame: root.title_frame

                Column {
                    x: 716
                    y: 392
                    spacing: 0

                    Repeater {
                        model: [{ t: "NEW GAME", k: "new" }, { t: "Continue?", k: "continue" }]
                        Item {
                            id: row
                            required property var modelData
                            readonly property bool picked: root.on_new === (row.modelData.k === "new")
                            width: 220
                            height: 44

                            Glove {
                                visible: row.picked
                                x: -70
                                y: 5
                            }

                            SText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.t
                                font.pixelSize: 30
                                font.letterSpacing: 1.5
                            }
                        }
                    }
                }

                SText {
                    x: root.tall ? root.title_frame[0] + root.title_frame[1] / 2 - 800 : 0
                    width: 1600
                    y: (root.tall ? title_stage.foot : 900) - 41.6 - height
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
                        if (root.tall && parts.length > 2) return parts.slice(0, 2).join("  ·  ") + "<br>" + parts.slice(2).join("  ·  ");
                        return parts.join("  ·  ");
                    }
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
    Loader {
        id: files_loader
        anchors.fill: parent
        active: root.screen === "files"
        sourceComponent: files_view
    }

    Component {
        id: files_view

        Item {
            Stage {
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
        }
    }

    // Name entry: the password as the character naming screen, with the save slot's stats.
    Loader {
        id: pw_loader
        anchors.fill: parent
        active: root.screen === "pw"
        sourceComponent: pw_view
    }

    Component {
        id: pw_view

        Item {
            function play_miss() {
                shake.restart();
                miss_pop.restart();
            }

            Stage {
                id: pw_stage
                tall_frame: [0, 787.2, 0, 0.05]

                Win {
                    x: 41.6
                    y: 32
                    width: root.tall ? 704 : 1516.8
                    height: 64
                    k: pw_stage.k
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
                    k: pw_stage.k

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
                    readonly property real rest_y: root.tall ? 820 : 600
                    visible: root.phase === "wrong"
                    x: 393.6 - width / 2
                    y: miss.rest_y
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
                        PropertyAction { target: miss; property: "y"; value: miss.rest_y + 24 }
                        ParallelAnimation {
                            NumberAnimation { target: miss; property: "y"; to: miss.rest_y - 16; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 3 }
                            NumberAnimation { target: miss; property: "opacity"; to: 1; duration: 200 }
                        }
                        NumberAnimation { target: miss; property: "y"; to: miss.rest_y; duration: 210; easing.type: Easing.OutQuad }
                    }
                }

                Win {
                    x: root.tall ? 41.6 : 1600 - 41.6 - 704
                    y: root.tall ? 496.4 : 900 - 41.6 - height
                    width: 704
                    height: 214
                    pad: 22
                    k: pw_stage.k

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
                            Lbl { text: "LV"; font.pixelSize: 20; width: 34 }
                            SText { text: "99"; font.pixelSize: 20 }
                        }
                        Row {
                            spacing: 9.6
                            Lbl { text: "HP"; font.pixelSize: 20; width: 34; anchors.verticalCenter: parent.verticalCenter }
                            SText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 96
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
                            Lbl { text: "MP"; font.pixelSize: 20; width: 34; anchors.verticalCenter: parent.verticalCenter }
                            SText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 96
                                text: root.mem_total > 0 ? Math.round(root.mem_avail / 1048576) + "/" + Math.round(root.mem_total / 1048576) : "999/999"
                                font.pixelSize: 20
                            }
                            Gauge {
                                anchors.verticalCenter: parent.verticalCenter
                                value: root.mem_total > 0 ? root.mem_avail / root.mem_total : 1
                                lo: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.green, 0.6))
                                hi: Theme.bright_green
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
                    }
                }
            }
        }
    }

    // Screensaver: a play-time window walks the corners over the Lifestream.
    Loader {
        id: saver_loader
        anchors.fill: parent
        active: root.screen === "saver"
        sourceComponent: saver_view
    }

    Component {
        id: saver_view

        Item {
            Stage {
                Win {
                    id: timebox
                    readonly property var spots: [[41.6, 900 - 41.6 - 132], [1600 - 41.6 - 416, 900 - 41.6 - 132], [1600 - 41.6 - 416, 41.6], [41.6, 41.6]]
                    x: timebox.spots[root.saver_spot][0]
                    y: timebox.spots[root.saver_spot][1]
                    width: 416
                    height: 132
                    pad: 20

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
        }
    }

    // Battle swirl: the title spins and zooms away under white wedges, then a fade to black.
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
                    fillColor: Qt.alpha(root.white, 0.3)
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
        color: root.shadow
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

    FrameAnimation {
        id: stream_clock
        running: root.stream_on && root.animate
        onTriggered: root.stream_t += Math.min(stream_clock.frameTime, 0.1)
    }

    property int saver_spot: 0

    Timer {
        interval: 120000
        repeat: true
        running: root.screen === "saver"
        onTriggered: root.saver_spot = (root.saver_spot + 1) % 4
    }

    // MP: available memory in GiB, read while the name entry shows.
    property real mem_total: 0
    property real mem_avail: 0

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const kb = key => {
                const m = meminfo.text().match(new RegExp("^" + key + ":\\s+(\\d+)", "m"));
                return m ? parseInt(m[1]) : 0;
            };
            root.mem_total = kb("MemTotal");
            root.mem_avail = kb("MemAvailable");
        }
    }

    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.screen === "pw"
        onTriggered: meminfo.reload()
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
