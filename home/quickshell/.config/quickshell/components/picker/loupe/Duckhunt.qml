// home/quickshell/.config/quickshell/components/picker/loupe/Duckhunt.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."

Item {
    id: root

    required property var loupe
    readonly property real gap: 34
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.dh_width
    implicitHeight: root.dh_lens_size + root.dh_gap + root.dh_hud_h + root.dh_gap + root.dh_score_h

    readonly property real dh_pad: 6
    readonly property real dh_gap: 6
    readonly property real dh_hud_h: 40
    readonly property real dh_score_h: 40
    readonly property real dh_lens_size: root.loupe.view + root.dh_pad * 2
    readonly property real dh_lens_x: (root.dh_width - root.dh_lens_size) / 2
    readonly property real dh_width: Math.max(300, root.loupe.view + root.dh_pad * 2)

    Rectangle {
        x: root.dh_lens_x
        y: 0
        width: root.dh_lens_size
        height: root.dh_lens_size
        radius: 6
        color: Theme.bg_shadow
        border.width: 3
        border.color: Theme.green
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.dh_lens_x + root.dh_pad
        y: root.dh_pad
        center_color: Theme.fg_strong
    }

    Rectangle {
        x: lens.x
        y: lens.y + lens.height - 16
        width: lens.width
        height: 16
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Theme.green, 0.35)
            }
        }
    }

    Item {
        id: dh_hud_row
        x: 0
        y: root.dh_lens_size + root.dh_gap
        width: root.dh_width
        height: root.dh_hud_h

        Rectangle {
            id: dh_zoom_box
            x: 0
            y: 0
            height: parent.height
            width: dh_zoom_row.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Row {
                id: dh_zoom_row
                anchors.centerIn: parent

                Text {
                    text: "R="
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Text {
                    text: String(root.loupe.zoom)
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: dh_shot_box
            x: dh_zoom_box.x + dh_zoom_box.width + 8
            y: 0
            height: parent.height
            width: dh_shot_col.implicitWidth + 16
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green

            Column {
                id: dh_shot_col
                anchors.centerIn: parent
                spacing: 2

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 3

                    Repeater {
                        model: 3

                        Rectangle {
                            width: 5
                            height: 11
                            topLeftRadius: 2
                            topRightRadius: 2
                            color: Theme.bright_yellow
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SHOT"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }
        }

        Rectangle {
            id: dh_hit_box
            x: dh_shot_box.x + dh_shot_box.width + 8
            y: 0
            width: Math.max(0, parent.width - dh_hit_box.x)
            height: parent.height
            radius: 6
            color: Theme.bg_shadow
            border.width: 3
            border.color: Theme.green
            clip: true

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "HIT"
                    color: Theme.bright_green
                    font.family: Style.font_family
                    font.pixelSize: 10
                }

                Repeater {
                    model: dh_hud_row.visible ? 10 : 0

                    DuckIcon {
                        id: hit_duck
                        required property int index
                        fill: Screenshot.recent_picks[hit_duck.index] ? Screenshot.recent_picks[hit_duck.index] : Theme.fg_muted
                    }
                }
            }
        }
    }

    Rectangle {
        id: dh_score_box
        y: root.dh_lens_size + root.dh_gap * 2 + root.dh_hud_h
        x: root.dh_width - dh_score_box.width
        width: dh_score_col.implicitWidth + 16
        height: root.dh_score_h
        radius: 6
        color: Theme.bg_shadow
        border.width: 3
        border.color: Theme.green

        Column {
            id: dh_score_col
            anchors.centerIn: parent
            spacing: 2

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.loupe.pixel_mode
                spacing: 4

                Rectangle {
                    width: 10
                    height: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : Theme.bg_shadow
                    border.width: 1
                    border.color: Theme.fg_strong
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex.substring(1) : "------"
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: 10
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.loupe.pixel_mode
                text: root.loupe.has_sel ? Math.round(root.loupe.sel.width) + "x" + Math.round(root.loupe.sel.height) : String(Math.round(root.loupe.screen_x + root.loupe.at.x)).padStart(4, "0") + String(Math.round(root.loupe.screen_y + root.loupe.at.y)).padStart(4, "0")
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: 10
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SCORE"
                color: Theme.bright_green
                font.family: Style.font_family
                font.pixelSize: 10
            }
        }
    }
}
