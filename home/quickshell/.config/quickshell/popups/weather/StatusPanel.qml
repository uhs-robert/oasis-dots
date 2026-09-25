// home/quickshell/.config/quickshell/popups/weather/StatusPanel.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../../components"
import "../../theme"
import "../../services"
import "Materia.js" as Materia

// The FF7 status screen: the alert as a battle message, the condition as a portrait, TEMP and HUM as gauges, RAIN as a Limit bar.
ColumnLayout {
    id: root

    signal alert_clicked()

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property var today: WeatherState.days.length > 0 ? WeatherState.days[0] : null
    readonly property bool roomy: root.width >= 300
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property string unit: "°" + WeatherState.unit_symbol()
    // TEMP reads like HP: now over the day's high, or across the day's range when the high is not above zero.
    readonly property real temp_fill: {
        if (!root.has || !root.today) return 0;
        const t = root.cur.temp, hi = root.today.max, lo = root.today.min;
        const f = hi > 0 ? t / hi : hi > lo ? (t - lo) / (hi - lo) : 1;
        return Math.max(0, Math.min(1, f));
    }
    readonly property var stats: root.has ? [
        ["FEELS", Math.round(root.cur.feels), root.unit],
        ["WIND", Math.round(root.cur.wind_speed), WeatherState.wind_unit() + " " + Materia.direction(root.cur.wind_dir)],
        ["UV", root.cur.uv_index.toFixed(1), ""],
        ["AQI", root.aqi >= 0 ? root.aqi : "--", root.aqi >= 0 ? WeatherState.aqi_band(root.aqi).label.toLowerCase() : ""]
    ] : []

    // Sized from the widest label/value actually shown, so a bigger style font never clips the fixed-width columns below.
    TextMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.ExtraBold
        text: "FEELS"
    }

    TextMetrics {
        id: pct_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-2)
        font.weight: Font.ExtraBold
        text: "100%"
    }

    readonly property real label_col_w: Math.max(44, label_metrics.tightBoundingRect.width + 6)
    readonly property real pct_col_w: Math.max(40, pct_metrics.tightBoundingRect.width + 4)

    component Label: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
        font.weight: Font.ExtraBold
        font.letterSpacing: 1
    }

    component Value: Text {
        color: Theme.fg_strong
        font.family: Style.font_family
        font.pixelSize: Style.font_size
        font.weight: Font.ExtraBold
    }

    component Small: Text {
        color: Theme.theme_primary_light
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.weight: Font.DemiBold
    }

    component StatLine: RowLayout {
        id: stat
        property string label: ""
        property string caption: ""
        property string now: ""
        property string high: ""
        property string unit: ""
        property real fill: 0
        property color from: Theme.theme_primary_strong
        property color to: Theme.theme_primary_light

        Layout.fillWidth: true
        spacing: 6

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    Layout.preferredWidth: root.label_col_w
                    text: stat.label
                }

                Small {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: stat.caption
                }

                Value {
                    text: stat.now
                }

                Small {
                    visible: stat.high !== ""
                    text: "/"
                    font.pixelSize: Style.fs(-2)
                }

                Value {
                    visible: stat.high !== ""
                    text: stat.high
                }

                Small {
                    text: stat.unit
                }
            }

            AtbBar {
                Layout.fillWidth: true
                Layout.leftMargin: 50
                Layout.preferredHeight: 5
                value: stat.fill
                fill_color: stat.from
                shade_color: stat.to
                horizontal: true
            }
        }
    }

    spacing: 8

    BattleMessage {
        visible: WeatherState.alerts.length > 0
        Layout.fillWidth: true
        onClicked: root.alert_clicked()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Rectangle {
            id: portrait
            visible: root.roomy
            Layout.preferredWidth: 66
            Layout.preferredHeight: 66
            Layout.alignment: Qt.AlignTop
            radius: 4
            color: Theme.bg_core
            border.width: 2
            border.color: Style.frame_border_color

            Shape {
                anchors.fill: parent
                anchors.margins: 2
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 1
                    strokeColor: Style.frame_inset_color
                    fillGradient: RadialGradient {
                        centerX: 31
                        centerY: 25
                        centerRadius: 44
                        focalX: 31
                        focalY: 25
                        focalRadius: 0
                        GradientStop { position: 0; color: Qt.tint(Theme.bg_core, Qt.alpha(Theme.theme_primary_light, 0.22)) }
                        GradientStop { position: 0.7; color: Theme.bg_core }
                    }
                    PathRectangle { width: 62; height: 62; radius: 2 }
                }
            }

            Image {
                visible: root.has
                anchors.centerIn: parent
                width: 50
                height: 50
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                sourceSize.width: Math.ceil(100 * dpr)
                sourceSize.height: Math.ceil(100 * dpr)
                source: root.has ? WeatherState.icon_source(root.cur.code, root.cur.is_day) : ""
                smooth: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                MateriaOrb {
                    visible: root.has
                    Layout.preferredWidth: 15
                    Layout.preferredHeight: 15
                    color: root.has ? Materia.color(Style.materia, WeatherState.weather_color_keys, root.cur.code) : "transparent"
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "Unavailable" + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: root.has || WeatherState.loading ? Theme.fg_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(2)
                    font.weight: Font.ExtraBold
                }
            }

            StatLine {
                visible: root.has
                label: "TEMP"
                caption: root.today ? "now / high" : "now"
                now: root.has ? String(Math.round(root.cur.temp)) : ""
                high: root.has && root.today ? String(Math.round(root.today.max)) : ""
                unit: root.unit
                fill: root.temp_fill
            }

            StatLine {
                visible: root.has
                label: "HUM"
                now: root.has ? String(root.cur.humidity) : ""
                unit: "%"
                fill: root.has ? root.cur.humidity / 100 : 0
                from: Theme.theme_secondary_strong
                to: Theme.theme_secondary
            }
        }
    }

    GridLayout {
        visible: root.has
        Layout.fillWidth: true
        columns: root.roomy ? 2 : 1
        columnSpacing: 14
        rowSpacing: 2

        Repeater {
            model: root.stats

            RowLayout {
                id: kv
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 6

                Label {
                    Layout.fillWidth: true
                    text: kv.modelData[0]
                }

                Value {
                    text: kv.modelData[1]
                    font.pixelSize: Style.fs(-2)
                }

                Small {
                    visible: text !== ""
                    Layout.maximumWidth: 90
                    elide: Text.ElideRight
                    text: kv.modelData[2]
                }
            }
        }
    }

    Rectangle {
        visible: root.has && !!root.today
        Layout.fillWidth: true
        Layout.preferredHeight: limit_row.implicitHeight + 12
        radius: 5
        color: Qt.alpha(Theme.bg_crust, 0.35)
        border.width: 2
        border.color: Style.frame_border_color

        RowLayout {
            id: limit_row
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6

            Label {
                Layout.preferredWidth: root.label_col_w
                text: "RAIN"
            }

            AtbBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                value: root.today ? root.today.pop / 100 : 0
                fill_color: Theme.info
                shade_color: Qt.tint(Theme.info, Qt.alpha(Theme.fg_strong, 0.55))
                ticks: true
            }

            Value {
                Layout.preferredWidth: root.pct_col_w
                horizontalAlignment: Text.AlignRight
                text: root.today ? root.today.pop + "%" : ""
                font.pixelSize: Style.fs(-2)
            }
        }
    }

    Small {
        visible: WeatherState.location_name !== "" || WeatherState.stale
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: WeatherState.stale ? "Stale data" + (WeatherState.error ? ": " + WeatherState.error : "") : WeatherState.location_name
        color: WeatherState.stale ? Theme.warning : Theme.theme_primary_light
        font.pixelSize: Style.fs(-4)
    }
}
