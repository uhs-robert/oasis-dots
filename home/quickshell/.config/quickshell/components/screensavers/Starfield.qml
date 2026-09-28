// home/quickshell/.config/quickshell/components/screensavers/Starfield.qml
import QtQuick

// Stars fly out from a vanishing point, brightening as they near; drawn as warp streaks or dots.
Item {
    id: root

    property bool running: true
    property color color: "white"
    property color dim_color: "#555566"
    property color background: "transparent"
    property int count: 260
    // Depth units per second; a star lives about 1 / speed seconds.
    property real speed: 0.35
    property bool streak: true
    // Streak length as seconds of travel behind the star.
    property real streak_length: 0.12
    property real star_size: 2
    property real center_x: 0.5
    property real center_y: 0.5
    property int fps: 60
    // Canvas resolution relative to the item; below 1 trades sharpness for fill cost on big screens.
    property real render_scale: 1

    readonly property int levels: 5
    readonly property real near_z: 0.02
    property var stars: []
    property var shades: []
    property double last_ms: 0

    function spawn(s, z) {
        s.x = Math.random() * 2 - 1;
        s.y = Math.random() * 2 - 1;
        s.z = z;
    }

    function reseed() {
        const list = [];
        for (let i = 0; i < root.count; i++) {
            const s = {};
            root.spawn(s, root.near_z + Math.random() * (1 - root.near_z));
            list.push(s);
        }
        root.stars = list;
    }

    function reshade() {
        const list = [];
        const a = root.dim_color, b = root.color;
        for (let i = 0; i < root.levels; i++) {
            const t = i / (root.levels - 1);
            list.push(Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 0.35 + 0.65 * t));
        }
        root.shades = list;
    }

    Component.onCompleted: {
        root.reshade();
        root.reseed();
    }
    onCountChanged: root.reseed()
    onColorChanged: root.reshade()
    onDim_colorChanged: root.reshade()
    onRunningChanged: root.last_ms = 0

    Rectangle {
        anchors.fill: parent
        color: root.background
    }

    Canvas {
        id: canvas
        width: root.width * root.render_scale
        height: root.height * root.render_scale
        scale: 1 / root.render_scale
        transformOrigin: Item.TopLeft

        onAvailableChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            ctx.clearRect(0, 0, w, h);
            if (w <= 0 || h <= 0 || root.shades.length < root.levels) return;

            const now = Date.now();
            const dt = root.last_ms > 0 ? Math.min(0.1, (now - root.last_ms) / 1000) : 0;
            root.last_ms = now;

            const cx = w * root.center_x, cy = h * root.center_y;
            const f = Math.max(w, h) * 0.1;
            const dz = root.speed * dt;
            const tail = root.speed * root.streak_length;
            const size = root.star_size * root.render_scale;
            const paths = [];
            for (let i = 0; i < root.levels; i++) paths.push([]);

            for (const s of root.stars) {
                s.z -= dz;
                const sx = cx + s.x / s.z * f, sy = cy + s.y / s.z * f;
                if (s.z <= root.near_z || sx < -f || sx > w + f || sy < -f || sy > h + f) {
                    root.spawn(s, 1);
                    continue;
                }
                const t = 1 - s.z;
                const lvl = Math.min(root.levels - 1, Math.floor(t * t * root.levels));
                paths[lvl].push(sx, sy, s.x, s.y, s.z + tail);
            }

            for (let i = 0; i < root.levels; i++) {
                const p = paths[i];
                if (p.length === 0) continue;
                const px = size * (0.5 + i * 0.5);
                if (root.streak) {
                    ctx.strokeStyle = root.shades[i];
                    ctx.lineWidth = px;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    for (let j = 0; j < p.length; j += 5) {
                        const tz = Math.min(1, p[j + 4]);
                        ctx.moveTo(cx + p[j + 2] / tz * f, cy + p[j + 3] / tz * f);
                        ctx.lineTo(p[j], p[j + 1]);
                    }
                    ctx.stroke();
                } else {
                    ctx.fillStyle = root.shades[i];
                    for (let j = 0; j < p.length; j += 5)
                        ctx.fillRect(p[j] - px / 2, p[j + 1] - px / 2, px, px);
                }
            }
        }
    }

    Timer {
        interval: Math.max(1, Math.round(1000 / root.fps))
        repeat: true
        running: root.running && root.visible && root.width > 0 && root.height > 0
        onTriggered: canvas.requestPaint()
    }
}
