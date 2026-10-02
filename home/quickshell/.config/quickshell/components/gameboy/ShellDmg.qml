// home/quickshell/.config/quickshell/components/gameboy/ShellDmg.qml
pragma ComponentBehavior: Bound
import QtQuick

// The 1989 Game Boy in its stock colours: grey shell, slate bezel, magenta B/A and the speaker slots.
Item {
    id: root

    property int screen_top: 26
    property int pad_top: 0

    readonly property color body: "#c6c4bd"
    readonly property color body_low: "#b0aea7"
    readonly property color edge: "#85837d"
    readonly property color slate: "#5c5f6b"
    readonly property color ink: "#2b2d7e"
    readonly property color rubber: "#84828a"
    readonly property color knob: "#1d1d21"

    Rectangle {
        anchors.fill: parent
        radius: 6
        bottomRightRadius: 34
        border.width: 2
        border.color: root.edge
        gradient: Gradient {
            GradientStop { position: 0; color: root.body }
            GradientStop { position: 1; color: root.body_low }
        }
    }

    // The groove across the top, cut by a notch near each end.
    Rectangle {
        x: 2
        y: 5
        width: parent.width - 4
        height: 1
        color: root.edge
    }

    Repeater {
        model: [16, root.width - 17]

        Rectangle {
            required property int modelData
            x: modelData
            y: 2
            width: 1
            height: 3
            color: root.edge
        }
    }

    Rectangle {
        x: 6
        y: 9
        width: parent.width - 12
        height: root.pad_top - 9
        radius: 6
        bottomRightRadius: 22
        color: root.slate
        border.width: 1
        border.color: Qt.darker(root.slate, 1.3)
    }

    Text {
        id: badge
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((9 + root.screen_top) / 2 - height / 2)
        text: full.implicitWidth + 70 <= root.width ? full.text : "DOT MATRIX"
        color: "#b8bbc6"
        font: full.font

        Text {
            id: full
            visible: false
            text: "DOT MATRIX WITH STEREO SOUND"
            font.family: "Silkscreen"
            font.pixelSize: 8
            font.letterSpacing: 1
        }
    }

    Repeater {
        model: [[16, badge.x - 6], [badge.x + badge.width + 6, root.width - 16]]

        Item {
            required property var modelData
            x: modelData[0]
            y: badge.y + Math.round(badge.height / 2) - 2
            width: Math.max(0, modelData[1] - modelData[0])
            height: 4

            Rectangle {
                width: parent.width
                height: 1
                color: "#8c1d4f"
            }

            Rectangle {
                y: 3
                width: parent.width
                height: 1
                color: "#27277a"
            }
        }
    }

    // Battery lamp beside the screen.
    Rectangle {
        x: 9
        y: root.screen_top + 18
        width: 4
        height: 4
        radius: 2
        color: "#d8202c"
    }

    DPad {
        id: dpad
        x: 18
        y: root.pad_top + 10
        color: root.knob
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: dpad.y + 2
        spacing: 8
        rotation: -22

        Repeater {
            model: ["B", "A"]

            Column {
                required property string modelData
                spacing: 2

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: "#9a2257"
                    border.width: 1
                    border.color: "#6f1640"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.modelData
                    color: root.ink
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dpad.y + dpad.height + 2
        spacing: 12

        Repeater {
            model: ["SELECT", "START"]

            Column {
                required property string modelData
                spacing: 3

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 22
                    height: 6
                    radius: 3
                    rotation: -22
                    color: root.rubber
                }

                Text {
                    text: parent.modelData
                    color: root.ink
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }
            }
        }
    }

    // Speaker slots in the round corner.
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7
        spacing: 4
        rotation: -28

        Repeater {
            model: 5

            Rectangle {
                width: 2
                height: 14
                radius: 1
                color: root.edge
            }
        }
    }
}
