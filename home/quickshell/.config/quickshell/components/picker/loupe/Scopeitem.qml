// home/quickshell/.config/quickshell/components/picker/loupe/Scopeitem.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../../theme"
import "../../../services"
import "../.."
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 36
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.si_pad * 2 + root.si_body_w
    implicitHeight: root.si_pad + root.si_ruler_h + root.loupe.view + root.si_foot_gap + root.si_foot_h + root.si_pad

    readonly property real si_pad: 10
    readonly property real si_ruler_h: 22
    readonly property real si_zbar_w: 30
    readonly property real si_body_gap: 10
    readonly property real si_foot_gap: 8
    readonly property real si_foot_h: 20
    readonly property real si_body_w: root.loupe.view + root.si_body_gap + root.si_zbar_w
    readonly property real header_h: root.si_ruler_h

    Rectangle {
        anchors.fill: parent
        radius: 6
        border.width: 1
        border.color: Qt.alpha(Theme.blue, 0.65)
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.tint(Theme.bg_crust, Qt.alpha(Theme.blue, 0.16))
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Theme.bg_crust, 0.9)
            }
        }
    }

    Rectangle {
        x: 1
        y: 1
        width: parent.width - 2
        height: 1
        color: Qt.alpha(Theme.fg_strong, 0.18)
    }

    Item {
        id: si_ruler
        x: root.si_pad
        y: root.si_pad
        width: root.si_body_w
        height: root.si_ruler_h
        clip: true

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.blue, 0.6)
        }

        Shape {
            id: si_caret
            x: parent.width / 2 - 5
            y: 0
            width: 10
            height: 5
            ShapePath {
                fillColor: Theme.theme_secondary
                strokeWidth: -1
                startX: 0
                startY: 0
                PathLine {
                    x: 10
                    y: 0
                }
                PathLine {
                    x: 5
                    y: 5
                }
                PathLine {
                    x: 0
                    y: 0
                }
            }
        }

        Repeater {
            model: si_ruler.visible ? Math.ceil(si_ruler.width / 40) + 2 : 0

            Text {
                id: si_tick
                required property int index
                readonly property real step: 40
                readonly property real base_x: Math.round(root.loupe.screen_x + root.loupe.at.x)
                readonly property real first: Math.ceil((si_tick.base_x - si_ruler.width / 2) / si_tick.step) * si_tick.step
                readonly property real global_v: si_tick.first + si_tick.index * si_tick.step
                x: si_ruler.width / 2 + (si_tick.global_v - si_tick.base_x) - si_tick.implicitWidth / 2
                y: si_ruler.height - si_tick.implicitHeight - 5
                text: (si_tick.global_v < 0 ? "-" : "") + String(Math.abs(Math.round(si_tick.global_v))).padStart(4, "0")
                color: Theme.theme_primary_light
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-8)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 1
                    width: 1
                    height: 4
                    color: Theme.blue
                }
            }
        }
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.si_pad
        y: root.si_pad + root.si_ruler_h
        center_color: Theme.theme_secondary

        Repeater {
            model: Math.ceil(root.loupe.view / 3)

            Rectangle {
                required property int index
                y: index * 3
                width: root.loupe.view
                height: 1
                color: Qt.alpha(Theme.bg_shadow, 0.14)
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Theme.blue, 0.55)
        }

        CornerBrackets {
            anchors.fill: parent
            color: Theme.blue
            inset: 6
            arm: 14
            thickness: 2
            all_corners: true
        }
    }

    Column {
        id: si_zbar
        x: root.si_pad + root.loupe.view + root.si_body_gap
        y: root.si_pad + root.si_ruler_h + root.loupe.view - si_zbar.implicitHeight
        spacing: 3

        Repeater {
            model: [3, 2, 1, 0]

            Rectangle {
                id: si_seg
                required property int modelData
                readonly property int step: Screenshot.zoom_levels[si_seg.modelData]
                width: root.si_zbar_w
                height: 10
                color: si_seg.step <= root.loupe.zoom ? Theme.blue : "transparent"
                border.width: si_seg.step <= root.loupe.zoom ? 0 : 1
                border.color: Qt.alpha(Theme.blue, 0.5)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "x" + root.loupe.zoom
            color: Theme.blue
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-7)
        }
    }

    Item {
        id: si_foot
        x: root.si_pad
        y: root.si_pad + root.si_ruler_h + root.loupe.view + root.si_foot_gap
        width: root.si_body_w
        height: root.si_foot_h

        Row {
            id: si_chip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: si_icon.width + 6
                height: si_icon.height + 4
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.5)

                Item {
                    id: si_icon
                    anchors.centerIn: parent
                    width: 22
                    height: 11

                    Rectangle {
                        x: 0
                        y: 1
                        width: 9
                        height: 9
                        radius: 4
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.blue
                    }

                    Rectangle {
                        x: 13
                        y: 1
                        width: 9
                        height: 9
                        radius: 4
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.blue
                    }

                    Rectangle {
                        x: 8
                        y: 4
                        width: 6
                        height: 3
                        color: Theme.blue
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.loupe.pixel_mode ? "SCOPE" : "CAMERA"
                color: Theme.fg_strong
                font.family: Style.font_family
                font.bold: true
                font.letterSpacing: 1
                font.pixelSize: Style.fs(-6)
            }
        }

        Row {
            id: si_pixel_read
            visible: root.loupe.pixel_mode
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "transparent"
                border.width: 1
                border.color: Qt.alpha(Theme.blue, 0.5)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------"
                color: Theme.fg_strong
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }

        Text {
            visible: !root.loupe.pixel_mode
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.loupe.has_sel ? Math.round(root.loupe.sel.width) + " x " + Math.round(root.loupe.sel.height) : root.loupe.pad4(root.loupe.screen_x + root.loupe.at.x) + " " + root.loupe.pad4(root.loupe.screen_y + root.loupe.at.y)
            color: Theme.fg_strong
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }
    }
}
