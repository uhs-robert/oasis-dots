// home/quickshell/.config/quickshell/components/modern/TileOsd.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import ".." as Shared

// The OSD as a card: an accent tile, the level's name and device, a large readout and the level as a capsule or 20-segment meter.
ColumnLayout {
    id: root

    property string kind: "volume"
    property real level: 0
    property int percent: 0
    property bool muted: false
    property string glyph: ""
    property string device: ""
    // The default sink's live wave in the volume capsule; off unless peaks_on.
    property var node: null
    property bool peaks_on: false

    spacing: Style.px(14)
    implicitWidth: Style.px(300)

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        AccentTile {
            glyph: root.glyph
            dimmed: root.muted
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1

            Text {
                text: root.kind === "brightness" ? "Brightness" : root.muted ? "Muted" : "Volume"
                color: Style.text_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.device !== ""
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.device
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }

        Row {
            Layout.alignment: Qt.AlignVCenter

            TextMetrics {
                id: readout_metrics
                font: readout.font
                text: "100"
            }

            Text {
                id: readout
                width: Math.ceil(readout_metrics.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: root.percent
                color: root.muted ? Style.text_muted : Style.text_strong
                font.family: Style.number_font
                font.pixelSize: Style.fs(20)
                font.weight: Font.Medium
                font.letterSpacing: -1.5
                font.features: { "tnum": 1 }
            }

            Text {
                y: Math.round(readout.height * 0.14)
                leftPadding: 1
                text: "%"
                color: Style.text_dim
                font.family: Style.number_font
                font.pixelSize: Math.round(readout.font.pixelSize * 0.45)
                font.weight: Font.Medium
            }
        }
    }

    CapsuleSlider {
        visible: Style.level_layout === "capsule"
        Layout.fillWidth: true
        implicitHeight: Style.px(26)
        value: root.level
        muted: root.muted
        interactive: false
        show_readout: false
        glow: root.kind !== "volume"
        node: root.node
        peaks_on: root.peaks_on && root.kind === "volume"
    }

    Shared.Meter {
        visible: Style.level_layout !== "capsule"
        Layout.fillWidth: true
        art_key: root.kind === "volume" ? "volume" : "osd"
        value: root.level
        hot_from: 0.9
        opacity: root.muted ? 0.35 : 1
    }
}
