import QtQuick
import ".."
import "../../theme"

// A weapon's materia socket, bare or holding an orb; lit rings it in the ready glow.
Item {
    id: root

    property color color: "transparent"
    property bool lit: false
    property bool raised: false

    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        visible: root.lit
        anchors.fill: parent
        anchors.margins: -3
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Qt.alpha(Theme.theme_secondary, 0.35)
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.bg_crust
        border.width: 2
        border.color: root.lit ? Theme.theme_secondary : root.raised ? Style.frame_border_color : Qt.tint(Theme.fg_dim, Qt.alpha(Theme.bg_surface, 0.3))

        Behavior on border.color {
            ColorAnimation { duration: 200 }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.bg_shadow, 0.8)
        }
    }

    MateriaOrb {
        visible: root.color.a > 0
        anchors.centerIn: parent
        width: parent.width - 6
        height: width
        glow: false
        color: root.color
    }
}
