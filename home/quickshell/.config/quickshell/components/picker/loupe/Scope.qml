// home/quickshell/.config/quickshell/components/picker/loupe/Scope.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 36
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: true
    implicitWidth: root.loupe.view + root.loupe.pad * 2
    implicitHeight: root.loupe.view + root.loupe.pad * 2 + root.header_h + root.foot_h

    readonly property real header_h: 20
    readonly property real foot_h: 22

    Rectangle {
        anchors.fill: parent
        radius: 0
        color: Qt.alpha(Style.frame_color, 0.82)
        border.width: 1
        border.color: Qt.alpha(Style.picker_hud, 0.7)
    }

    Text {
        id: zoomhead
        anchors.top: parent.top
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        text: "- ZOOM LEVEL - -  " + root.loupe.zoom * 100 + " -"
        color: Style.picker_hud
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.loupe.pad
        y: root.loupe.pad + root.header_h
        center_color: Style.picker_hud

        Repeater {
            model: Math.ceil(root.loupe.view / 3)

            Rectangle {
                required property int index
                y: index * 3
                width: root.loupe.view
                height: 1
                color: Qt.rgba(0, 0, 0, 0.18)
            }
        }

        Repeater {
            model: Math.floor(root.loupe.view / 11) + 1

            Rectangle {
                required property int index
                x: root.loupe.view - 3
                y: index * 11
                width: 3
                height: 1
                color: Qt.alpha(Style.picker_hud, 0.7)
            }
        }

        Rectangle {
            x: 0
            y: lens.center_px.y + lens.center_px.height / 2
            width: Math.max(0, lens.center_px.x)
            height: 1
            color: Qt.alpha(Style.picker_hud, 0.45)
        }

        Rectangle {
            x: lens.center_px.x + lens.center_px.width
            y: lens.center_px.y + lens.center_px.height / 2
            width: Math.max(0, root.loupe.view - x)
            height: 1
            color: Qt.alpha(Style.picker_hud, 0.45)
        }

        Rectangle {
            x: lens.center_px.x + lens.center_px.width / 2
            y: 0
            width: 1
            height: Math.max(0, lens.center_px.y)
            color: Qt.alpha(Style.picker_hud, 0.45)
        }

        Rectangle {
            x: lens.center_px.x + lens.center_px.width / 2
            y: lens.center_px.y + lens.center_px.height
            width: 1
            height: Math.max(0, root.loupe.view - y)
            color: Qt.alpha(Style.picker_hud, 0.45)
        }
    }

    LoupeReadout {
        id: swatch_row
        loupe: root.loupe
        anchors.right: scope_foot.right
        anchors.verticalCenter: scope_foot.verticalCenter
        hex_color: Style.picker_hud

        Text {
            id: scope_read
            visible: !root.loupe.pixel_mode
            anchors.verticalCenter: parent.verticalCenter
            text: "X" + Math.round(root.loupe.screen_x + root.loupe.at.x) + " Y" + Math.round(root.loupe.screen_y + root.loupe.at.y)
            color: Style.picker_hud
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-3)
        }
    }

    Item {
        id: scope_foot
        x: root.loupe.pad
        y: root.loupe.pad + root.header_h + root.loupe.view + (root.foot_h - foot_left.height) / 2
        width: root.loupe.view
        height: foot_left.height

        Row {
            id: foot_left
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Item {
                width: 26
                height: 14
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    x: 1
                    y: 2
                    width: 10
                    height: 10
                    radius: 5
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.red
                }

                Rectangle {
                    x: 15
                    y: 2
                    width: 10
                    height: 10
                    radius: 5
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.red
                }

                Rectangle {
                    x: 10
                    y: 5
                    width: 6
                    height: 3
                    color: Theme.red
                }
            }

            Text {
                id: scope_label
                visible: 26 + foot_left.spacing + scope_label.implicitWidth + 8 + swatch_row.width <= scope_foot.width
                anchors.verticalCenter: parent.verticalCenter
                text: root.loupe.pixel_mode ? "SCOPE" : "CAMERA"
                color: Style.text_fg
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }
        }
    }
}
