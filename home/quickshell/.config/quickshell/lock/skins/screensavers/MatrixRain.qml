// home/quickshell/.config/quickshell/lock/skins/screensavers/MatrixRain.qml
import QtQuick

// Falling glyph columns: a bright head over a fading trail, each column at its own speed.
Item {
    id: root

    property bool running: true
    property color color: "#ccffcc"
    property color trail_color: "#33cc55"
    property color background: "transparent"
    property string font_family: "monospace"
    property real glyph_size: 18
    property string characters: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:=*+-<>"
    // Share of columns falling at once, 0..1.
    property real density: 0.6
    // Average fall speed in rows per second.
    property real speed: 14
    property real trail_length: 20
    // Chance per step that a glyph just behind a head flips.
    property real change_chance: 0.04
    property int fps: 30
    property real render_scale: 1

    property var drops: []
    property double last_ms: 0
    property bool fresh: true

    function glyph() {
        const c = root.characters;
        return c.length > 0 ? c.charAt(Math.floor(Math.random() * c.length)) : "";
    }

    function respawn(d, rows, initial) {
        const gap = rows / Math.max(0.05, root.density);
        d.y = initial ? rows * 0.8 - Math.random() * gap : -Math.random() * gap;
        d.row = Math.floor(d.y);
        d.speed = root.speed * (0.5 + Math.random());
    }

    function reseed() {
        const cell = root.glyph_size * root.render_scale;
        const cols = cell > 0 ? Math.ceil(canvas.width / cell) : 0;
        const rows = cell > 0 ? Math.ceil(canvas.height / cell) : 0;
        const list = [];
        for (let i = 0; i < cols; i++) {
            const d = {};
            root.respawn(d, rows, true);
            list.push(d);
        }
        root.drops = list;
        root.fresh = true;
        canvas.requestPaint();
    }

    Component.onCompleted: root.reseed()
    onGlyph_sizeChanged: root.reseed()
    onDensityChanged: root.reseed()
    onRender_scaleChanged: root.reseed()
    onFont_familyChanged: root.fresh = true
    onRunningChanged: {
        root.last_ms = 0;
        root.fresh = true;
        canvas.requestPaint();
    }

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

        onWidthChanged: root.reseed()
        onHeightChanged: root.reseed()
        onAvailableChanged: requestPaint()

        function cell_text(ctx, col, row, cell, fill) {
            ctx.clearRect(col * cell, row * cell, cell, cell);
            ctx.fillStyle = fill;
            ctx.fillText(root.glyph(), col * cell + cell / 2, row * cell);
        }

        // Paused: one full frame with every trail drawn at its faded strength.
        function draw_still(ctx, cell, rows) {
            for (let c = 0; c < root.drops.length; c++) {
                const d = root.drops[c];
                for (let k = 0; k < root.trail_length; k++) {
                    const r = d.row - k;
                    if (r < 0 || r >= rows) continue;
                    ctx.globalAlpha = 1 - k / root.trail_length;
                    ctx.fillStyle = k === 0 ? root.color : root.trail_color;
                    ctx.fillText(root.glyph(), c * cell + cell / 2, r * cell);
                }
            }
            ctx.globalAlpha = 1;
        }

        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            const cell = root.glyph_size * root.render_scale;
            if (w <= 0 || h <= 0 || cell <= 0) return;
            const rows = Math.ceil(h / cell);

            ctx.font = Math.round(cell) + "px \"" + root.font_family + "\"";
            ctx.textAlign = "center";
            ctx.textBaseline = "top";
            ctx.globalCompositeOperation = "source-over";

            if (root.fresh) {
                ctx.clearRect(0, 0, w, h);
                root.fresh = false;
                if (!root.running) {
                    canvas.draw_still(ctx, cell, rows);
                    return;
                }
            }
            if (!root.running) return;

            const now = Date.now();
            const dt = root.last_ms > 0 ? Math.min(0.1, (now - root.last_ms) / 1000) : 0;
            root.last_ms = now;
            if (dt <= 0) return;

            // Fades everything so a glyph drops to ~4% by the time a mean-speed head is trail_length rows past it.
            ctx.globalCompositeOperation = "destination-out";
            ctx.fillStyle = Qt.rgba(0, 0, 0, 1 - Math.pow(0.04, dt * root.speed / Math.max(1, root.trail_length)));
            ctx.fillRect(0, 0, w, h);
            ctx.globalCompositeOperation = "source-over";

            for (let c = 0; c < root.drops.length; c++) {
                const d = root.drops[c];
                d.y += d.speed * dt;
                const head = Math.floor(d.y);
                if (head !== d.row) {
                    for (let r = Math.max(0, d.row); r < head && r < rows; r++)
                        canvas.cell_text(ctx, c, r, cell, root.trail_color);
                    if (head >= 0 && head < rows) canvas.cell_text(ctx, c, head, cell, root.color);
                    ctx.clearRect(c * cell, (d.row - root.trail_length * 1.5) * cell, cell, (head - d.row) * cell);
                    d.row = head;
                }
                if (head > 0 && head < rows + 1 && Math.random() < root.change_chance) {
                    const r = head - 1 - Math.floor(Math.random() * root.trail_length * 0.3);
                    if (r >= 0 && r < rows) canvas.cell_text(ctx, c, r, cell, root.trail_color);
                }
                if (head - root.trail_length * 1.5 > rows) root.respawn(d, rows, false);
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
