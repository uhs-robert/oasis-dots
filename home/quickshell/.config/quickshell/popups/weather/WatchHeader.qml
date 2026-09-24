// home/quickshell/.config/quickshell/popups/weather/WatchHeader.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "../../services"

// The current conditions as the GoldenEye pause watch: segmented health and armour arcs beside an LCD temperature.
RowLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property color health: Theme.theme_label
    readonly property color armour: Theme.info
    // Health fills with the temperature over 0-100 °F in either unit; armour with the humidity.
    readonly property real fahrenheit: !root.has ? 0 : WeatherState.settings.unit === "celsius" ? root.cur.temp * 9 / 5 + 32 : root.cur.temp
    readonly property real health_level: Math.max(0, Math.min(1, root.fahrenheit / 100))
    readonly property real armour_level: root.has ? Math.max(0, Math.min(1, root.cur.humidity / 100)) : 0
    readonly property string digits: root.has ? String(Math.round(root.cur.temp)) : "--"

    readonly property var readouts: !root.has ? [] : [
        { label: "HUM", value: root.cur.humidity + "%", label_color: root.armour },
        { label: "WIND", value: Math.round(root.cur.wind_speed) + " " + WeatherState.wind_dir_label(root.cur.wind_dir), label_color: Style.text_muted },
        { label: "UV", value: root.cur.uv_index.toFixed(1), label_color: Style.text_muted },
        { label: "AQI", value: root.aqi >= 0 ? String(root.aqi) : "--", label_color: Style.text_muted }
    ]

    spacing: 10

    Item {
        id: bars
        readonly property int segments: 12
        readonly property real half: 60 * Math.PI / 180
        readonly property real h: Math.round(Math.max(92, Math.min(136, root.width * 0.33)))
        readonly property real t: Math.max(7, Math.round(bars.h * 0.09))
        readonly property real gap: Math.max(2, Math.round(bars.t * 0.3))
        readonly property real outer: bars.h / 2 / Math.sin(bars.half)
        readonly property real cx: bars.outer
        readonly property real cy: bars.h / 2
        readonly property real r_health: bars.outer - bars.t / 2
        readonly property real r_armour: bars.r_health - bars.t - bars.gap
        readonly property int health_lit: Math.round(root.health_level * bars.segments)
        readonly property int armour_lit: Math.round(root.armour_level * bars.segments)

        // Segments from..to-1 of an arc bowing left, counted from its bottom end.
        function segment_path(r, from, to) {
            const a0 = Math.PI - bars.half;
            const step = 2 * bars.half / bars.segments;
            const cut = bars.gap / r;
            let d = "";
            for (let i = from; i < to; i++) {
                const a = a0 + i * step;
                const b = a + step - cut;
                d += "M " + (bars.cx + r * Math.cos(a)) + " " + (bars.cy + r * Math.sin(a)) + " A " + r + " " + r + " 0 0 1 " + (bars.cx + r * Math.cos(b)) + " " + (bars.cy + r * Math.sin(b)) + " ";
            }
            return d;
        }

        Layout.preferredWidth: Math.ceil(bars.cx - (bars.r_armour - bars.t / 2) * Math.cos(bars.half) + 1)
        Layout.preferredHeight: bars.h
        Layout.alignment: Qt.AlignVCenter

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(root.health, 0.18)
                strokeWidth: bars.t
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathSvg { path: bars.segment_path(bars.r_health, bars.health_lit, bars.segments) }
            }

            ShapePath {
                strokeColor: root.health
                strokeWidth: bars.t
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathSvg { path: bars.segment_path(bars.r_health, 0, bars.health_lit) }
            }

            ShapePath {
                strokeColor: Qt.alpha(root.armour, 0.18)
                strokeWidth: bars.t
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathSvg { path: bars.segment_path(bars.r_armour, bars.armour_lit, bars.segments) }
            }

            ShapePath {
                strokeColor: root.armour
                strokeWidth: bars.t
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathSvg { path: bars.segment_path(bars.r_armour, 0, bars.armour_lit) }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Row {
            spacing: 4

            Item {
                width: ghost.implicitWidth
                height: ghost.implicitHeight

                // Unlit LCD segments behind the digits.
                Text {
                    id: ghost
                    anchors.right: parent.right
                    text: "8".repeat(Math.max(2, root.digits.length))
                    color: Qt.alpha(Style.text_strong, 0.07)
                    font.family: Style.number_font
                    font.pixelSize: Style.font_size * 2 + 4
                }

                Text {
                    anchors.right: parent.right
                    text: root.digits
                    color: root.has ? Style.text_strong : Style.text_dim
                    font.family: Style.number_font
                    font.pixelSize: Style.font_size * 2 + 4
                }
            }

            Text {
                text: "°" + WeatherState.unit_symbol()
                color: root.health
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 1
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.topMargin: 2
            elide: Text.ElideRight
            text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "Unavailable"
            color: root.has || WeatherState.loading ? Style.text_fg : Theme.warning
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 3
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
        }

        Text {
            visible: root.has
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.bottomMargin: 2
            elide: Text.ElideRight
            text: "FEELS LIKE " + (root.has ? Math.round(root.cur.feels) + "°" + WeatherState.unit_symbol() : "")
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 4
        }

        GridLayout {
            id: readout_grid
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            columns: readout_grid.width >= 200 ? 2 : 1
            columnSpacing: 12
            rowSpacing: 1

            Repeater {
                model: root.readouts

                RowLayout {
                    id: readout_row
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    spacing: 3

                    Text {
                        text: readout_row.modelData.label
                        color: readout_row.modelData.label_color
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 4
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        clip: true
                        text: "·".repeat(40)
                        color: Qt.alpha(Style.text_muted, 0.4)
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 4
                    }

                    Text {
                        text: readout_row.modelData.value
                        color: Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 4
                    }
                }
            }
        }

        Text {
            visible: WeatherState.stale
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: "STALE DATA" + (WeatherState.error ? ": " + WeatherState.error : "")
            color: Theme.warning
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 4
        }
    }
}
