import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.ui.frames
import qs.ui.gauges
import qs.theme
import qs.features.weather

// A Scan Visor logbook entry: the condition locked in scan brackets beside the reading and a generated analysis line,
// then the vitals as energy readouts: TEMP as an energy bar across today's low to high, HUM and RAIN as energy tanks.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool threat: WeatherState.alerts.length > 0
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property color lock_color: root.threat ? Theme.theme_label : Theme.theme_primary
    readonly property var phrases: ({ partly_cloudy: "broken cloud layer", overcast: "overcast cloud layer", fog: "dense fog bank", drizzle: "light drizzle", rain: "active rainfall", heavy_rain: "heavy rainfall", freezing_rain: "freezing precipitation", snow: "snowfall", heavy_snow: "heavy snowfall", thunderstorm: "electrical storm activity" })

    readonly property string log_line: {
        if (!root.has) return WeatherState.loading ? "Acquiring atmospheric data." : "No atmospheric data" + (WeatherState.error ? ": " + WeatherState.error : "") + ".";
        const key = WeatherState.weather_color_keys[Math.round(root.cur.code)] || "";
        const phrase = root.phrases[key] || (key === "clear" ? (root.cur.is_day ? "clear sky, no cloud layer" : "clear night sky") : root.cur.cond.toLowerCase());
        // The vitals below already read out humidity, wind and air quality.
        if (WeatherState.has_vitals) return "Atmospheric analysis: " + phrase + ".";
        const dir = WeatherState.compass_label(root.cur.wind_dir);
        return "Atmospheric analysis: " + phrase + ". Humidity " + root.cur.humidity + "%. Wind " + Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit() + " " + dir + "." + (root.aqi >= 0 ? " Air quality index " + root.aqi + "." : "");
    }

    readonly property var readouts: ["feels", "wind", "uv", "aqi"].map(key => WeatherState.vital(key)).filter(v => !!v)

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Item {
            readonly property real size: root.width >= 300 ? 64 : 52
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            Layout.alignment: Qt.AlignTop

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.lock_color, 0.06)
            }

            CornerBrackets {
                anchors.fill: parent
                color: root.lock_color
                inset: 0
                arm: 10
                thickness: 1.5
                all_corners: true
            }

            Image {
                visible: root.has
                anchors.fill: parent
                anchors.margins: 8
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                sourceSize.width: Math.ceil(96 * dpr)
                sourceSize.height: Math.ceil(96 * dpr)
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                smooth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            GridLayout {
                Layout.fillWidth: true
                columns: root.width >= 300 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 0

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.threat ? "THREAT DETECTED" : root.has ? "SCAN COMPLETE" : WeatherState.loading ? "SCANNING" : "SCAN FAILED"
                    color: root.threat ? Theme.theme_label : root.has || WeatherState.loading ? Theme.theme_primary : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.letterSpacing: 2.5
                }

                Text {
                    visible: root.has
                    text: Math.round(root.has ? root.cur.temp : 0) + "°" + WeatherState.unit_symbol()
                    color: Theme.fg_strong
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(4)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.alpha(root.lock_color, 0.6) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                wrapMode: Text.WordWrap
                text: root.log_line
                color: root.has ? Style.text_fg : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                lineHeight: 1.1
            }

            Text {
                visible: WeatherState.location_name !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "Location: " + WeatherState.location_name
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Text {
                visible: WeatherState.stale
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: WeatherState.stale_text()
                color: Theme.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }
    }

    Rectangle {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.alpha(root.lock_color, 0.25)
    }

    GridLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        columns: 5
        columnSpacing: 8
        rowSpacing: 3

        GaugeLabel { text: "TEMP" }

        RangeEnd { text: Math.round(WeatherState.today_low) + "°" }

        Item {
            id: energy_bar
            Layout.fillWidth: true
            Layout.preferredHeight: 8

            SegBar {
                anchors.fill: parent
                count: 24
                gap: 1
                last_lit: Math.round(WeatherState.temp_range_pos * count) - 1
                on_color: root.vital_color("temp")
                off_color: Qt.alpha(root.lock_color, 0.14)
            }

            Rectangle {
                x: Math.max(0, Math.min(energy_bar.width - width, WeatherState.temp_range_pos * energy_bar.width - width / 2))
                y: -3
                width: 2
                height: energy_bar.height + 6
                color: Theme.fg_strong
            }
        }

        RangeEnd { text: Math.round(WeatherState.today_high) + "°" }

        GaugeValue { key: "temp" }

        GaugeLabel { text: "HUM" }

        EnergyTanks {
            key: "hum"
            Layout.columnSpan: 3
        }

        GaugeValue { key: "hum" }

        GaugeLabel { text: "RAIN" }

        EnergyTanks {
            key: "rain"
            Layout.columnSpan: 3
        }

        GaugeValue { key: "rain" }
    }

    GridLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        columns: root.width >= 360 ? 4 : 2
        columnSpacing: 6
        rowSpacing: 6

        Repeater {
            model: root.readouts

            Item {
                id: cell
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: cell_column.implicitHeight + 10

                CornerBrackets {
                    anchors.fill: parent
                    color: Qt.alpha(root.lock_color, 0.5)
                    inset: 0
                    arm: 5
                    all_corners: true
                }

                Column {
                    id: cell_column
                    x: 6
                    y: 5
                    width: parent.width - 12
                    spacing: 1

                    Item {
                        width: parent.width
                        height: cell_label.implicitHeight

                        GaugeLabel {
                            id: cell_label
                            text: cell.modelData.label
                        }

                        Text {
                            anchors.left: cell_label.right
                            anchors.leftMargin: 6
                            anchors.right: parent.right
                            anchors.baseline: cell_label.baseline
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: cell.modelData.detail
                            color: cell.modelData.color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-6)
                        }
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.reading_text(cell.modelData)
                        color: cell.modelData.key === "aqi" && WeatherState.aqi_now < 0 ? Style.text_muted : Theme.fg_strong
                        font.family: Style.number_font
                        font.pixelSize: Style.fs(-2)
                    }
                }
            }
        }
    }

    // Degrees hug the number ("74°F"); word units stand apart ("8 mph").
    function reading_text(vital) {
        const spaced = vital.unit !== "" && !vital.unit.startsWith("°");
        return vital.value + (spaced ? " " : "") + vital.unit;
    }

    function vital_color(key) {
        const v = WeatherState.vital(key);
        return v ? v.color : root.lock_color;
    }

    component GaugeLabel: Text {
        color: root.lock_color
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.letterSpacing: 2
    }

    component RangeEnd: Text {
        color: Style.text_muted
        font.family: Style.number_font
        font.pixelSize: Style.fs(-4)
    }

    component GaugeValue: Text {
        property string key: ""
        readonly property var vital: WeatherState.vital(key)
        Layout.alignment: Qt.AlignRight
        text: vital ? vital.value + vital.unit : ""
        color: Theme.fg_strong
        font.family: Style.number_font
        font.pixelSize: Style.fs(-4)
    }

    // One tank per tenth, like the Energy Tanks above Samus's energy count.
    component EnergyTanks: SegBar {
        property string key: ""
        readonly property var vital: WeatherState.vital(key)
        Layout.fillWidth: true
        Layout.preferredHeight: 7
        count: 10
        gap: 3
        last_lit: vital ? Math.round(vital.fill * count) - 1 : -1
        on_color: vital ? vital.color : root.lock_color
        off_color: Qt.alpha(root.lock_color, 0.14)
    }
}
