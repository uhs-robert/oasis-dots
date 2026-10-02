// home/quickshell/.config/quickshell/components/gameboy/ShellSp.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// The Game Boy Advance SP open: the screen in the lid, a hinge, then the pad on the base.
Item {
    id: root

    property int screen_top: 26
    property int pad_top: 0

    readonly property color body: Qt.tint(Theme.fg_muted, Qt.alpha(Theme.theme_primary, 0.3))
    readonly property color body_low: Qt.tint(root.body, Qt.alpha(Theme.bg_crust, 0.3))
    readonly property color edge: Qt.tint(root.body, Qt.alpha(Theme.bg_crust, 0.6))
    readonly property color knob: Qt.tint(root.body, Qt.alpha(Theme.fg_strong, 0.45))
    readonly property color label: Qt.tint(root.body, Qt.alpha(Theme.bg_crust, 0.7))
    readonly property int hinge_top: root.pad_top - 1

    component Half: Rectangle {
        radius: 12
        border.width: 2
        border.color: root.edge
        gradient: Gradient {
            GradientStop { position: 0; color: root.body }
            GradientStop { position: 1; color: root.body_low }
        }
    }

    Half {
        width: parent.width
        height: root.hinge_top + 3
        bottomLeftRadius: 4
        bottomRightRadius: 4
    }

    Half {
        y: root.hinge_top + 7
        width: parent.width
        height: parent.height - y
        topLeftRadius: 4
        topRightRadius: 4
    }

    Rectangle {
        x: 20
        y: root.hinge_top
        width: parent.width - 40
        height: 10
        radius: 5
        color: root.body_low
        border.width: 1
        border.color: root.edge
    }

    Repeater {
        model: [6, root.width - 18]

        Rectangle {
            required property int modelData
            x: modelData
            y: root.hinge_top
            width: 12
            height: 10
            radius: 4
            color: root.body_low
            border.width: 1
            border.color: root.edge
        }
    }

    // The black glass around the screen.
    Rectangle {
        x: 8
        y: root.screen_top - 8
        width: parent.width - 16
        height: root.hinge_top - y - 2
        radius: 4
        color: "#101014"
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((2 + root.screen_top - 8) / 2 - height / 2)
        text: "GAME BOY ADVANCE SP"
        color: root.label
        font.family: "Silkscreen"
        font.pixelSize: 8
        font.letterSpacing: 1
    }

    DPad {
        id: dpad
        x: 20
        y: root.hinge_top + 20
        arm: 10
        color: root.knob
        dimple: root.body_low
    }

    Repeater {
        model: [["B", 62, 16], ["A", 36, 4]]

        Rectangle {
            required property var modelData
            x: root.width - modelData[1]
            y: dpad.y + modelData[2]
            width: 18
            height: 18
            radius: 9
            color: root.knob
            border.width: 1
            border.color: root.edge

            Text {
                anchors.centerIn: parent
                text: parent.modelData[0]
                color: root.label
                font.family: "Silkscreen"
                font.pixelSize: 8
            }
        }
    }

    // Backlight button under the hinge.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.hinge_top + 16
        width: 8
        height: 8
        radius: 4
        color: root.knob
        border.width: 1
        border.color: root.edge
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 12

        Repeater {
            model: ["SELECT", "START"]

            Column {
                required property string modelData
                spacing: 2

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 12
                    height: 6
                    radius: 3
                    color: root.knob
                    border.width: 1
                    border.color: root.edge
                }

                Text {
                    text: parent.modelData
                    color: root.label
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }
            }
        }
    }

    // Power and charge lamps on the base's right edge.
    Column {
        anchors.right: parent.right
        anchors.rightMargin: 7
        y: root.hinge_top + 16
        spacing: 4

        Repeater {
            model: [Theme.ok, Theme.warning]

            Rectangle {
                required property color modelData
                width: 3
                height: 5
                radius: 1
                color: modelData
            }
        }
    }
}
