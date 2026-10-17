import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.styles.snes.widgets as Snes

// A SNES RPG menu window: blue gradient panel in a light double border, conditions set out like a status screen.
Item {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool roomy: root.width >= 330
    readonly property var rows: WeatherState.vitals.filter(v => ["feels", "wind", "uv", "aqi"].indexOf(v.key) >= 0).map(v => [v.label, root.readout_text(v)])
    readonly property var gauges: !WeatherState.has_vitals ? [] : [
        { label: "TEMP", value: Math.round(WeatherState.current.temp) + "°", fill: WeatherState.temp_range_pos, range: true },
        { label: "HUM", value: WeatherState.current.humidity + "%", fill: WeatherState.current.humidity / 100, range: false },
        { label: "RAIN", value: WeatherState.today_pop + "%", fill: WeatherState.today_pop / 100, range: false }
    ]

    // The EPA's own short name keeps the longest AQI band on one line.
    function readout_text(vital) {
        if (vital.key === "feels") return vital.value + "°";
        const detail = vital.detail.replace("Unhealthy for Sensitive Groups", "USG");
        return [vital.value, vital.unit, detail].filter(part => part !== "").join(" ").toUpperCase();
    }

    implicitHeight: body.implicitHeight + 24

    Snes.SnesWindow {
        id: menu_window
        anchors.fill: parent
    }

    ColumnLayout {
        id: body
        anchors.left: menu_window.left
        anchors.right: menu_window.right
        anchors.top: menu_window.top
        anchors.leftMargin: 14
        anchors.rightMargin: 14 + menu_window.drop
        anchors.topMargin: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Image {
                visible: root.has
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                sourceSize.width: Math.ceil(80 * dpr)
                sourceSize.height: Math.ceil(80 * dpr)
                smooth: true
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.has ? Math.round(root.cur.temp) + "°" + WeatherState.unit_symbol() : WeatherState.failed ? "n/a" : "--°"
                color: root.has ? Theme.fg_strong : Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.font_size * 2
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "No signal"
                color: root.has || WeatherState.loading ? Theme.theme_secondary : Theme.warning
                font.family: Style.font_family
                font.pixelSize: Style.fs(-2)
                font.capitalization: Font.AllUppercase
                style: Text.Raised
                styleColor: Style.text_shadow
            }
        }

        // Status-screen gauges: TEMP spans today's low to high with a notch at now; HUM and RAIN fill from empty.
        GridLayout {
            visible: WeatherState.has_vitals
            Layout.fillWidth: true
            Layout.topMargin: 2
            columns: 5
            columnSpacing: 8
            rowSpacing: 5

            Repeater {
                model: root.gauges

                Text {
                    id: gauge_label
                    required property var modelData
                    required property int index
                    Layout.row: gauge_label.index
                    Layout.column: 0
                    text: gauge_label.modelData.label
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }

            Repeater {
                model: root.gauges

                Text {
                    id: gauge_value
                    required property var modelData
                    required property int index
                    Layout.row: gauge_value.index
                    Layout.column: 1
                    Layout.alignment: Qt.AlignRight
                    text: gauge_value.modelData.value
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }

            Text {
                Layout.row: 0
                Layout.column: 2
                text: Math.round(WeatherState.today_low) + "°"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Repeater {
                model: root.gauges

                Snes.SnesGauge {
                    id: gauge_bar
                    required property var modelData
                    required property int index
                    Layout.row: gauge_bar.index
                    Layout.column: gauge_bar.modelData.range ? 3 : 2
                    Layout.columnSpan: gauge_bar.modelData.range ? 1 : 3
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    value: gauge_bar.modelData.fill

                    Rectangle {
                        visible: gauge_bar.modelData.range
                        x: Math.round(1 + gauge_bar.inner_w * gauge_bar.v) - 1
                        y: -2
                        width: 2
                        height: gauge_bar.height + 4
                        color: Theme.fg_strong
                    }
                }
            }

            Text {
                Layout.row: 0
                Layout.column: 4
                text: Math.round(WeatherState.today_high) + "°"
                color: Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }
        }

        GridLayout {
            visible: WeatherState.has_vitals
            Layout.fillWidth: true
            columns: root.roomy ? 4 : 2
            columnSpacing: 10
            rowSpacing: 3

            Repeater {
                model: root.rows

                Text {
                    id: row_label
                    required property var modelData
                    required property int index
                    Layout.row: Math.floor(row_label.index / (root.roomy ? 2 : 1))
                    Layout.column: 2 * (row_label.index % (root.roomy ? 2 : 1))
                    text: row_label.modelData[0]
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }

            Repeater {
                model: root.rows

                Text {
                    id: row_value
                    required property var modelData
                    required property int index
                    Layout.row: Math.floor(row_value.index / (root.roomy ? 2 : 1))
                    Layout.column: 2 * (row_value.index % (root.roomy ? 2 : 1)) + 1
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: row_value.modelData[1]
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-6)
                    style: Text.Raised
                    styleColor: Style.text_shadow
                }
            }
        }

        RowLayout {
            visible: WeatherState.location_name !== "" || WeatherState.stale || WeatherState.failed
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: WeatherState.failed ? "ERROR" : WeatherState.stale ? "STALE" : "LOC"
                color: WeatherState.stale || WeatherState.failed ? Theme.warning : Theme.theme_primary_light
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: WeatherState.stale || WeatherState.failed ? (WeatherState.error || "Old data") : WeatherState.location_name
                color: WeatherState.stale || WeatherState.failed ? Theme.warning : Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
                style: Text.Raised
                styleColor: Style.text_shadow
            }
        }
    }
}
