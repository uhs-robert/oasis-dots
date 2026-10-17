import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.ui.gauges
import qs.theme
import qs.services

// WeatherStar 4000 "Current Conditions": a yellow title over a bevelled blue panel of readings.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool roomy: root.width >= 330
    readonly property int row_px: Style.fs(-4)
    readonly property bool show_vitals: root.has && WeatherState.has_vitals
    // Humidity moves to its gauge below once there are vitals to draw.
    readonly property var rows: !root.has ? [] : (root.show_vitals ? [] : [["Humidity:", root.cur.humidity + "%"]]).concat([
        ["Dewpoint:", Math.round(root.cur.dew_point) + "°"],
        ["Feels Like:", Math.round(root.cur.feels) + "°"],
        ["Wind:", WeatherState.wind_dir_label(root.cur.wind_dir) + " " + Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit()]
    ], root.roomy ? [["Pressure:", WeatherState.pressure_display(root.cur.pressure)]] : [], root.show_vitals ? [["UV Index:", Math.round(root.cur.uv_index) + " " + WeatherState.vital("uv").detail]] : [], root.show_vitals && WeatherState.aqi_now >= 0 ? [["Air Quality:", WeatherState.aqi_now + " " + root.short_band(WeatherState.vital("aqi").detail)]] : [])

    // The one AQI band too long for the readings column, cut down the way the channel abbreviated.
    function short_band(label) {
        return label === "Unhealthy for Sensitive Groups" ? "Unhlthy-Sens" : label;
    }

    function lo_hi(word, color, temp) {
        return "<font color=\"" + color + "\">" + word + "</font> " + Math.round(temp);
    }

    component Gauge: RowLayout {
        id: gauge

        property string label: ""
        property string lead: ""
        property string tail: ""
        property real fill: 0
        // Lights up to the segment nearest `fill` and draws that one brighter, for a position rather than an amount.
        property bool marks_now: false

        Layout.fillWidth: true
        spacing: 6

        Text {
            Layout.preferredWidth: gauge_metrics.advanceWidth(root.roomy ? "Chance of Rain:" : "Humidity:")
            text: gauge.label
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: root.row_px
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Text {
            Layout.preferredWidth: gauge_metrics.advanceWidth("Lo -10")
            horizontalAlignment: Text.AlignRight
            textFormat: Text.StyledText
            text: gauge.lead
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: root.row_px
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        SegBar {
            id: segs
            Layout.fillWidth: true
            Layout.preferredHeight: 9
            count: Math.max(6, Math.min(20, Math.round(segs.width / 11)))
            last_lit: gauge.marks_now ? Math.round(gauge.fill * (segs.count - 1)) : Math.round(gauge.fill * segs.count) - 1
            on_color: Theme.theme_secondary
            off_color: Qt.alpha(Theme.bg_shadow, 0.55)

            SegBar {
                visible: gauge.marks_now
                anchors.fill: parent
                count: segs.count
                gap: segs.gap
                first_lit: segs.last_lit
                last_lit: segs.last_lit
                on_color: Theme.fg_strong
            }
        }

        Text {
            Layout.preferredWidth: gauge_metrics.advanceWidth("Hi 100")
            textFormat: Text.StyledText
            text: gauge.tail
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: root.row_px
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }
    }

    spacing: 4

    Text {
        text: "Current Conditions"
        color: Theme.theme_secondary
        font.family: Style.font_family
        font.pixelSize: Style.fs(-1)
        style: Text.Outline
        styleColor: Theme.bg_shadow
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: panel_content.implicitHeight + 16

        WsPanel {
            anchors.fill: parent
        }

        FontMetrics {
            id: gauge_metrics
            font.family: Style.font_family
            font.pixelSize: root.row_px
        }

        ColumnLayout {
            id: panel_content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 8

            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: root.roomy ? 2 : 1
                columnSpacing: 14
                rowSpacing: 2

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.fillWidth: !root.roomy
                    spacing: 0

                    RowLayout {
                        spacing: 8

                        Text {
                            text: root.has ? Math.round(root.cur.temp) + "°" : "--"
                            color: root.has ? Theme.fg_strong : Style.text_dim
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size * 2
                            style: Text.Outline
                            styleColor: Theme.bg_shadow
                        }

                        Image {
                            visible: root.has
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                            sourceSize.width: Math.ceil(88 * dpr)
                            sourceSize.height: Math.ceil(88 * dpr)
                            source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                            smooth: true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.maximumWidth: root.roomy ? Math.max(120, root.width * 0.42) : -1
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.has ? root.cur.cond : WeatherState.loading ? "Loading..." : "No Report Available"
                        color: root.has || WeatherState.loading ? Theme.fg_strong : Theme.warning
                        font.family: Style.font_family
                        font.pixelSize: root.row_px
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    spacing: 0

                    Text {
                        visible: WeatherState.location_name !== ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: WeatherState.location_name.split(",")[0]
                        color: Theme.theme_secondary
                        font.family: Style.font_family
                        font.pixelSize: root.row_px
                        style: Text.Outline
                        styleColor: Theme.bg_shadow
                    }

                    Repeater {
                        model: root.rows

                        RowLayout {
                            id: reading
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: reading.modelData[0]
                                color: Theme.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: root.row_px
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }

                            Text {
                                text: reading.modelData[1]
                                color: Theme.fg_strong
                                font.family: Style.font_family
                                font.pixelSize: root.row_px
                                style: Text.Outline
                                styleColor: Theme.bg_shadow
                            }
                        }
                    }

                    Text {
                        visible: WeatherState.stale || (!root.has && !WeatherState.loading && WeatherState.error !== "")
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (WeatherState.stale ? "Stale Data" : "Error") + (WeatherState.error ? ": " + WeatherState.error : "")
                        color: Theme.warning
                        font.family: Style.font_family
                        font.pixelSize: root.row_px - 2
                    }
                }
            }

            ColumnLayout {
                visible: root.show_vitals
                Layout.fillWidth: true
                spacing: 3

                Gauge {
                    label: "Today:"
                    lead: root.show_vitals ? root.lo_hi("Lo", Theme.theme_primary_light, WeatherState.today_low) : ""
                    tail: root.show_vitals ? root.lo_hi("Hi", Theme.theme_secondary, WeatherState.today_high) : ""
                    fill: WeatherState.temp_range_pos
                    marks_now: true
                }

                Gauge {
                    label: "Humidity:"
                    tail: root.show_vitals ? root.cur.humidity + "%" : ""
                    fill: root.show_vitals ? root.cur.humidity / 100 : 0
                }

                Gauge {
                    label: root.roomy ? "Chance of Rain:" : "Rain:"
                    tail: WeatherState.today_pop + "%"
                    fill: WeatherState.today_pop / 100
                }
            }
        }
    }
}
