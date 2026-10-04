// home/quickshell/.config/quickshell/components/picker/loupe/Materia.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import "../.."
import ".."
import "../../ff7" as Ff7Parts

Item {
    id: root

    required property var loupe
    readonly property real gap: 34
    readonly property real flip_gap: root.loupe.gap
    readonly property bool own_readout: false
    implicitWidth: root.mat_width
    implicitHeight: root.mat_pad_y * 2 + root.mat_header_h + root.loupe.view + root.mat_row_gap + mat_rows_col.implicitHeight

    readonly property real mat_pad_x: 14
    readonly property real mat_pad_y: 10
    readonly property real mat_header_h: 28
    readonly property real mat_row_gap: 4
    readonly property var mat_rows: {
        if (root.loupe.pixel_mode) {
            const rgb = root.loupe.rgb;
            return [
                { label: "R AP", value: String(rgb[0]), ratio: rgb[0] / 255, color: Theme.red, bar: true },
                { label: "G AP", value: String(rgb[1]), ratio: rgb[1] / 255, color: Theme.green, bar: true },
                { label: "B AP", value: String(rgb[2]), ratio: rgb[2] / 255, color: Theme.blue, bar: true }
            ];
        }
        return [
            { label: "Size", value: root.loupe.has_sel ? Math.round(root.loupe.sel.width) + " x " + Math.round(root.loupe.sel.height) : "--", ratio: 0, color: "transparent", bar: false },
            { label: "Pos", value: Math.round(root.loupe.screen_x + root.loupe.at.x) + ", " + Math.round(root.loupe.screen_y + root.loupe.at.y), ratio: 0, color: "transparent", bar: false }
        ];
    }
    readonly property real mat_width: Math.max(222, root.loupe.view + root.mat_pad_x * 2)

    Ff7Parts.Ff7Window {
        anchors.fill: parent
    }

    Item {
        id: mat_header
        x: root.mat_pad_x
        y: root.mat_pad_y
        width: root.mat_width - root.mat_pad_x * 2
        height: 22

        MateriaOrb {
            id: mat_orb
            visible: root.loupe.pixel_mode
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            color: Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : Theme.fg_muted
        }

        Text {
            anchors.left: root.loupe.pixel_mode ? mat_orb.right : parent.left
            anchors.leftMargin: root.loupe.pixel_mode ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.loupe.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") + " Materia" : "Area Materia"
            color: Theme.fg_strong
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    Rectangle {
        x: lens.x - 2
        y: lens.y - 2
        width: lens.width + 4
        height: lens.height + 4
        radius: 4
        color: "transparent"
        border.width: 2
        border.color: Style.frame_border_color
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.mat_pad_x
        y: root.mat_pad_y + root.mat_header_h
        center_color: Theme.fg_strong
    }

    Column {
        id: mat_rows_col
        x: root.mat_pad_x
        y: root.mat_pad_y + root.mat_header_h + root.loupe.view + root.mat_row_gap
        width: root.mat_width - root.mat_pad_x * 2
        spacing: 4

        Repeater {
            model: root.mat_rows

            Column {
                id: mat_row
                required property var modelData
                width: mat_rows_col.width
                spacing: 2

                Item {
                    width: parent.width
                    height: 14

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: mat_row.modelData.label
                        color: Theme.theme_primary_light
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: mat_row.modelData.value
                        color: Theme.fg_strong
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(-6)
                    }
                }

                Rectangle {
                    visible: mat_row.modelData.bar
                    width: parent.width
                    height: 5
                    color: Theme.bg_shadow
                    border.width: 1
                    border.color: Theme.fg_muted

                    Rectangle {
                        x: 1
                        y: 1
                        width: Math.max(0, (parent.width - 2) * Math.max(0, Math.min(1, mat_row.modelData.ratio)))
                        height: parent.height - 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: mat_row.modelData.color }
                            GradientStop { position: 1; color: Theme.fg_strong }
                        }
                    }
                }
            }
        }

        Item {
            width: mat_rows_col.width
            height: 14

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Lv"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: String(Screenshot.zoom_index + 1)
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }
        }
    }
}
