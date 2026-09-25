// home/quickshell/.config/quickshell/components/DeviceShell.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../theme"

// A Game Boy around a small popup: shell, bezel with power LED, the pixel screen, then D-pad, B/A and Select/Start.
Item {
    id: root

    property var st: Style.for_item(root)
    // Room the popup keeps clear of its content at each side, above the title and below the footer.
    property int room_side: 20
    property int room_top: 30
    property int room_bottom: 80

    readonly property color shell: Qt.tint(Theme.fg_muted, Qt.alpha(Theme.bg_surface, 0.85))
    readonly property color shell_low: Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.bg_surface, 0.6))
    readonly property color bezel_color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.bg_mantle, 0.8))
    readonly property color knob: Theme.bg_crust
    readonly property int screen_top: root.room_top - 4
    readonly property int screen_bottom: root.height - root.room_bottom - 4
    readonly property int pad_top: root.height - root.room_bottom + 6

    Rectangle {
        anchors.fill: parent
        bottomLeftRadius: 12
        bottomRightRadius: 34
        border.width: 2
        border.color: Theme.bg_crust
        gradient: Gradient {
            GradientStop { position: 0; color: root.shell }
            GradientStop { position: 1; color: root.shell_low }
        }
    }

    Rectangle {
        x: 2
        y: 2
        width: parent.width - 4
        height: 1
        color: Qt.alpha(Theme.fg_strong, 0.08)
    }

    Rectangle {
        id: bezel
        x: 6
        y: 6
        width: parent.width - 12
        height: root.pad_top - 6
        radius: 6
        bottomRightRadius: 22
        color: root.bezel_color
        border.width: 1
        border.color: Theme.bg_crust
    }

    Row {
        id: badge
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((6 + root.screen_top) / 2 - height / 2)
        spacing: 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: Theme.theme_label
        }

        Text {
            text: "DOT MATRIX"
            color: Theme.fg_dim
            font.family: "Silkscreen"
            font.pixelSize: 8
            font.letterSpacing: 1
        }
    }

    Repeater {
        model: [[16, badge.x - 8], [badge.x + badge.width + 8, root.width - 16]]

        Item {
            required property var modelData
            x: modelData[0]
            y: badge.y + Math.round(badge.height / 2) - 2
            width: Math.max(0, modelData[1] - modelData[0])
            height: 4
            opacity: 0.7

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.theme_label
            }

            Rectangle {
                y: 2
                width: parent.width
                height: 1
                color: Theme.theme_primary_strong
            }
        }
    }

    Rectangle {
        id: screen
        x: root.room_side - 4
        y: root.screen_top
        width: parent.width - x * 2
        height: Math.max(0, root.screen_bottom - root.screen_top)
        color: root.st.shade_1
        clip: true

        Repeater {
            model: Math.max(0, Math.ceil(screen.height / 3))

            Rectangle {
                required property int index
                y: index * 3
                width: screen.width
                height: 1
                color: Qt.alpha(Theme.bg_crust, 0.12)
            }
        }

        PixelBox {
            anchors.fill: parent
            rings: [root.st.shade_0, root.st.shade_2, root.st.shade_0]
        }
    }

    Item {
        id: dpad
        x: 18
        y: root.pad_top + 10
        width: 36
        height: 36

        Rectangle {
            x: 12
            width: 12
            height: 36
            radius: 2
            color: root.knob
        }

        Rectangle {
            y: 12
            width: 36
            height: 12
            radius: 2
            color: root.knob
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: dpad.y + 8
        spacing: 8
        rotation: -22

        Repeater {
            model: ["B", "A"]

            Rectangle {
                required property string modelData
                width: 20
                height: 20
                radius: 10
                color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.theme_label, 0.7))
                border.width: 1
                border.color: Qt.alpha(Theme.bg_crust, 0.35)

                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: Theme.bg_crust
                    font.family: "Press Start 2P"
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
                    color: root.knob
                }

                Text {
                    text: parent.modelData
                    color: Theme.fg_dim
                    font.family: "Silkscreen"
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }
            }
        }
    }
}
