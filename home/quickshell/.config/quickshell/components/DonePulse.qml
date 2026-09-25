// home/quickshell/.config/quickshell/components/DonePulse.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../theme"

// A one-shot celebration centred on this item's origin: the glyph pops with a ring and hearts float up; `nudge` is a quieter pass.
Item {
    id: root

    property string glyph: ""
    property color color: Theme.theme_primary
    property string font_family: Style.bar_font_family
    property int glyph_size: Theme.glyph_size
    // hearts, pixel (stepped, integer motion), lcd (pixel-styled, then the glyph blinks twice at the end), hev_pickup, levelup (inverted flash, then pixel sparkles) or fanfare.
    property string mode: Style.done_anim
    // How far the hearts climb; defaults to the window's top edge.
    property real rise: 12
    property bool nudge: false
    // The glyph's free slot from the module; the pop and ring stay inside it and the window's height.
    property var slot: null
    property real room: 16

    signal finished()

    readonly property real glyph_half: root.slot ? root.slot.glyph_half : root.glyph_size / 2
    readonly property real side: root.slot ? Math.min(root.slot.left, root.slot.right) : root.glyph_size / 2 + 5
    readonly property real peak: Math.max(1, Math.min(root.nudge ? 1.15 : 1.4, (root.side - 0.5) / root.glyph_half, (root.room - 0.5) / (root.glyph_size / 2)))
    readonly property real ring_max: Math.max(8, 2 * Math.min(root.side, root.room) - 2)
    readonly property real ring_min: Math.min(root.glyph_size * 0.9, root.ring_max * 0.7)

    // fanfare: the glyph hops, gold stars twinkle round it and the count flashes gold.
    readonly property bool fanfare: root.mode === "fanfare"
    readonly property bool pixel: root.mode === "pixel"
    readonly property bool lcd: root.mode === "lcd"
    // A health pickup: the glyph and count flash bright and a + rises into the pickup history.
    readonly property bool hev: root.mode === "hev_pickup"
    // The count redrawn over the module's badge in this color; transparent leaves the module's own showing.
    readonly property color count_color: root.hev ? (root.hev_flash ? Theme.fg_strong : root.color) : root.fanfare && root.elapsed >= 300 && root.elapsed < root.duration - 100 ? Theme.theme_secondary : "transparent"
    // Drawn beneath the glyph row, except by modes that redraw the count badge.
    readonly property bool under: !root.hev && !root.fanfare
    readonly property bool levelup: root.mode === "levelup"
    // lcd reuses the pixel stepping/snapping machinery, just on a coarser refresh.
    readonly property bool stepped: root.pixel || root.lcd || root.levelup
    readonly property int duration: root.hev ? (root.nudge ? 700 : 1000) : root.levelup ? (root.nudge ? 500 : 800) : (root.lcd ? 1300 : 1100) - (root.nudge ? 400 : 0)
    property real elapsed
    readonly property real t: root.pixel ? Math.floor(root.elapsed / 80) * 80 : root.lcd ? Math.floor(root.elapsed / 100) * 100 : root.elapsed
    // lcd's final blink phase fills the last 200ms, once the hearts are done.
    readonly property int blink_start: root.duration - 200
    readonly property int blink_step: root.lcd ? Math.floor(Math.max(0, root.elapsed - root.blink_start) / 50) : 0

    function phase(start, length) {
        return Math.max(0, Math.min(1, (root.t - start) / length));
    }

    function out_quad(p) {
        return root.stepped ? p : 1 - (1 - p) * (1 - p);
    }

    function out_back(p) {
        if (root.stepped) return p;
        const c = 2.2;
        return 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2);
    }

    function snap(v) {
        return root.stepped ? Math.round(v) : v;
    }

    readonly property real pop_scale: {
        if (root.levelup) return 1;
        const p = root.phase(0, 450);
        if (p <= 0 || p >= 1) return 1;
        if (p < 1 / 3) return 1 + (root.peak - 1) * root.out_quad(p * 3);
        return root.peak - (root.peak - 1) * root.out_back((p - 1 / 3) * 1.5);
    }

    Component.onCompleted: {
        let top = root;
        while (top.parent) top = top.parent;
        const y = root.mapToItem(top, 0, 0).y;
        root.rise = Math.max(8, y - 4);
        root.room = Math.max(8, Math.min(y, top.height - y) - 1);
    }

    NumberAnimation on elapsed {
        from: 0
        to: root.duration
        duration: root.duration
        onFinished: root.finished()
    }

    Rectangle {
        readonly property real p: root.phase(0, 600)
        visible: !root.hev && !root.levelup && !root.fanfare && p > 0 && p < 1
        width: root.stepped ? 2 * Math.round((root.ring_min + (root.ring_max - root.ring_min) * p) / 2) : root.ring_min + (root.ring_max - root.ring_min) * root.out_quad(p)
        height: width
        x: -width / 2
        y: -height / 2
        radius: root.stepped ? 0 : width / 2
        color: "transparent"
        border.width: root.stepped ? 2 : 1.5
        border.color: root.color
        opacity: (root.nudge ? 0.6 : 1) * (root.stepped ? Math.ceil((1 - p) * 3) / 5 : 0.6 * (1 - p))
    }

    Repeater {
        model: root.hev || root.levelup || root.fanfare ? [] : root.nudge ? [{ dx: 0, delay: 100 }] : [{ dx: -3, delay: 120 }, { dx: 3, delay: 260 }, { dx: 0, delay: 400 }]

        Item {
            id: heart
            required property var modelData
            readonly property real p: root.phase(heart.modelData.delay, 700)
            readonly property real fade: p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85

            visible: p > 0 && p < 1
            width: root.stepped ? 7 : heart_glyph.implicitWidth
            height: root.stepped ? 6 : heart_glyph.implicitHeight
            x: root.snap(-width / 2 + heart.modelData.dx * p + Math.sin(p * 2 * Math.PI))
            y: root.snap(-height / 2 - 4 - (root.rise - 4) * root.out_quad(p))
            scale: root.stepped ? 1 : 0.7 + 0.3 * p
            opacity: root.stepped ? Math.ceil(fade * 4) / 4 : fade

            Text {
                id: heart_glyph
                visible: !root.stepped
                text: String.fromCodePoint(0xF02D1)
                color: root.color
                font.family: root.font_family
                font.pixelSize: 9
            }

            Repeater {
                model: root.stepped ? [[1, 0, 2], [4, 0, 2], [0, 1, 7], [0, 2, 7], [1, 3, 5], [2, 4, 3], [3, 5, 1]] : []

                Rectangle {
                    required property var modelData
                    x: modelData[0]
                    y: modelData[1]
                    width: modelData[2]
                    height: 1
                    color: root.color
                }
            }
        }
    }

    readonly property bool hev_flash: root.hev && root.elapsed >= 80 && root.elapsed < root.duration - 300
    readonly property real hev_fade: root.hev && root.elapsed >= root.duration - 300 ? 0.75 + 0.25 * root.phase(root.duration - 150, 150) : 1

    // levelup: the glyph flashes inverted, then pixel plus-sparkles burst from its corners, the far ones skipped on a nudge.
    readonly property color light: Style.shade_3.a > 0 ? Style.shade_3 : Theme.fg_strong
    readonly property color dark: Style.shade_0.a > 0 ? Style.shade_0 : Theme.bg_crust
    readonly property bool inverted: root.levelup && root.elapsed >= 100 && root.elapsed < 250

    Rectangle {
        visible: root.inverted
        width: Math.round(Math.min(2 * root.side - 2, 2 * root.glyph_half + 4))
        height: Math.round(Math.min(2 * root.room - 2, root.glyph_size + 2))
        x: -Math.round(width / 2)
        y: -Math.round(height / 2)
        color: root.light
    }

    Repeater {
        model: root.levelup ? [[-1, -1], [1, -1], [-1, 1], [1, 1]] : []

        Item {
            id: sparkle
            required property var modelData
            readonly property bool far: root.elapsed >= 450
            readonly property int size: far ? 3 : 5
            readonly property real reach_x: Math.min(root.side - 1 - size / 2, root.glyph_half + (far ? 5 : 1))
            readonly property real reach_y: Math.min(root.room - 1 - size / 2, root.glyph_half + (far ? 5 : 1))
            visible: root.elapsed >= 250 && (!far || !root.nudge)
            width: size
            height: size
            x: Math.round(modelData[0] * reach_x - size / 2)
            y: Math.round(modelData[1] * reach_y - size / 2)

            Rectangle {
                x: Math.floor(sparkle.size / 2)
                width: 1
                height: sparkle.size
                color: sparkle.far ? Style.shade_2.a > 0 ? Style.shade_2 : root.color : root.light
            }

            Rectangle {
                y: Math.floor(sparkle.size / 2)
                width: sparkle.size
                height: 1
                color: sparkle.far ? Style.shade_2.a > 0 ? Style.shade_2 : root.color : root.light
            }
        }
    }

    Repeater {
        // Kept off the top right, where the count badge sits.
        model: !root.fanfare ? [] : root.nudge ? [{ x: -0.4, y: -1, size: 8, delay: 80 }, { x: 0.8, y: 1, size: 6, delay: 260 }]
            : [{ x: -0.4, y: -1, size: 9, delay: 120 }, { x: -1, y: 0.3, size: 6, delay: 300 }, { x: 0.8, y: 1, size: 6, delay: 600 }]

        Shape {
            id: star
            required property var modelData
            readonly property real s: star.modelData.size
            readonly property real p: root.phase(star.modelData.delay, 120)
            readonly property real cx: Math.max(-(root.slot ? root.slot.left : root.side) + star.s / 2 + 0.5, Math.min((root.slot ? root.slot.right : root.side) - star.s / 2 - 0.5, star.modelData.x * (root.glyph_half + 1)))
            readonly property real cy: Math.max(-root.room + star.s / 2, Math.min(root.room - star.s / 2, star.modelData.y * (root.glyph_size / 2 + 1)))
            visible: p > 0
            x: cx - star.s / 2
            y: cy - star.s / 2
            width: star.s
            height: star.s
            opacity: p * (root.elapsed > 600 + star.modelData.delay ? 0.45 : 1) * (1 - root.phase(root.duration - 150, 150))
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.alpha(Theme.theme_secondary, 0.4)
                fillColor: Theme.theme_secondary
                PathPolyline {
                    path: {
                        const s = star.s;
                        return [Qt.point(s * 0.5, 0), Qt.point(s * 0.62, s * 0.38), Qt.point(s, s * 0.5), Qt.point(s * 0.62, s * 0.62), Qt.point(s * 0.5, s), Qt.point(s * 0.38, s * 0.62), Qt.point(0, s * 0.5), Qt.point(s * 0.38, s * 0.38), Qt.point(s * 0.5, 0)];
                    }
                }
            }
        }
    }

    Text {
        x: -width / 2
        y: -height / 2 - (root.fanfare ? (root.nudge ? 2 : 3) * Math.sin(Math.PI * root.phase(80, 360)) : 0)
        text: root.glyph
        color: root.hev_flash ? Theme.fg_strong : root.inverted ? root.dark : root.color
        opacity: root.hev_fade
        font.family: root.font_family
        font.pixelSize: root.glyph_size
        style: root.hev_flash ? Text.Outline : Style.bar_text_style
        styleColor: root.hev_flash ? Qt.alpha(Theme.ok, 0.7) : Style.bar_glow_color
        scale: root.hev || root.fanfare ? 1 : root.pop_scale
        visible: !root.lcd || root.elapsed < root.blink_start || root.blink_step % 2 === 1
    }

    Text {
        visible: root.count_color.a > 0 && !!root.slot && root.slot.badge
        x: root.slot ? root.slot.badge_x : 0
        y: root.slot ? root.slot.badge_y : 0
        text: root.slot ? root.slot.count : ""
        color: root.count_color
        opacity: root.hev_fade
        font.family: root.font_family
        font.pixelSize: Style.bar_font_size - 3
        font.bold: true
        style: root.hev_flash ? Text.Outline : Style.bar_text_style
        styleColor: root.hev_flash ? Qt.alpha(Theme.ok, 0.7) : Style.bar_glow_color
    }

    // The pickup +, kept inside the glyph's slot and the bar's height.
    Item {
        readonly property real p: root.phase(250, 450)
        readonly property real size: 7
        readonly property real start_y: -root.glyph_size / 2 + 1
        readonly property real end_y: Math.max(-root.room + 0.5, start_y - 6)
        visible: root.hev && root.elapsed >= 250
        width: size
        height: size
        x: Math.round(Math.min(root.slot ? root.slot.right - 1 : root.glyph_half + 5, (root.slot ? root.slot.content_right : root.glyph_half) + 1 + size / 2) - size)
        y: Math.round(start_y + (end_y - start_y) * root.out_quad(p))
        opacity: (root.nudge ? 0.7 : 1) * (p < 1 ? 1 : 0.45 * (1 - root.phase(700, Math.max(1, root.duration - 700))))

        Rectangle {
            x: 2.5
            width: 2
            height: parent.height
            color: Theme.ok
        }

        Rectangle {
            y: 2.5
            width: parent.width
            height: 2
            color: Theme.ok
        }
    }
}
