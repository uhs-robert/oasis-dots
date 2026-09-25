// home/quickshell/.config/quickshell/components/nes/CoinMeter.qml
import QtQuick
import "../../theme"
import ".."

// A signal meter of Mario coins: one lit coin per quarter of the value, dim outline when unlit.
Row {
    id: root

    property real value: 0
    property int count: 4
    property int size: 12
    readonly property int lit: Math.ceil(Math.max(0, Math.min(1, root.value)) * root.count - 0.001)
    readonly property var shape: [".00.", "0110", "0110", ".00."]

    spacing: 2

    Repeater {
        model: root.count

        PixelSprite {
            id: coin
            required property int index
            readonly property bool on: coin.index < root.lit

            pixel: Math.max(1, Math.floor(root.size / 4))
            rows: coin.on ? root.shape : root.shape.map(r => r.replace(/1/g, "."))
            colors: coin.on ? [Theme.theme_secondary_strong, Theme.theme_secondary] : [Theme.bg_surface, "transparent"]
        }
    }
}
