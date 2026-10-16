pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../../services"

// The plain current conditions: icon, temperature and condition, then today's range, humidity and rain as thin bars over a row of readouts.
ColumnLayout {
    id: root

    // Children size from the popup column's width, not this layout's own: reading root.width while this layout arranges them makes it rearrange again.
    readonly property real header_w: parent ? parent.width : 0
    readonly property bool roomy: root.header_w >= 340
    readonly property var temp_vital: WeatherState.vital("temp")
    readonly property var hum_vital: WeatherState.vital("hum")
    readonly property var rain_vital: WeatherState.vital("rain")
    readonly property var readouts: WeatherState.vitals.filter(v => ["feels", "wind", "uv", "aqi"].includes(v.key))

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    component GaugeLabel: Text {
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.letterSpacing: 1
    }

    component GaugeValue: Text {
        color: Style.text_muted
        font.family: Style.number_font
        font.pixelSize: Style.fs(-3)
    }

    // Sized from the widest text each column holds, so the bars start and end in line.
    TextMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.letterSpacing: 1
        text: "TEMP"
    }

    TextMetrics {
        id: value_metrics
        font.family: Style.number_font
        font.pixelSize: Style.fs(-3)
        text: "100%"
    }

    // A thin bar for one vital; TEMP adds today's low before it and a marker where now sits.
    component BarRow: RowLayout {
        id: bar_row
        property var vital: null
        property string low: ""
        property string value_text: bar_row.vital ? bar_row.vital.value + bar_row.vital.unit : ""
        property color shade_color: bar_row.vital ? Qt.alpha(bar_row.vital.color, 0.5) : Style.text_dim
        property bool marked: false

        Layout.fillWidth: true
        spacing: 8

        GaugeLabel {
            Layout.preferredWidth: label_metrics.advanceWidth + 2
            text: bar_row.vital ? bar_row.vital.label : ""
        }

        GaugeValue {
            Layout.preferredWidth: value_metrics.advanceWidth
            horizontalAlignment: Text.AlignRight
            text: bar_row.low
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.px(6)

            AtbBar {
                anchors.fill: parent
                value: bar_row.vital ? bar_row.vital.fill : 0
                fill_color: bar_row.vital ? bar_row.vital.color : Style.text_dim
                shade_color: bar_row.shade_color
                horizontal: true
            }

            Rectangle {
                visible: bar_row.marked
                x: Math.round(parent.width * (bar_row.vital ? bar_row.vital.fill : 0) - width / 2)
                y: -3
                width: 2
                height: parent.height + 6
                radius: 1
                color: Style.text_strong
            }
        }

        GaugeValue {
            Layout.preferredWidth: value_metrics.advanceWidth
            text: bar_row.value_text
        }
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        Image {
            Layout.preferredWidth: Math.min(72, Math.max(40, root.header_w / 5))
            Layout.preferredHeight: Layout.preferredWidth
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            source: WeatherState.has_data ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
            visible: WeatherState.has_data
            sourceSize.width: Math.ceil(144 * dpr)
            sourceSize.height: Math.ceil(144 * dpr)
            smooth: true
        }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true

            Text {
                text: WeatherState.has_data ? root.fmt_temp(WeatherState.current.temp) : WeatherState.failed ? "n/a" : "--°"
                color: WeatherState.has_data ? WeatherState.temp_color(WeatherState.current.temp) : Style.text_dim
                font.family: Style.number_font
                font.pixelSize: Style.fs(12)
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: WeatherState.cond_text(true)
                color: WeatherState.has_data || WeatherState.loading ? Style.pal.fg : Style.pal.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(1)
            }

            // FEELS moves into the readouts once today's vitals arrive.
            Text {
                visible: WeatherState.has_data && !WeatherState.has_vitals
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "Feels like " + (WeatherState.has_data ? root.fmt_temp(WeatherState.current.feels) : "")
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }

            Text {
                visible: WeatherState.location_name !== ""
                elide: Text.ElideRight
                Layout.fillWidth: true
                text: WeatherState.location_name
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
            }
        }

        Text {
            visible: WeatherState.stale
            Layout.alignment: Qt.AlignTop
            Layout.maximumWidth: root.header_w / 3
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            text: WeatherState.stale_text()
            color: Style.pal.warning
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }
    }

    ColumnLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        spacing: 6

        BarRow {
            vital: root.temp_vital
            low: WeatherState.has_vitals ? Math.round(WeatherState.today_low) + "°" : ""
            value_text: WeatherState.has_vitals ? Math.round(WeatherState.today_high) + "°" : ""
            shade_color: WeatherState.has_vitals ? WeatherState.temp_color(WeatherState.today_low) : Style.text_dim
            marked: true
        }

        BarRow {
            vital: root.hum_vital
        }

        BarRow {
            vital: root.rain_vital
        }
    }

    GridLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        columns: root.roomy ? 4 : 2
        columnSpacing: 10
        rowSpacing: 6

        Repeater {
            model: root.readouts

            ColumnLayout {
                id: readout
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                spacing: 1

                GaugeLabel { text: readout.modelData.label }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: readout.modelData.value + (readout.modelData.unit !== "" ? " " + readout.modelData.unit : "")
                    color: readout.modelData.color
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                // The band gets its own line: beside the value, "Moderate" no longer fits a quarter of 440px.
                Text {
                    visible: readout.modelData.detail !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: readout.modelData.detail
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                }
            }
        }
    }
}
