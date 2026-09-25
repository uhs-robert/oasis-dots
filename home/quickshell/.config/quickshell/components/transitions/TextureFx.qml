import QtQuick
import QtQuick.Effects
import "../../theme"

// Redraws the bar through one effect while it plays: fade, blur, crt, flash, palette, mosaic or flicker.
Item {
    id: root

    required property Item target
    property string kind: "fade"
    property int duration: 450
    property real elapsed

    signal finished()

    readonly property real p: Math.min(1, root.elapsed / root.duration)

    function seg(a, b) {
        return Math.max(0, Math.min(1, (root.elapsed - a) / (b - a)));
    }

    function ease_out(x) {
        return 1 - (1 - x) * (1 - x);
    }

    function ease_in(x) {
        return x * x;
    }

    // Holds the value of the last key at or before elapsed.
    function hold(keys) {
        let v = keys[0][1];
        for (const k of keys) if (root.elapsed >= k[0]) v = k[1];
        return v;
    }

    readonly property real line: Math.min(1, 2 / Math.max(1, root.height))
    readonly property real dot: Math.min(1, 4 / Math.max(1, root.width))

    // [x scale, y scale, opacity, brightness, tint, blur] for this frame.
    readonly property var frame: {
        const t = root.elapsed;
        switch (root.kind) {
        case "blur": {
            const e = root.ease_out(root.p);
            return [1, 1, 0.3 + 0.7 * root.ease_out(Math.min(1, root.p * 1.5)), 0, 0, 1 - e];
        }
        case "crt": {
            if (t < 160) {
                const a = root.ease_in(root.seg(0, 160));
                return [1, 1 - (1 - root.line) * a, 1, 0.6 * a, 0.9 * a, 0];
            }
            if (t < 280) return [1 - (1 - root.dot) * root.ease_in(root.seg(160, 280)), root.line, 1, 0.6, 0.9, 0];
            if (t < 360) return [root.dot, root.line, 1 - 0.4 * root.seg(280, 360), 0.6, 0.9, 0];
            if (t < 500) return [root.dot + (1 - root.dot) * root.ease_out(root.seg(360, 500)), root.line, 1, 0.6, 0.9, 0.3];
            if (t < 660) return [1, root.line + (1 - root.line) * root.ease_out(root.seg(500, 660)), 1, 0.6, 0.9, 0.5];
            const f = 1 - root.seg(660, root.duration);
            return [1, 1, 1, 0.6 * f, 0.9 * f, 0.5 * f];
        }
        case "flash": {
            const f = 1 - root.ease_out(root.seg(150, root.duration));
            return [1, 1, root.seg(0, 60), 0.8 * f, f, 0];
        }
        case "palette": {
            const step = Math.min(3, Math.floor(t / (root.duration / 4)));
            return [1, 1, 1, [0.75, 0.5, 0.25, 0][step], [0.8, 0.55, 0.3, 0][step], 0];
        }
        case "flicker": {
            const f = 1 - root.seg(370, root.duration);
            return [1, 1, root.hold([[0, 0], [50, 0.85], [90, 0.1], [150, 1], [200, 0.25], [260, 0.9], [320, 0.5], [370, 1]]), 0.25 * f, 0.6 * f, 0];
        }
        default:
            return [1, 1, root.ease_out(root.p), 0, 0, 0];
        }
    }

    readonly property color tint_color: {
        if (root.kind === "palette") return Style.shade_3.a > 0 ? Style.shade_3 : Theme.fg_strong;
        if (root.kind === "flicker") return Style.accent_color.a > 0 ? Style.accent_color : Theme.theme_secondary;
        return Theme.fg_strong;
    }

    // SNES mosaic: the bar rendered into ever finer blocks.
    readonly property int mosaic: [24, 16, 10, 6, 3, 1][Math.min(5, Math.floor(root.p * 6))]

    NumberAnimation on elapsed {
        from: 0
        to: root.duration
        duration: root.duration
        onFinished: root.finished()
    }

    ShaderEffectSource {
        id: tex
        anchors.fill: parent
        sourceItem: root.target
        hideSource: true
        visible: root.kind === "mosaic"
        smooth: root.kind !== "mosaic"
        textureSize: root.kind === "mosaic" ? Qt.size(Math.max(1, Math.ceil(root.width / root.mosaic)), Math.max(1, Math.ceil(root.height / root.mosaic))) : Qt.size(0, 0)
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.kind !== "mosaic"
        source: tex
        opacity: root.frame[2]
        brightness: root.frame[3]
        colorization: root.frame[4]
        colorizationColor: root.tint_color
        blurEnabled: root.kind === "blur" || root.kind === "crt"
        blurMax: root.kind === "blur" ? 32 : 12
        blur: root.frame[5]
        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: root.frame[0]
            yScale: root.frame[1]
        }
    }

    Rectangle {
        visible: root.kind === "crt" && root.elapsed >= 120 && root.elapsed < 540
        anchors.centerIn: parent
        width: Math.max(6, root.width * root.frame[0])
        height: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, 0) }
            GradientStop { position: 0.5; color: Theme.fg_strong }
            GradientStop { position: 1; color: Qt.alpha(Theme.fg_strong, 0) }
        }
    }
}
