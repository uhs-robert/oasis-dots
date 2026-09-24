// home/quickshell/.config/quickshell/popups/weather/WsPanel.qml
import QtQuick
import "../../theme"

// A WeatherStar 4000 panel: a blue gradient with a raised bevel, outlined in yellow when lit.
Item {
    id: root

    property bool lit: false
    readonly property int bevel: 2

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary_strong, root.lit ? 0.85 : 0.7)) }
            GradientStop { position: 1; color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary_strong, root.lit ? 0.45 : 0.3)) }
        }
    }

    Rectangle {
        width: parent.width
        height: root.bevel
        color: Qt.alpha(Theme.theme_primary_light, 0.75)
    }

    Rectangle {
        width: root.bevel
        height: parent.height
        color: Qt.alpha(Theme.theme_primary_light, 0.5)
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.bevel
        color: Qt.alpha(Theme.bg_shadow, 0.8)
    }

    Rectangle {
        anchors.right: parent.right
        width: root.bevel
        height: parent.height
        color: Qt.alpha(Theme.bg_shadow, 0.8)
    }

    Rectangle {
        visible: root.lit
        anchors.fill: parent
        anchors.margins: -2
        color: "transparent"
        border.width: 2
        border.color: Theme.theme_secondary
    }
}
