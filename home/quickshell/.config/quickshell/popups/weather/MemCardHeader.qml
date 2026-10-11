// home/quickshell/.config/quickshell/popups/weather/MemCardHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"

// The PS1 memory card screen: a location strip over the current conditions as the selected save's info panel.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int aqi: WeatherState.aqi_now
    // Each readout is [label, value, band, band colour]; AQI drops out when there is no reading.
    readonly property var readouts: !root.has ? [] : [
        ["WIND", Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit().toUpperCase() + " " + WeatherState.compass_label(root.cur.wind_dir), "", Style.text_fg],
        ["UV", root.cur.uv_index.toFixed(1), WeatherState.uv_band(root.cur.uv_index).label.toUpperCase(), WeatherState.uv_color(root.cur.uv_index)]
    ].concat(root.aqi >= 0 ? [["AQI", String(root.aqi), WeatherState.aqi_band(root.aqi).label.toUpperCase(), WeatherState.aqi_color(root.aqi)]] : [])

    component GaugeLabel: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
    }

    component GaugeValue: Text {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        color: Style.text_fg
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
    }

    spacing: 6

    Rectangle {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: strip_text.implicitHeight + 6
        radius: 4
        color: "transparent"
        clip: true

        FadeFill {
            radius: parent.radius
            fill: Style.title_bg
        }

        Text {
            id: strip_text
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: WeatherState.location_name.toUpperCase()
            color: Style.title_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
            style: Text.Raised
            styleColor: Style.text_shadow
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: info.implicitHeight + 16
        radius: 6
        color: Qt.alpha(Theme.bg_shadow, 0.35)
        border.width: 2
        border.color: Style.frame_border_color

        RowLayout {
            id: info
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 10

            SaveIcon {
                Layout.alignment: Qt.AlignTop
                size: 44
                code: root.has ? root.cur.code : -1
                is_day: root.has ? root.cur.is_day : true
                lit: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.has ? Math.round(root.cur.temp) + "°" + WeatherState.unit_symbol() : WeatherState.failed ? "n/a" : "--°"
                        color: root.has ? Style.text_strong : Style.text_dim
                        font.family: Style.font_family
                        font.pixelSize: Style.fs(12)
                        style: Text.Raised
                        styleColor: Style.text_shadow
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.has ? root.cur.cond.toUpperCase() : WeatherState.loading ? "LOADING" : "NO DATA"
                            color: root.has || WeatherState.loading ? Theme.theme_primary_light : Theme.warning
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-3)
                        }

                        Text {
                            visible: root.has
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "FEELS " + (root.has ? Math.round(root.cur.feels) + "°" : "")
                            color: Style.text_muted
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-5)
                        }
                    }
                }

                Flow {
                    visible: root.has
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.readouts

                        Row {
                            id: readout
                            required property var modelData
                            spacing: 4

                            Text {
                                text: readout.modelData[0]
                                color: Theme.theme_primary_light
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }

                            Text {
                                text: readout.modelData[1]
                                color: Style.text_fg
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }

                            Text {
                                visible: readout.modelData[2] !== ""
                                text: readout.modelData[2]
                                color: readout.modelData[3]
                                font.family: Style.font_family
                                font.pixelSize: Style.fs(-5)
                            }
                        }
                    }
                }

                GridLayout {
                    visible: WeatherState.has_vitals
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    columns: 4
                    columnSpacing: 6
                    rowSpacing: 4

                    GaugeLabel {
                        text: "TEMP"
                    }

                    GaugeValue {
                        text: Math.round(WeatherState.today_low) + "°"
                        color: WeatherState.temp_color(WeatherState.today_low)
                    }

                    BlockGauge {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        value: WeatherState.temp_range_pos
                        fill_color: WeatherState.has_vitals ? WeatherState.temp_color(root.cur.temp) : Theme.theme_primary_light
                        mark_last: true
                    }

                    GaugeValue {
                        text: Math.round(WeatherState.today_high) + "°"
                        color: WeatherState.temp_color(WeatherState.today_high)
                    }

                    GaugeLabel {
                        text: "HUM"
                    }

                    // Only TEMP has a low end; the empty cell keeps every gauge starting at the same x.
                    Item {}

                    BlockGauge {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        value: root.has ? root.cur.humidity / 100 : 0
                        fill_color: Theme.theme_primary_light
                    }

                    GaugeValue {
                        text: root.has ? root.cur.humidity + "%" : ""
                    }

                    GaugeLabel {
                        text: "RAIN"
                    }

                    Item {}

                    BlockGauge {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        value: WeatherState.today_pop / 100
                        fill_color: Theme.info
                    }

                    GaugeValue {
                        text: WeatherState.today_pop + "%"
                    }
                }

                Text {
                    visible: WeatherState.stale || WeatherState.failed
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (WeatherState.failed ? "NO DATA" : "STALE DATA") + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }
        }
    }
}
