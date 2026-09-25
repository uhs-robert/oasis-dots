// home/quickshell/.config/quickshell/components/snes/SnesGauge.qml
import QtQuick
import ".."
import "../../theme"

// An ATB-style bar lit left to right from deep blue into light blue; past hot_from it turns the hot color.
AtbBar {
    id: root

    property bool dim: false

    horizontal: true
    implicitHeight: 8
    fill_color: root.dim ? Theme.fg_muted : Theme.theme_primary_strong
    shade_color: root.dim ? Theme.fg_dim : Qt.tint(Theme.theme_primary_light, Qt.alpha(Theme.fg_strong, 0.3))
    hot_color: Theme.theme_label
}
