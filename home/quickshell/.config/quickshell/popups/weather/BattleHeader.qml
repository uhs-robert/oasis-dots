import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

// A Dragon Quest encounter: the condition appears as the enemy, its stats laid out like the party status window.
Item {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int sprite: root.roomy ? 48 : 32
    readonly property bool roomy: root.width >= 300
    readonly property int stat_px: Style.fs(-5)
    readonly property var gauges: !WeatherState.has_vitals ? [] : [
        { label: "TEMP", value: Math.round(WeatherState.current.temp) + "°", low: Math.round(WeatherState.today_low), high: Math.round(WeatherState.today_high), fill: WeatherState.temp_range_pos, color: WeatherState.vital("temp").color, range: true },
        { label: "HUM", value: WeatherState.current.humidity + "%", fill: WeatherState.current.humidity / 100, color: WeatherState.vital("hum").color, range: false },
        { label: "RAIN", value: WeatherState.today_pop + "%", fill: WeatherState.today_pop / 100, color: WeatherState.vital("rain").color, range: false }
    ]
    readonly property var readouts: WeatherState.vitals.filter(v => ["feels", "wind", "uv", "aqi"].indexOf(v.key) >= 0)

    // The EPA's own short name keeps the longest AQI band on one line.
    function readout_text(vital) {
        if (vital.key === "feels") return vital.value + "°";
        const detail = vital.detail.replace("Unhealthy for Sensitive Groups", "USG");
        return [vital.value, vital.unit, detail].filter(part => part !== "").join(" ").toUpperCase();
    }

    implicitHeight: body.implicitHeight + 30

    DqWindow {
        anchors.fill: parent
        anchors.topMargin: 6
        title: WeatherState.location_name.toUpperCase()

        RowLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Image {
                visible: root.has
                Layout.preferredWidth: root.sprite
                Layout.preferredHeight: root.sprite
                Layout.alignment: Qt.AlignTop
                sourceSize.width: 16
                sourceSize.height: 16
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                smooth: false
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.has ? root.cur.cond.toUpperCase() + " APPEARS!" : WeatherState.loading ? "LOADING..." : "NOTHING APPEARS."
                    color: root.has || WeatherState.loading ? Theme.fg_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    lineHeight: 1.3
                }

                // HP/MP-style rows: TEMP spans today's low to high with a tick at now; HUM and RAIN fill from empty.
                GridLayout {
                    visible: WeatherState.has_vitals
                    Layout.fillWidth: true
                    columns: 5
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: root.gauges

                        Text {
                            id: gauge_label
                            required property var modelData
                            required property int index
                            Layout.row: gauge_label.index
                            Layout.column: 0
                            text: gauge_label.modelData.label
                            color: Style.caret_color
                            font.family: Style.font_family
                            font.pixelSize: root.stat_px
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
                            text: gauge_value.modelData.value
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: root.stat_px
                        }
                    }

                    Text {
                        visible: WeatherState.has_vitals
                        Layout.row: 0
                        Layout.column: 2
                        text: root.gauges.length > 0 ? root.gauges[0].low : ""
                        color: Theme.fg_dim
                        font.family: Style.font_family
                        font.pixelSize: root.stat_px
                    }

                    Repeater {
                        model: root.gauges

                        BattleGauge {
                            id: gauge_bar
                            required property var modelData
                            required property int index
                            Layout.row: gauge_bar.index
                            Layout.column: gauge_bar.modelData.range ? 3 : 2
                            Layout.columnSpan: gauge_bar.modelData.range ? 1 : 3
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            value: gauge_bar.modelData.fill
                            fill_color: gauge_bar.modelData.color
                            marker: gauge_bar.modelData.range
                        }
                    }

                    Text {
                        visible: WeatherState.has_vitals
                        Layout.row: 0
                        Layout.column: 4
                        text: root.gauges.length > 0 ? root.gauges[0].high : ""
                        color: Theme.fg_dim
                        font.family: Style.font_family
                        font.pixelSize: root.stat_px
                    }
                }

                GridLayout {
                    visible: WeatherState.has_vitals
                    Layout.fillWidth: true
                    columns: root.roomy ? 4 : 2
                    columnSpacing: 6
                    rowSpacing: 4

                    Repeater {
                        model: root.readouts

                        Text {
                            id: readout_label
                            required property var modelData
                            required property int index
                            Layout.row: Math.floor(readout_label.index / (root.roomy ? 2 : 1))
                            Layout.column: 2 * (readout_label.index % (root.roomy ? 2 : 1))
                            text: readout_label.modelData.key === "feels" ? "FEEL" : readout_label.modelData.label
                            color: Style.caret_color
                            font.family: Style.font_family
                            font.pixelSize: root.stat_px
                        }
                    }

                    Repeater {
                        model: root.readouts

                        Text {
                            id: readout_value
                            required property var modelData
                            required property int index
                            Layout.row: Math.floor(readout_value.index / (root.roomy ? 2 : 1))
                            Layout.column: 2 * (readout_value.index % (root.roomy ? 2 : 1)) + 1
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: root.readout_text(readout_value.modelData)
                            color: Theme.fg_strong
                            font.family: Style.font_family
                            font.pixelSize: root.stat_px
                        }
                    }
                }

                Text {
                    visible: WeatherState.stale || WeatherState.failed
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: WeatherState.failed ? "NO DATA: " + WeatherState.error : "STALE DATA"
                    color: Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                }
            }
        }
    }
}
