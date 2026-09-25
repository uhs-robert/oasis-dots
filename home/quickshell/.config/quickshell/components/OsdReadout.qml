// home/quickshell/.config/quickshell/components/OsdReadout.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// The OSD as a stat readout: a big number, the device and its change, a meter over a 0-100 scale.
RowLayout {
    id: root

    property real level: 0
    property int percent: 0
    property bool muted: false
    property string label: ""
    property int delta: 0

    spacing: 14

    FontMetrics {
        id: big_metrics
        font.family: Style.number_font
        font.pixelSize: Style.font_size * 3
    }

    Row {
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Text {
            id: big
            width: Math.ceil(big_metrics.advanceWidth("100"))
            horizontalAlignment: Text.AlignRight
            text: root.percent
            color: root.muted ? Style.text_muted : Style.text_strong
            font.family: Style.number_font
            font.pixelSize: Style.font_size * 3
        }

        Text {
            anchors.baseline: big.baseline
            text: "%"
            color: Style.text_muted
            font.family: Style.number_font
            font.pixelSize: Style.fs(1)
        }
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.px(190)
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.label
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.label_spacing
            }

            Text {
                text: root.delta > 0 ? "▲ +" + root.delta : root.delta < 0 ? "▼ " + root.delta : "= 0"
                color: root.delta > 0 ? Theme.ok : root.delta < 0 ? Theme.theme_label : Style.text_muted
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }

        Meter {
            Layout.fillWidth: true
            implicitHeight: 10
            value: root.level
            hot_from: 0.9
            opacity: root.muted ? 0.35 : 1
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: 1
            implicitHeight: scale_row.implicitHeight + 5

            Repeater {
                model: 11

                Rectangle {
                    required property int index
                    x: Math.min(parent.width - 1, index * parent.width / 10)
                    width: 1
                    height: 3
                    color: Style.frame_line.a > 0 ? Style.frame_line : Style.text_muted
                }
            }

            RowLayout {
                id: scale_row
                y: 5
                width: parent.width

                Repeater {
                    model: ["0", "50", "100"]

                    Text {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: index === 0 ? Text.AlignLeft : index === 2 ? Text.AlignRight : Text.AlignHCenter
                        text: modelData
                        color: Style.text_muted
                        font.family: Style.mono_font
                        font.pixelSize: Style.fs(-6)
                    }
                }
            }
        }
    }
}
