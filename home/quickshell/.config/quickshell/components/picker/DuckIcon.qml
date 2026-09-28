// home/quickshell/.config/quickshell/components/picker/DuckIcon.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import ".."

// A ~12x10 pixel duck silhouette: the Duck Hunt skin's unit for shots, hits and window/output markers.
PixelSprite {
    id: root

    property color fill: Theme.fg_muted

    readonly property var shape: [
        "....1111....",
        "...111111...",
        "..111111111.",
        ".11111111111",
        "11111111111.",
        "1111111111..",
        ".1111111111.",
        ".1111111111.",
        ".11111111111",
        "..1111111111"
    ]

    pixel: 1
    rows: root.shape
    colors: ["transparent", root.fill]
}
