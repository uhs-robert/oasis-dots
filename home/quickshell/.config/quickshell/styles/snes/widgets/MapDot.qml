import QtQuick
import qs.theme

// A Super Mario World level dot: yellow oval with a darker underside, hollow when empty, larger with a soft glow when selected, dimmed and underlined when shown on another monitor.
Canvas {
    id: root

    property bool selected: false
    property bool empty: false
    property bool shown: false
    readonly property bool dimmed: root.shown && !root.selected
    readonly property color face: root.dimmed ? Qt.tint(Theme.theme_secondary, Qt.alpha(Theme.bg_core, 0.45)) : Theme.theme_secondary
    readonly property color underside: root.dimmed ? Qt.tint(Theme.theme_secondary_strong, Qt.alpha(Theme.bg_core, 0.45)) : Theme.theme_secondary_strong
    readonly property color glow: Qt.alpha(Theme.theme_secondary, 0.22)
    readonly property color shadow: Theme.bg_shadow
    readonly property color highlight: Theme.fg_strong
    readonly property color underline: Theme.theme_primary_light
    readonly property color core: Theme.bg_core
    readonly property color hollow_ring: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_secondary_strong, 0.7))

    width: 22
    height: 14

    onSelectedChanged: root.requestPaint()
    onEmptyChanged: root.requestPaint()
    onShownChanged: root.requestPaint()
    onFaceChanged: root.requestPaint()
    onUndersideChanged: root.requestPaint()
    onGlowChanged: root.requestPaint()
    onHollow_ringChanged: root.requestPaint()
    onShadowChanged: root.requestPaint()
    onHighlightChanged: root.requestPaint()
    onUnderlineChanged: root.requestPaint()
    onCoreChanged: root.requestPaint()

    function oval(ctx, x, y, w, h, color) {
        ctx.beginPath();
        ctx.ellipse(x, y, w, h);
        ctx.fillStyle = String(color);
        ctx.fill();
    }

    // The filled dot, w x h and centred, with its face lit above a darker underside; returns its top-left.
    function dot(ctx, w, h) {
        const x = (root.width - w) / 2, y = (root.height - h) / 2;
        root.oval(ctx, x - 1, y - 1, w + 2, h + 2, root.shadow);
        root.oval(ctx, x, y, w, h, root.underside);
        ctx.save();
        ctx.beginPath();
        ctx.ellipse(x, y, w, h);
        ctx.clip();
        root.oval(ctx, x, y - 2, w, h, root.face);
        ctx.restore();
        return { x: x, y: y };
    }

    onPaint: {
        const ctx = root.getContext("2d");
        ctx.reset();
        if (root.empty) {
            root.oval(ctx, 4, 2, 14, 10, root.shadow);
            root.oval(ctx, 5, 3, 12, 8, root.hollow_ring);
            root.oval(ctx, 7, 5, 8, 4, root.core);
            return;
        }
        if (root.selected) {
            root.oval(ctx, 0, 0, root.width, root.height, root.glow);
            const at = root.dot(ctx, 18, 11);
            ctx.fillStyle = String(root.highlight);
            ctx.fillRect(at.x + 5, at.y + 2, 6, 1);
            return;
        }
        root.dot(ctx, 14, 9);
        if (root.shown) {
            ctx.fillStyle = String(root.underline);
            ctx.fillRect(4, root.height - 1, root.width - 8, 1);
        }
    }
}
