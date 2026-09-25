// home/quickshell/.config/quickshell/popups/weather/WeatherSpec.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../../services"

// Current conditions as a spec sheet: icon, stencil temperature and condition beside stat bars, then the location.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool roomy: root.width >= 330
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Item {
            visible: root.roomy
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            Layout.alignment: Qt.AlignVCenter

            CutBox {
                anchors.fill: parent
                cut_tl: 6
                cut_br: 6
                fill: Style.row_rule
                stroke: Style.frame_line
            }

            Image {
                anchors.centerIn: parent
                width: 32
                height: 32
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                sourceSize.width: Math.ceil(64 * dpr)
                sourceSize.height: Math.ceil(64 * dpr)
                smooth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Row {
                spacing: 3

                Text {
                    id: temp_text
                    text: root.has ? Math.round(root.cur.temp) : "--"
                    color: root.has ? Style.text_strong : Style.text_dim
                    font.family: Style.number_font
                    font.pixelSize: Style.font_size * 2 + 10
                }

                Text {
                    y: temp_text.height * 0.12
                    text: "°" + WeatherState.unit_symbol()
                    color: Style.text_muted
                    font.family: Style.mono_font
                    font.pixelSize: Style.fs(-1)
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "Unavailable"
                color: root.has || WeatherState.loading ? Style.text_primary : Theme.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.label_spacing
            }

            Text {
                visible: root.has
                text: "FEELS " + (root.has ? Math.round(root.cur.feels) + "°" + WeatherState.unit_symbol() : "")
                color: Style.text_muted
                font.family: Style.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }

        Item {
            visible: root.has
            Layout.preferredWidth: Math.min(172, root.width * 0.46)
            Layout.preferredHeight: spec.implicitHeight
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                width: 1
                height: parent.height
                color: Style.frame_line
            }

            ColumnLayout {
                id: spec
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                spacing: 4

                StatRow {
                    Layout.fillWidth: true
                    label: "Humid"
                    value: root.has ? root.cur.humidity : ""
                    unit: "%"
                    fraction: root.has ? root.cur.humidity / 100 : 0
                }

                StatRow {
                    Layout.fillWidth: true
                    label: "Wind"
                    value: root.has ? Math.round(root.cur.wind_speed) : ""
                    unit: root.has ? WeatherState.wind_unit().toUpperCase() + " " + WeatherState.wind_dir_label(root.cur.wind_dir) : ""
                    fraction: root.has ? root.cur.wind_speed / 40 : 0
                }

                StatRow {
                    Layout.fillWidth: true
                    label: "UV"
                    value: root.has ? root.cur.uv_index.toFixed(1) : ""
                    unit: "IDX"
                    fraction: root.has ? root.cur.uv_index / 11 : 0
                }

                StatRow {
                    visible: root.aqi >= 0
                    Layout.fillWidth: true
                    label: "AQI"
                    value: root.aqi
                    unit: root.aqi >= 0 ? WeatherState.aqi_band(root.aqi).label.split(" ")[0].toUpperCase() : ""
                    fraction: root.aqi / 150
                }
            }
        }
    }

    RowLayout {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: "LOC"
            color: Style.text_muted
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: WeatherState.location_name
            color: Style.text_fg
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }

        Text {
            visible: root.roomy
            text: Math.abs(WeatherState.lat).toFixed(2) + (WeatherState.lat >= 0 ? "N " : "S ") + Math.abs(WeatherState.lon).toFixed(2) + (WeatherState.lon >= 0 ? "E" : "W")
            color: Style.text_muted
            font.family: Style.mono_font
            font.pixelSize: Style.fs(-4)
        }
    }

    Text {
        visible: WeatherState.stale
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: "STALE DATA" + (WeatherState.error ? ": " + WeatherState.error : "")
        color: Theme.warning
        font.family: Style.mono_font
        font.pixelSize: Style.fs(-4)
    }
}
