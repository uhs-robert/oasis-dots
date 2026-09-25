pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "../../theme"
import "Covers.js" as Covers

// Paints a cover over the bar, clipped to the islands by the bar's own alpha.
Item {
    id: root

    required property Item target
    property string kind: "blocks"
    property int cover: 300
    property int reveal: 450
    property int start_at: 0
    // Holds at start_at until released, for the startup intro.
    property bool hold: false
    property real elapsed

    signal finished()

    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")";
    }

    readonly property var colors: ({
        cover: root.css(Theme.bg_shadow, 1),
        primary: root.css(Theme.theme_primary, 1),
        primary_clear: root.css(Theme.theme_primary, 0),
        secondary: root.css(Theme.theme_secondary, 1),
        strong: root.css(Theme.fg_strong, 1),
        dim: root.css(Theme.fg_dim, 1),
        accent: root.css(Style.accent_color.a > 0 ? Style.accent_color : Theme.theme_primary, 1),
        caret: root.css(Style.caret_color.a > 0 ? Style.caret_color : Theme.theme_cursor, 1),
        cell: Math.max(6, Math.round(Style.bar_font_size * 0.62))
    })

    onElapsedChanged: canvas.requestPaint()

    Component.onCompleted: root.elapsed = root.start_at

    NumberAnimation on elapsed {
        from: root.start_at
        to: root.cover + root.reveal
        duration: root.cover + root.reveal - root.start_at
        running: !root.hold
        onFinished: root.finished()
    }

    ShaderEffectSource {
        id: mask
        anchors.fill: parent
        sourceItem: root.target
        visible: false
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
        onPaint: Covers.paint(canvas.getContext("2d"), root.kind, root.elapsed, root.cover, root.reveal, canvas.width, canvas.height, root.colors)
    }
}
