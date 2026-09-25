// home/quickshell/.config/quickshell/components/snes/SnesWindow.qml
import QtQuick
import "../../theme"

// A SNES RPG menu window: blue vertical gradient in a rounded light double border, with a hard drop shadow.
Item {
    id: root

    property real radius: 6
    // The shadow's offset; the panel gives up this much room at the right and bottom for it.
    property int drop: 3
    // Lights the border for the window that holds the cursor.
    property bool lit: false
    property color top_color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary_strong, 0.72))
    property color bottom_color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_primary_strong, 0.16))
    readonly property alias panel: panel

    Rectangle {
        visible: root.drop > 0
        anchors.fill: panel
        anchors.topMargin: root.drop
        anchors.leftMargin: root.drop
        anchors.rightMargin: -root.drop
        anchors.bottomMargin: -root.drop
        radius: panel.radius
        color: Qt.alpha(Theme.bg_shadow, 0.7)
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        anchors.rightMargin: root.drop
        anchors.bottomMargin: root.drop
        radius: root.radius
        border.width: 2
        border.color: root.lit ? Theme.theme_secondary : Theme.fg_strong
        gradient: Gradient {
            GradientStop { position: 0; color: root.top_color }
            GradientStop { position: 1; color: root.bottom_color }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Math.max(0, root.radius - 2)
            color: "transparent"
            border.width: 1
            border.color: Theme.fg_dim
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: Math.max(0, root.radius - 3)
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.bg_shadow, 0.45)
        }
    }
}
