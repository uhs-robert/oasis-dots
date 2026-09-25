// home/quickshell/.config/quickshell/components/snes/MapDot.qml
import QtQuick
import "../../theme"

// A Super Mario World level dot: yellow oval with a darker underside, hollow when empty, ringed white when selected.
Canvas {
    id: root

    property bool selected: false
    property bool empty: false
    readonly property color face: Theme.theme_secondary
    readonly property color underside: Theme.theme_secondary_strong
    readonly property color shadow: Theme.bg_shadow
    readonly property color ring: Theme.fg_strong
    readonly property color core: Theme.bg_core
    readonly property color hollow_ring: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_secondary_strong, 0.7))

    width: 16
    height: 12

    onSelectedChanged: root.requestPaint()
    onEmptyChanged: root.requestPaint()
    onFaceChanged: root.requestPaint()
    onUndersideChanged: root.requestPaint()
    onHollow_ringChanged: root.requestPaint()
    onShadowChanged: root.requestPaint()
    onRingChanged: root.requestPaint()
    onCoreChanged: root.requestPaint()

    function oval(ctx, x, y, w, h, color) {
        ctx.beginPath();
        ctx.ellipse(x, y, w, h);
        ctx.fillStyle = String(color);
        ctx.fill();
    }

    onPaint: {
        const ctx = root.getContext("2d");
        ctx.reset();
        if (root.selected) {
            root.oval(ctx, 0, 0, 16, 12, root.shadow);
            root.oval(ctx, 1, 1, 14, 10, root.ring);
        } else {
            root.oval(ctx, 1, 1, 14, 10, root.shadow);
        }
        if (root.empty) {
            root.oval(ctx, 2, 2, 12, 8, root.hollow_ring);
            root.oval(ctx, 4, 4, 8, 4, root.core);
            return;
        }
        root.oval(ctx, 2, 2, 12, 8, root.underside);
        ctx.save();
        ctx.beginPath();
        ctx.ellipse(2, 2, 12, 8);
        ctx.clip();
        root.oval(ctx, 2, 0, 12, 8, root.face);
        ctx.restore();
    }
}
