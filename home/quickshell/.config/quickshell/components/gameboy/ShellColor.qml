// home/quickshell/.config/quickshell/components/gameboy/ShellColor.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"

// The Game Boy Color: a shell in the theme's primary, black bezel with the five-colour logo, round speaker holes.
Item {
    id: root

    property int screen_top: 26
    property int pad_top: 0

    readonly property color body: Qt.tint(Theme.theme_primary, Qt.alpha(Theme.fg_strong, 0.1))
    readonly property color body_low: Qt.tint(Theme.theme_primary, Qt.alpha(Theme.bg_crust, 0.3))
    readonly property color edge: Qt.tint(Theme.theme_primary, Qt.alpha(Theme.bg_crust, 0.6))
    readonly property color knob: "#1b1b20"
    readonly property color label: Qt.tint(Theme.theme_primary, Qt.alpha(Theme.bg_crust, 0.75))

    Rectangle {
        anchors.fill: parent
        radius: 10
        bottomLeftRadius: 28
        bottomRightRadius: 28
        border.width: 2
        border.color: root.edge
        gradient: Gradient {
            GradientStop { position: 0; color: root.body }
            GradientStop { position: 1; color: root.body_low }
        }
    }

    Rectangle {
        x: 6
        y: 6
        width: parent.width - 12
        height: root.pad_top - 6
        radius: 8
        bottomLeftRadius: 18
        bottomRightRadius: 18
        color: "#121216"
        border.width: 1
        border.color: "#000000"
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((6 + root.screen_top) / 2 - height / 2)
        spacing: 5

        Text {
            text: "GAME BOY"
            color: "#c9c9d2"
            font.family: "Silkscreen"
            font.pixelSize: 8
            font.letterSpacing: 1
        }

        Row {
            spacing: 1

            Repeater {
                model: [["C", "#e0457f"], ["O", "#6a62d6"], ["L", "#8ccf3f"], ["O", "#f2d43a"], ["R", "#2fb5ad"]]

                Text {
                    required property var modelData
                    text: modelData[0]
                    color: modelData[1]
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                    font.bold: true
                }
            }
        }
    }

    // Power lamp beside the screen.
    Rectangle {
        x: 9
        y: root.screen_top + 18
        width: 4
        height: 4
        radius: 2
        color: "#e2262f"
    }

    DPad {
        id: dpad
        x: 20
        y: root.pad_top + 8
        color: root.knob
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: dpad.y + 8
        spacing: 8
        rotation: -26

        Repeater {
            model: ["B", "A"]

            Rectangle {
                required property string modelData
                width: 20
                height: 20
                radius: 10
                color: root.knob
                border.width: 1
                border.color: "#000000"

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: "#77777f"
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dpad.y + dpad.height + 4
        spacing: 12

        Repeater {
            model: ["SELECT", "START"]

            Column {
                required property string modelData
                spacing: 2

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 20
                    height: 6
                    radius: 3
                    color: root.knob
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

    // Speaker holes in the right corner.
    Grid {
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        columns: 3
        spacing: 3

        Repeater {
            model: 6

            Rectangle {
                width: 3
                height: 3
                radius: 1.5
                color: root.edge
            }
        }
    }
}
