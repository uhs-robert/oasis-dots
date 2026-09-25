// home/quickshell/.config/quickshell/components/ps1/BiosPanel.qml
import QtQuick
import "../../theme"

// A PS1 BIOS menu panel: deep blue shading with a glossy upper half and a light rim; lit when picked.
Rectangle {
    id: root

    property bool lit: false

    radius: 6
    border.width: 1
    border.color: root.lit ? Theme.theme_primary_light : Qt.alpha(Theme.blue, 0.55)
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.tint(Theme.bg_surface, Qt.alpha(Theme.blue, root.lit ? 0.6 : 0.38)) }
        GradientStop { position: 1; color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.blue, root.lit ? 0.34 : 0.16)) }
    }

    Rectangle {
        x: 2
        y: 2
        width: parent.width - 4
        height: (parent.height - 4) / 2
        radius: Math.max(0, parent.radius - 2)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.fg_strong, root.lit ? 0.24 : 0.14) }
            GradientStop { position: 1; color: Qt.alpha(Theme.fg_strong, 0.03) }
        }
    }
}
