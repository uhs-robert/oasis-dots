// home/quickshell/.config/quickshell/components/picker/loupe/Jrpg.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../../theme"
import "../../../services"
import ".."
import "../../snes" as SnesParts

Item {
    id: root

    required property var loupe
    readonly property real gap: 36
    readonly property real flip_gap: Math.max(66, root.loupe.min_gap)
    readonly property bool own_readout: false
    implicitWidth: root.loupe.view + root.loupe.pad * 2 + root.jrpg_drop
    implicitHeight: root.loupe.pad + root.header_h + root.loupe.view + root.jrpg_gap + root.jrpg_stats_h + root.loupe.pad + root.jrpg_drop

    readonly property real jrpg_name_h: 16
    readonly property real jrpg_gap: 6
    readonly property real jrpg_drop: 3
    readonly property var jrpg_rows: {
        if (root.loupe.pixel_mode) {
            const rgb = root.loupe.rgb;
            return [
                { label: "R", value: rgb[0], ratio: rgb[0] / 255, color: Theme.red },
                { label: "G", value: rgb[1], ratio: rgb[1] / 255, color: Theme.green },
                { label: "B", value: rgb[2], ratio: rgb[2] / 255, color: Theme.blue }
            ];
        }
        const rows = [
            { label: "X", value: Math.round(root.loupe.screen_x + root.loupe.at.x), ratio: root.loupe.at.x / root.loupe.area_width, color: Theme.theme_primary_light },
            { label: "Y", value: Math.round(root.loupe.screen_y + root.loupe.at.y), ratio: root.loupe.at.y / root.loupe.area_height, color: Theme.theme_primary_light }
        ];
        if (root.loupe.has_sel) {
            rows.push({ label: "W", value: Math.round(root.loupe.sel.width), ratio: root.loupe.sel.width / root.loupe.area_width, color: Theme.theme_secondary });
            rows.push({ label: "H", value: Math.round(root.loupe.sel.height), ratio: root.loupe.sel.height / root.loupe.area_height, color: Theme.theme_secondary });
        }
        return rows;
    }
    readonly property real jrpg_stats_h: root.jrpg_rows.length > 0 ? root.jrpg_rows.length * 14 + (root.jrpg_rows.length - 1) * 3 : 0
    readonly property real header_h: root.jrpg_name_h + root.jrpg_gap

    SnesParts.SnesWindow {
        anchors.fill: parent
    }

    Text {
        id: jrpg_name_left
        x: root.loupe.pad
        y: root.loupe.pad
        text: root.loupe.pixel_mode ? (Screenshot.pixel_hex !== "" ? Screenshot.pixel_hex : "#------") : "TARGET"
        color: Theme.fg_strong
        style: Text.Raised
        styleColor: Style.text_shadow
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
    }

    Text {
        id: jrpg_name_right
        x: root.loupe.pad + root.loupe.view - jrpg_name_right.implicitWidth
        y: root.loupe.pad
        text: "Lv " + root.loupe.zoom
        color: Theme.theme_secondary
        style: Text.Raised
        styleColor: Style.text_shadow
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
    }

    LoupeLens {
        id: lens
        loupe: root.loupe
        x: root.loupe.pad
        y: root.loupe.pad + root.header_h
        center_color: jrpg_blink.alt ? Theme.theme_secondary : Theme.fg_strong
    }

    Rectangle {
        x: lens.x
        y: lens.y
        width: lens.width
        height: lens.height
        color: "transparent"
        border.width: 2
        border.color: Theme.theme_primary_light
    }

    Timer {
        id: jrpg_blink
        property bool alt: false
        running: root.loupe.visible
        interval: 400
        repeat: true
        onTriggered: jrpg_blink.alt = !jrpg_blink.alt
    }

    Column {
        id: jrpg_stats
        x: root.loupe.pad
        y: root.loupe.pad + root.header_h + root.loupe.view + root.jrpg_gap
        width: root.loupe.view
        spacing: 3

        Repeater {
            model: root.jrpg_rows

            Item {
                id: stat_row
                required property var modelData
                width: jrpg_stats.width
                height: 14

                Text {
                    id: stat_label
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    text: stat_row.modelData.label
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-7)
                }

                Text {
                    id: stat_value
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    horizontalAlignment: Text.AlignRight
                    text: String(stat_row.modelData.value)
                    color: Theme.fg_strong
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-7)
                }

                Rectangle {
                    anchors.left: stat_label.right
                    anchors.leftMargin: 4
                    anchors.right: stat_value.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    color: Theme.bg_shadow
                    border.width: 1
                    border.color: Theme.fg_muted

                    Rectangle {
                        x: 1
                        y: 1
                        width: Math.max(0, (parent.width - 2) * Math.max(0, Math.min(1, stat_row.modelData.ratio)))
                        height: parent.height - 2
                        color: stat_row.modelData.color
                    }
                }
            }
        }
    }
}
