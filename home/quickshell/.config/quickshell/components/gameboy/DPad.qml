// home/quickshell/.config/quickshell/components/gameboy/DPad.qml
import QtQuick

// A handheld's cross pad, three arm widths square, with a dimple at the hub.
Item {
    id: root

    property int arm: 12
    property color color: "black"
    property color dimple: Qt.lighter(root.color, 1.6)

    width: root.arm * 3
    height: root.arm * 3

    Rectangle {
        x: root.arm
        width: root.arm
        height: root.height
        radius: 2
        color: root.color
    }

    Rectangle {
        y: root.arm
        width: root.width
        height: root.arm
        radius: 2
        color: root.color
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.arm - 6
        height: root.arm - 6
        radius: width / 2
        color: root.dimple
    }
}
