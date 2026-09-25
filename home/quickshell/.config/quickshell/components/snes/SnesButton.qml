// home/quickshell/.config/quickshell/components/snes/SnesButton.qml
import QtQuick
import "../../theme"

// One Super Famicom controller button: a/b/x/y face buttons, l/r/lr shoulders, the start/select pill, or the D-pad lit on dpad_v/dpad_h.
Item {
    id: root

    property string button: "a"
    property int size: 13

    readonly property bool face: ["a", "b", "x", "y"].indexOf(root.button) >= 0
    readonly property bool shoulder: root.button === "l" || root.button === "r" || root.button === "lr"
    readonly property bool dpad: root.button === "dpad_v" || root.button === "dpad_h"
    readonly property bool pill: root.button === "start" || root.button === "select"

    // Super Famicom hardware colors pulled halfway into the theme's own hues.
    readonly property var face_colors: ({
        a: Qt.tint(Theme.red, Qt.alpha("#d8292f", 0.5)),
        b: Qt.tint(Theme.yellow, Qt.alpha("#f1c232", 0.5)),
        x: Qt.tint(Theme.blue, Qt.alpha("#3e5cc0", 0.55)),
        y: Qt.tint(Theme.green, Qt.alpha("#27a04a", 0.5))
    })
    readonly property color face_color: root.face ? root.face_colors[root.button] : "transparent"
    readonly property color plastic: Qt.tint(Theme.fg_dim, Qt.alpha("#a4a4b4", 0.45))
    readonly property color dark_plastic: Qt.tint(Theme.bg_surface, Qt.alpha("#3a3a44", 0.5))

    implicitWidth: root.face || root.dpad ? root.size : root.shoulder ? shoulders.implicitWidth : pill_label.implicitWidth + 8
    implicitHeight: root.size

    Rectangle {
        visible: root.face
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        color: root.face_color
        border.width: 1
        border.color: Qt.darker(root.face_color, 1.7)

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 0.5
            text: root.button.toUpperCase()
            color: root.button === "b" || root.button === "y" ? Theme.bg_crust : Theme.fg_strong
            font.family: "Silkscreen"
            font.pixelSize: 8
        }
    }

    Row {
        id: shoulders
        visible: root.shoulder
        spacing: 2

        Repeater {
            model: root.button === "lr" ? ["l", "r"] : [root.button]

            Rectangle {
                id: shoulder_cap
                required property string modelData
                readonly property bool is_left: shoulder_cap.modelData === "l"
                width: Math.round(root.size * 1.4)
                height: root.size - 2
                y: 1
                topLeftRadius: shoulder_cap.is_left ? height : 2
                topRightRadius: shoulder_cap.is_left ? 2 : height
                bottomLeftRadius: 2
                bottomRightRadius: 2
                antialiasing: true
                color: root.plastic
                border.width: 1
                border.color: Qt.darker(root.plastic, 1.8)

                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: shoulder_cap.is_left ? 1 : -1
                    text: shoulder_cap.modelData.toUpperCase()
                    color: Theme.bg_crust
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                }
            }
        }
    }

    Rectangle {
        visible: root.pill
        anchors.fill: parent
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: height / 2
        antialiasing: true
        color: root.dark_plastic
        border.width: 1
        border.color: Qt.lighter(root.dark_plastic, 1.6)

        Text {
            id: pill_label
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 0.5
            text: root.button.toUpperCase()
            color: Theme.fg_strong
            font.family: "Silkscreen"
            font.pixelSize: 8
        }
    }

    Item {
        id: dpad_box
        visible: root.dpad
        anchors.fill: parent
        readonly property real arm: Math.round(root.size * 0.38)
        readonly property real inset: Math.round((root.size - arm) / 2)

        Rectangle {
            x: dpad_box.inset
            width: dpad_box.arm
            height: root.size
            radius: 1
            color: root.dark_plastic
            border.width: 1
            border.color: Qt.lighter(root.dark_plastic, 1.6)
        }

        Rectangle {
            y: dpad_box.inset
            width: root.size
            height: dpad_box.arm
            radius: 1
            color: root.dark_plastic
            border.width: 1
            border.color: Qt.lighter(root.dark_plastic, 1.6)
        }

        Repeater {
            model: root.button === "dpad_v" ? [[1, 0], [1, 2]] : [[0, 1], [2, 1]]

            Rectangle {
                required property var modelData
                readonly property real step: (root.size - dpad_box.arm) / 2
                x: modelData[0] === 1 ? dpad_box.inset + 1 : modelData[0] === 0 ? 1 : root.size - step
                y: modelData[1] === 1 ? dpad_box.inset + 1 : modelData[1] === 0 ? 1 : root.size - step
                width: modelData[0] === 1 ? dpad_box.arm - 2 : step - 1
                height: modelData[1] === 1 ? dpad_box.arm - 2 : step - 1
                color: Theme.theme_secondary
            }
        }
    }
}
