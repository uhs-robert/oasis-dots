// home/quickshell/.config/quickshell/popups/weather/Mode7Floor.qml
import QtQuick
import "../../theme"

// A Mode 7 checker floor receding to a horizon at the top edge; `run()` scrolls it forward once.
Canvas {
    id: root

    property color tile: Theme.theme_primary
    property color horizon: Theme.theme_secondary
    property real phase: 0

    // Camera depth of the bottom edge, in tiles; the bottom edge spans six tiles.
    readonly property real near_z: 4
    readonly property real far_z: 26
    readonly property real half_tiles: 3

    function run() {
        scroll.restart();
    }

    function stop() {
        scroll.stop();
    }

    NumberAnimation {
        id: scroll
        target: root
        property: "phase"
        from: 0
        to: 4
        duration: 700
        easing.type: Easing.OutCubic
    }

    onPhaseChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onTileChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        if (w <= 0 || h <= 0) return;
        const cx = w / 2;
        const unit = cx / root.half_tiles;
        const y_at = z => h * root.near_z / z;
        const x_at = (x, z) => cx + x * unit * root.near_z / z;
        const whole = Math.floor(root.phase);
        const frac = root.phase - whole;
        const span = Math.ceil(root.half_tiles * root.far_z / root.near_z);

        ctx.fillStyle = root.tile;
        for (let k = 0; root.near_z + k - frac < root.far_z; k++) {
            const z_far = root.near_z + k + 1 - frac;
            const z_near = Math.max(root.near_z, z_far - 1);
            ctx.globalAlpha = 0.34 * Math.max(0, 1 - (z_near - root.near_z) / (root.far_z - root.near_z));
            const y0 = y_at(z_near), y1 = y_at(z_far);
            for (let j = -span; j < span; j++) {
                if ((j + k + whole) % 2 !== 0) continue;
                ctx.beginPath();
                ctx.moveTo(x_at(j, z_near), y0);
                ctx.lineTo(x_at(j + 1, z_near), y0);
                ctx.lineTo(x_at(j + 1, z_far), y1);
                ctx.lineTo(x_at(j, z_far), y1);
                ctx.closePath();
                ctx.fill();
            }
        }

        ctx.globalAlpha = 1;
        ctx.fillStyle = root.horizon;
        ctx.fillRect(0, 0, w, 1);
    }
}
