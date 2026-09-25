// home/quickshell/.config/quickshell/components/ps2/AnalogLed.qml
import QtQuick
import "../../theme"

// The DualShock 2 ANALOG lamp: a red LED, lit while its popup holds the keyboard.
Row {
    id: root

    property bool lit: false
    readonly property color led: Qt.tint("#FF3B30", Qt.alpha(Theme.red, 0.4))

    spacing: 5

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "ANALOG"
        color: Qt.alpha(Theme.theme_primary_light, 0.6)
        font.family: "Exo 2"
        font.pixelSize: 8
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: 7
        height: 7

        Rectangle {
            visible: root.lit
            anchors.centerIn: parent
            width: 15
            height: 15
            radius: 7.5
            color: Qt.alpha(root.led, 0.22)
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.lit ? root.led : Qt.alpha(Qt.darker(root.led, 2.6), 0.9)
            border.width: 1
            border.color: Qt.alpha(Theme.bg_shadow, 0.8)
        }

        Rectangle {
            x: 1.5
            y: 1
            width: 3
            height: 2
            radius: 1
            color: Qt.alpha(Theme.fg_strong, root.lit ? 0.7 : 0.2)
        }
    }
}
