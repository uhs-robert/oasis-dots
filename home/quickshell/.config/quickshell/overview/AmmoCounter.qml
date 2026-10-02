// home/quickshell/.config/quickshell/overview/AmmoCounter.qml
import QtQuick
import "../theme"
import "../lock/skins/goldeneye/Watch.js" as W

// The game's ammo readout for the overview: the selected window, a brass bullet and the window count, as `N | M`.
Rectangle {
    id: root

    property int index: 0
    property int total: 0

    implicitWidth: row.implicitWidth + 24
    implicitHeight: row.implicitHeight + 14
    radius: 6
    color: "#99000000"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.index
            color: Style.wk.lit
            font.family: W.digit_font
            font.pixelSize: 28
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 28

            Rectangle {
                x: 1
                y: 0
                width: 8
                height: 18
                topLeftRadius: 4
                topRightRadius: 4
                color: W.warm[5]
            }

            Rectangle {
                x: 0
                y: 19
                width: 10
                height: 8
                color: W.warm[3]
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.total
            color: Style.wk.lit
            font.family: W.digit_font
            font.pixelSize: 28
        }
    }
}
