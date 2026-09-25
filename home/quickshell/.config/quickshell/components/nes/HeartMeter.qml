// home/quickshell/.config/quickshell/components/nes/HeartMeter.qml
import QtQuick
import "../../theme"
import ".."

// Zelda heart containers as a Meter's art: ten hearts (five when narrow), each half a step.
Item {
    id: root

    property var meter: null
    property real value: root.meter ? root.meter.value : 0
    readonly property int count: root.width >= 160 ? 10 : 5
    readonly property int halves: Math.round(Math.max(0, Math.min(1, root.value)) * root.count * 2)
    readonly property int pixel: Math.max(1, Math.min(Math.floor(root.width / (root.count * 8)), Math.floor(root.height / 6)))
    readonly property var shape: [".11.11.", "1211111", "1111111", ".11111.", "..111..", "...1..."]
    readonly property color red: Qt.tint(Theme.red, Qt.alpha(Theme.theme_label, 0.4))
    // The hearts sit left-aligned, so clicks map across this width only.
    readonly property real art_width: hearts.width

    Row {
        id: hearts
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pixel

        Repeater {
            model: root.count

            PixelSprite {
                required property int index
                readonly property int fill: Math.max(0, Math.min(2, root.halves - index * 2))

                pixel: root.pixel
                rows: root.shape.map(r => r.split("").map((c, x) => c === "." ? "." : fill === 2 || (fill === 1 && x <= 3) ? (c === "2" ? "2" : "0") : "1").join(""))
                colors: [root.red, Theme.bg_surface, Qt.tint(root.red, Qt.alpha(Theme.fg_strong, 0.55)), "transparent"]
            }
        }
    }
}
