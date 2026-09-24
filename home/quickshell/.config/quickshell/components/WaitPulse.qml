// home/quickshell/.config/quickshell/components/WaitPulse.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../theme"

// A one-shot "waiting for you" cue centred on this item's origin; `nudge` plays a shorter, fainter pass.
Item {
    id: root

    property string glyph: ""
    property color color: Theme.theme_primary
    property string font_family: Style.bar_font_family
    property int glyph_size: Theme.glyph_size
    property string mode: Style.wait_anim
    property bool nudge: false
    // The glyph's free slot from the module: left/right reach from the centre, badge edges, opened room.
    property var slot: null

    signal finished()

    // These redraw the glyph themselves, so the module hides the real one while they play.
    readonly property bool hides_glyph: root.mode === "rumble" || root.mode === "transmission"
    // Drawn beneath the glyph row so the glyph and its count badge stay on top.
    readonly property bool under: ["pressanykey", "rumble", "transmission", "scan", "comms", "ping", "orders"].indexOf(root.mode) !== -1
    readonly property real strength: root.nudge ? 0.6 : 1
    readonly property real half: root.glyph_size / 2
    readonly property var durations: ({ bubble: [1200, 700], cursor: [1200, 600], pressanykey: [1400, 700], advance: [1400, 600], hand: [1200, 600], alert: [1000, 600], rumble: [1000, 450], transmission: [1200, 500], scan: [1300, 700], comms: [1200, 500], ping: [1400, 900], orders: [1400, 600] })
    readonly property int duration: (root.durations[root.mode] || root.durations.bubble)[root.nudge ? 1 : 0]
    property real elapsed
    readonly property real tail: 1 - root.phase(root.duration - 150, 150)
    // Distance from the origin to the window's top and bottom edges.
    property real room_up: 16
    property real room_down: 16
    readonly property real room: Math.min(root.room_up, root.room_down)

    readonly property real glyph_half: root.slot ? root.slot.glyph_half : root.half
    readonly property real room_left: root.slot ? root.slot.left : root.half + 5
    readonly property real room_right: root.slot ? root.slot.right : root.half + 5
    readonly property real content_right: root.slot ? root.slot.content_right : root.glyph_half
    readonly property real badge_bottom: root.slot && root.slot.badge ? root.slot.badge_bottom : -root.room_up

    function phase(start, length) {
        return Math.max(0, Math.min(1, (root.elapsed - start) / length));
    }

    function step(ms) {
        return Math.floor(root.elapsed / ms);
    }

    function out_quad(p) {
        return 1 - (1 - p) * (1 - p);
    }

    function out_back(p) {
        const c = 2.2;
        return 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2);
    }

    Component.onCompleted: {
        let top = root;
        while (top.parent) top = top.parent;
        const y = root.mapToItem(top, 0, 0).y;
        root.room_up = Math.max(8, y - 1);
        root.room_down = Math.max(8, top.height - y - 1);
    }

    NumberAnimation on elapsed {
        from: 0
        to: root.duration
        duration: root.duration
        onFinished: root.finished()
    }

    Loader {
        sourceComponent: ({ bubble: bubble_c, cursor: cursor_c, pressanykey: pressanykey_c, advance: advance_c, hand: hand_c, alert: alert_c, rumble: rumble_c, transmission: transmission_c, scan: scan_c, comms: comms_c, ping: ping_c, orders: orders_c })[root.mode] || bubble_c
    }

    Component {
        id: bubble_c

        Item {
            id: bubble
            readonly property real base: root.nudge ? 50 : 250
            readonly property real grow: root.nudge ? 1 : root.out_back(root.phase(0, 220))
            width: Math.min(15, root.room_left + 1)
            height: 9
            x: 2 - width
            y: Math.max(-root.room_up + 1, -root.half - 5)
            transformOrigin: Item.BottomRight
            scale: Math.min(bubble.grow, (root.room_left + 2) / width, (y + height + root.room_up) / height)
            opacity: root.tail * (root.nudge ? 0.75 : 1)

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Theme.bg_core
                border.color: root.color
                border.width: 1
            }

            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.bg_core
                    strokeColor: root.color
                    strokeWidth: 1
                    startX: bubble.width - 3
                    startY: bubble.height - 1.5
                    PathLine { x: bubble.width - 1; y: bubble.height + 3 }
                    PathLine { x: bubble.width - 7; y: bubble.height - 1.5 }
                }
            }

            Repeater {
                model: 3

                Rectangle {
                    required property int index
                    x: bubble.width / 2 - 5 + index * 4
                    y: 3.5 - (root.nudge ? 1.5 : 2) * Math.sin(Math.PI * root.phase(bubble.base + index * 120, 300))
                    width: 2
                    height: 2
                    radius: 1
                    color: root.color
                }
            }
        }
    }

    Component {
        id: cursor_c

        Rectangle {
            readonly property real foot: Math.min(root.room_down - 1, root.half)
            x: root.glyph_half + 1
            y: Math.max(root.badge_bottom + 1, root.half - root.glyph_size * 0.6)
            width: Math.max(2, Math.min(5, root.room_right - root.glyph_half - 2))
            height: foot - y
            color: Theme.theme_cursor
            opacity: root.strength
            visible: root.step(150) % 2 === 0
        }
    }

    Component {
        id: pressanykey_c

        Item {
            id: pak
            readonly property int frame: root.step(50)
            readonly property bool lit: frame >= 8 || [1, 0, 1, 1, 0, 1, 0, 1][frame] === 1
            readonly property real x0: -Math.min(root.room_left - 1, root.glyph_half + 2)
            readonly property real x1: Math.min(root.room_right - 1, root.nudge ? root.glyph_half + 2 : root.content_right + 5)

            Rectangle {
                x: pak.x0
                y: -height / 2
                width: pak.x1 - pak.x0
                height: Math.min(root.glyph_size + 2, 2 * root.room - 2)
                radius: 2
                color: root.color
                visible: !root.nudge || pak.lit
                opacity: root.nudge ? 0.3 * (1 - root.phase(0, 500)) : 0.35 * (1 - root.phase(0, 350))
            }
        }
    }

    Component {
        id: advance_c

        Item {
            x: Math.round(Math.min(root.glyph_half - 2, root.room_right - 10))
            y: Math.round(Math.min(root.room_down - 6, root.half - 4 + (root.step(200) % 2 ? 2 : 0)))
            opacity: root.strength

            Repeater {
                model: 5

                Rectangle {
                    required property int index
                    x: index
                    y: index
                    width: 9 - 2 * index
                    height: 1
                    color: Style.bar_fg
                }
            }
        }
    }

    Component {
        id: hand_c

        Item {
            readonly property var fills: [[0, 2, 5, 5], [5, 1, 6, 2], [5, 4, 3, 1], [5, 6, 2, 1], [1, 1, 3, 1]]
            x: Math.round(-root.room_left + 2 + (root.step(150) % 2 ? 2 : 0))
            y: Math.round(Math.min(root.room_down - 9, root.half - 8))
            opacity: root.strength

            Repeater {
                model: parent.fills

                Rectangle {
                    required property var modelData
                    x: modelData[0] - 1
                    y: modelData[1] - 1
                    width: modelData[2] + 2
                    height: modelData[3] + 2
                    color: Theme.bg_shadow
                }
            }

            Repeater {
                model: parent.fills

                Rectangle {
                    required property var modelData
                    x: modelData[0]
                    y: modelData[1]
                    width: modelData[2]
                    height: modelData[3]
                    color: Theme.fg_strong
                }
            }
        }
    }

    Component {
        id: alert_c

        Text {
            readonly property real p: root.phase(0, 180)
            readonly property real peak: root.nudge ? 1.15 : 1.3
            x: Math.max(-root.room_left + 1 + width * (peak - 1) / 2, -root.glyph_half + 1 - width / 2)
            y: Math.max(-root.room_up + height * (peak - 1), -root.half - height * 0.6)
            text: "!"
            color: Theme.theme_label
            font.family: root.font_family
            font.pixelSize: 12
            font.bold: true
            style: Text.Outline
            styleColor: Theme.bg_shadow
            transformOrigin: Item.Bottom
            scale: p < 0.6 ? peak * p / 0.6 : peak - (peak - 1) * (p - 0.6) / 0.4
            opacity: root.strength
        }
    }

    Component {
        id: rumble_c

        Text {
            readonly property var bursts: root.nudge ? [[0, 420]] : [[0, 380], [560, 940]]
            readonly property bool shaking: bursts.some(b => root.elapsed >= b[0] && root.elapsed < b[1])
            readonly property real amp: Math.max(0, Math.min(root.nudge ? 1 : 2, Math.min(root.room_left, root.room_right) - root.glyph_half - 1))
            x: -width / 2 + (shaking ? (root.step(35) % 2 ? 1 : -1) * amp : 0)
            y: -height / 2
            text: root.glyph
            color: root.color
            font.family: root.font_family
            font.pixelSize: root.glyph_size
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
        }
    }

    Component {
        id: transmission_c

        Item {
            id: transmission
            readonly property int frame: root.step(100)
            readonly property int blinks: root.nudge ? 2 : 5
            readonly property real foot: Math.min(root.room_down - 1, root.half)
            readonly property real tall: Math.max(3, Math.min(6, foot - root.badge_bottom - 1))

            Text {
                x: -width / 2
                y: -height / 2
                text: root.glyph
                color: root.color
                font.family: root.font_family
                font.pixelSize: root.glyph_size
                style: Style.bar_text_style
                styleColor: Style.bar_glow_color
                visible: transmission.frame % 2 === 1 || transmission.frame >= transmission.blinks * 2
            }

            Repeater {
                model: root.nudge ? 0 : 3

                Rectangle {
                    required property int index
                    x: Math.round(Math.min(root.glyph_half + 1, root.room_right - 9)) + index * 3
                    y: Math.round(transmission.foot) - height
                    width: 2
                    height: Math.round(transmission.tall * (index + 1) / 3)
                    color: root.color
                    visible: root.step(100) >= index * 2 + 1
                }
            }
        }
    }

    // Corner brackets hug the glyph and its badge, tightened to the slot; `grow` widens every side.
    component Frame: CornerBrackets {
        property real grow: 0
        readonly property real x0: -Math.min(root.room_left - 1, root.glyph_half + 2 + grow)
        readonly property real x1: Math.min(root.room_right - 1, root.content_right + 2 + grow)
        readonly property real y0: -Math.min(root.room_up - 1, root.half + 2 + grow)
        readonly property real y1: Math.min(root.room_down - 1, root.half + 2 + grow)
        x: x0
        y: y0
        width: x1 - x0
        height: y1 - y0
        inset: 0
        thickness: 1.5
        all_corners: true
    }

    Component {
        id: scan_c

        Item {
            opacity: root.tail * root.strength * (root.elapsed < 350 ? 1 : 0.55 + 0.45 * Math.cos((root.elapsed - 350) / 300 * 2 * Math.PI))

            Frame {
                grow: (root.nudge ? 2 : 5) * (1 - root.out_quad(root.phase(0, 350)))
                color: root.color
                arm: 4
            }
        }
    }

    Component {
        id: comms_c

        Item {
            opacity: root.tail * root.strength

            Frame {
                color: Theme.theme_label
                arm: 5
                visible: root.step(120) % 2 === 0
            }
        }
    }

    // Rings grow from inside the glyph out to the nearer slot edge, and to the window's edges.
    readonly property real ping_rx: Math.max(4, Math.min(root.room_left, root.room_right) - 1)
    readonly property real ping_ry: Math.max(4, root.room - 1)

    component Ring: ShapePath {
        id: ring
        property int delay
        property bool live: true
        readonly property real p: root.phase(delay, root.nudge ? 800 : 1000)
        readonly property real grow: 0.35 + 0.65 * root.out_quad(p)
        fillColor: "transparent"
        strokeColor: Qt.alpha(root.color, live && p > 0 && p < 1 ? 0.8 * root.strength * (1 - p) : 0)
        strokeWidth: 1

        PathAngleArc {
            centerX: root.ping_rx + 1
            centerY: root.ping_ry + 1
            radiusX: root.ping_rx * ring.grow
            radiusY: root.ping_ry * ring.grow
            startAngle: 0
            sweepAngle: 360
        }
    }

    Component {
        id: ping_c

        Shape {
            x: -root.ping_rx - 1
            y: -root.ping_ry - 1
            width: 2 * root.ping_rx + 2
            height: 2 * root.ping_ry + 2
            preferredRendererType: Shape.CurveRenderer

            Ring { delay: 0 }
            Ring { delay: 350; live: !root.nudge }
        }
    }

    Component {
        id: orders_c

        Item {
            id: orders
            readonly property int frame: root.step(140)
            readonly property bool lit: frame % 2 === 0 && frame < (root.nudge ? 2 : 6)
            readonly property color amber: Theme.bright_yellow
            readonly property real x0: -Math.min(root.room_left - 1, root.glyph_half + 3)
            readonly property real x1: Math.min(root.room_right - 1, root.glyph_half + 3)
            readonly property real box_height: Math.min(root.glyph_size + 4, 2 * root.room - 2)

            Rectangle {
                visible: orders.lit
                x: orders.x0
                y: -height / 2
                width: orders.x1 - orders.x0
                height: orders.box_height
                radius: 3
                color: Qt.alpha(orders.amber, 0.35 * root.strength)
                border.color: orders.amber
                border.width: 1
            }

            Hazard {
                visible: orders.lit
                x: orders.x0
                y: orders.box_height / 2 + 2
                width: orders.x1 - orders.x0
                height: 4
                stripe: Style.hazard.a > 0 ? Style.hazard : orders.amber
                tile: 6
                line: 2
            }
        }
    }
}
