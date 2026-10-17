import QtQuick
import qs.theme
import qs.features.weather

// The moon at its phase over a small oasis pool that holds the same phase upside down, broken by ripples, with a palm on the bank.
Item {
    id: root

    property real phase: 0

    readonly property color sand: Theme.theme_secondary
    readonly property real moon_size: 44
    readonly property real pool_h: root.height - root.moon_size - 6
    readonly property color water: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.info, 0.4))

    Image {
        id: moon
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.moon_size
        height: root.moon_size
        source: WeatherState.moon_icon_source(root.phase)
        sourceSize.width: 128
        sourceSize.height: 128
        smooth: true
    }

    Connections {
        target: Theme
        function onInfoChanged() { pool.requestPaint(); ripples.requestPaint(); }
        function onTheme_primary_strongChanged() { pool.requestPaint(); }
    }

    Canvas {
        id: pool
        x: 0
        y: root.height - root.pool_h
        width: root.width
        height: root.pool_h

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            ctx.beginPath();
            ctx.ellipse(1, 1, w - 2, h - 2);
            const fill = ctx.createLinearGradient(0, 0, 0, h);
            fill.addColorStop(0, Qt.alpha(Theme.info, 0.34));
            fill.addColorStop(1, Qt.alpha(Theme.theme_primary_strong, 0.16));
            ctx.fillStyle = fill;
            ctx.fill();
            ctx.strokeStyle = Qt.alpha(root.sand, 0.4);
            ctx.lineWidth = 1;
            ctx.stroke();
        }

        onHeightChanged: requestPaint()
        onWidthChanged: requestPaint()
    }

    Item {
        id: reflection_window
        x: pool.x + pool.width * 0.2
        y: pool.y + 3
        width: pool.width * 0.6
        height: pool.height - 6
        clip: true

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2
            width: root.moon_size * 0.8
            height: width
            source: moon.source
            sourceSize.width: 96
            sourceSize.height: 96
            smooth: true
            opacity: 0.45
            // Rotated half a turn and mirrored, which is a flip top to bottom.
            rotation: 180
            mirror: true
        }
    }

    Canvas {
        id: ripples
        x: pool.x
        y: pool.y
        width: pool.width
        height: pool.height

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            ctx.lineCap = "round";
            ctx.lineWidth = 1;
            for (let k = 0; k < 3; k++) {
                const y = h * (0.28 + k * 0.24);
                const half = w * (0.2 - k * 0.04);
                ctx.strokeStyle = Qt.alpha(Theme.info, 0.55 - k * 0.1);
                ctx.beginPath();
                for (let x = -half; x <= half; x += 2) {
                    const yy = y + 1.1 * Math.sin(x / 4 + k);
                    if (x === -half) ctx.moveTo(w / 2 + x, yy); else ctx.lineTo(w / 2 + x, yy);
                }
                ctx.stroke();
            }
        }

        onHeightChanged: requestPaint()
        onWidthChanged: requestPaint()
    }

    OasisPalm {
        x: root.width - width - 4
        y: pool.y + 4 - height + 8
        color: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary_light, 0.55))
        stroke: 1.4
        scale: 0.8
        transformOrigin: Item.Bottom
    }
}
