// home/quickshell/.config/quickshell/components/picker/LabelPlate.qml
import QtQuick
import "../../theme"

// Dark backing behind a HUD label so it reads over any window content.
Rectangle {
    required property Item target
    property Item from: target
    property int pad_x: 4
    property int pad_y: 1

    visible: target.visible
    x: from.x - pad_x
    y: Math.min(from.y, target.y) - pad_y
    width: target.x + target.width - from.x + pad_x * 2
    height: Math.max(from.y + from.height, target.y + target.height) - Math.min(from.y, target.y) + pad_y * 2
    color: Qt.alpha(Theme.bg_shadow, 0.75)
}
