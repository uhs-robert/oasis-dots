// home/quickshell/.config/quickshell/components/snes/SnesOsd.qml
import QtQuick
import "../../theme"

// The OSD as an FF6 readout: a big raised number over an ATB gauge.
Row {
    id: root

    property real level: 0
    property int percent: 0
    property bool muted: false

    spacing: 12

    FontMetrics {
        id: big_metrics
        font.family: Style.number_font
        font.pixelSize: Style.font_size * 2
    }

    Text {
        id: big
        anchors.verticalCenter: parent.verticalCenter
        width: Math.ceil(big_metrics.advanceWidth("100"))
        horizontalAlignment: Text.AlignRight
        text: root.percent
        color: root.muted ? Style.text_muted : Theme.fg_strong
        style: Text.Raised
        styleColor: Style.text_shadow
        font.family: Style.number_font
        font.pixelSize: Style.font_size * 2
    }

    SnesGauge {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.px(170)
        implicitHeight: 11
        value: root.level
        hot_from: 0.9
        dim: root.muted
    }
}
