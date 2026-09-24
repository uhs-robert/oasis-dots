// home/quickshell/.config/quickshell/popups/weather/ScopeHeader.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../components"
import "../../theme"
import "../../services"

// Current conditions on a sensor scope: wind bearing and the next 12 hours of precip as contacts, the temperature as the locked target.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool alert: WeatherState.alerts.length > 0
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property color vec: Style.text_primary
    readonly property color lock: Style.selection_brackets.a > 0 ? Style.selection_brackets : Theme.theme_label
    readonly property color readout: Style.text_accent
    readonly property color ring: root.alert ? root.lock : root.vec
    readonly property var blip_hours: WeatherState.hours.slice(0, 12)
    readonly property int pop_max: root.blip_hours.reduce((m, h) => Math.max(m, h.pop), 0)
    readonly property bool is_open: Popups.open_name === "weather"
    readonly property var compass: ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    readonly property var readouts: !root.has ? [] : [
        { label: "WND", value: Math.round(root.cur.wind_speed) + " " + root.bearing(root.cur.wind_dir), color: root.vec },
        { label: "HUM", value: root.cur.humidity + "%", color: root.readout },
        { label: "UV", value: root.cur.uv_index.toFixed(1), color: root.cur.uv_index >= 8 ? root.lock : root.readout },
        { label: "AQI", value: root.aqi >= 0 ? String(root.aqi) : "--", color: root.aqi > 150 ? root.lock : root.readout },
        { label: "PRECIP", value: root.pop_max + "%", color: root.readout }
    ]

    function bearing(deg) {
        return root.compass[Math.round((((deg % 360) + 360) % 360) / 22.5) % 16];
    }

    onIs_openChanged: root.is_open ? sweep_anim.restart() : sweep_anim.stop()
    Component.onCompleted: if (root.is_open) sweep_anim.restart()

    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Item {
            id: scope
            readonly property real size: Math.round(Math.max(96, Math.min(148, root.width * 0.4)))
            readonly property real c: scope.size / 2
            readonly property real r: scope.c - 1
            readonly property real wind_max: WeatherState.settings.unit === "celsius" ? 60 : 40
            readonly property real wind_len: root.has ? scope.r * 0.66 * Math.max(0.12, Math.min(1, root.cur.wind_speed / scope.wind_max)) : 0
            readonly property real wind_rad: root.has ? root.cur.wind_dir * Math.PI / 180 : 0
            readonly property point tip: Qt.point(scope.c + Math.sin(scope.wind_rad) * scope.wind_len, scope.c - Math.cos(scope.wind_rad) * scope.wind_len)
            readonly property var ticks: {
                const out = [];
                for (let d = 0; d < 360; d += 10) {
                    const a = d * Math.PI / 180;
                    const len = d % 90 === 0 ? 7 : d % 30 === 0 ? 5 : 2.5;
                    out.push([Qt.point(scope.c + Math.sin(a) * scope.r, scope.c - Math.cos(a) * scope.r), Qt.point(scope.c + Math.sin(a) * (scope.r - len), scope.c - Math.cos(a) * (scope.r - len))]);
                }
                return out;
            }

            Layout.preferredWidth: scope.size
            Layout.preferredHeight: scope.size
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.alpha(root.ring, 0.05)
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: Qt.alpha(root.ring, 0.3)
                    strokeWidth: 1
                    fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 3]
                    startX: scope.c
                    startY: scope.c - scope.r
                    PathLine { x: scope.c; y: scope.c + scope.r }
                    PathMove { x: scope.c - scope.r; y: scope.c }
                    PathLine { x: scope.c + scope.r; y: scope.c }
                }

                ShapePath {
                    strokeColor: Qt.alpha(root.ring, 0.35)
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathAngleArc { centerX: scope.c; centerY: scope.c; radiusX: scope.r * 0.66; radiusY: scope.r * 0.66; startAngle: 0; sweepAngle: 360 }
                    PathAngleArc { centerX: scope.c; centerY: scope.c; radiusX: scope.r * 0.33; radiusY: scope.r * 0.33; startAngle: 0; sweepAngle: 360 }
                }

                ShapePath {
                    strokeColor: root.ring
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathAngleArc { centerX: scope.c; centerY: scope.c; radiusX: scope.r; radiusY: scope.r; startAngle: 0; sweepAngle: 360 }
                }

                ShapePath {
                    strokeColor: Qt.alpha(root.ring, 0.75)
                    strokeWidth: 1
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathMultiline { paths: scope.ticks }
                }

                ShapePath {
                    strokeColor: root.has ? root.vec : "transparent"
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    startX: scope.c
                    startY: scope.c
                    PathLine { x: scope.tip.x; y: scope.tip.y }
                }

                ShapePath {
                    strokeWidth: -1
                    fillColor: root.has ? root.vec : "transparent"
                    startX: scope.tip.x
                    startY: scope.tip.y - 3.5
                    PathLine { x: scope.tip.x + 3.5; y: scope.tip.y }
                    PathLine { x: scope.tip.x; y: scope.tip.y + 3.5 }
                    PathLine { x: scope.tip.x - 3.5; y: scope.tip.y }
                    PathLine { x: scope.tip.x; y: scope.tip.y - 3.5 }
                }
            }

            Repeater {
                model: [["N", 0], ["E", 90], ["S", 180], ["W", 270]]

                Text {
                    required property var modelData
                    readonly property real a: modelData[1] * Math.PI / 180
                    x: scope.c + Math.sin(a) * (scope.r - 14) - width / 2
                    y: scope.c - Math.cos(a) * (scope.r - 14) - height / 2
                    text: modelData[0]
                    color: Qt.alpha(root.ring, 0.8)
                    font.family: Style.mono_font
                    font.pixelSize: Math.max(7, Style.font_size - 6)
                }
            }

            Repeater {
                model: root.blip_hours

                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property real a: (index + 0.5) * 30 * Math.PI / 180
                    readonly property real p: Math.max(0, Math.min(100, modelData.pop)) / 100
                    width: 2 + p * 4
                    height: width
                    radius: width / 2
                    x: scope.c + Math.sin(a) * (scope.r - 9) - width / 2
                    y: scope.c - Math.cos(a) * (scope.r - 9) - height / 2
                    color: root.readout
                    opacity: 0.25 + p * 0.75
                }
            }

            Reticle {
                anchors.centerIn: parent
                width: 12
                height: 12
                color: root.ring
                center_color: root.ring
            }

            Item {
                id: sweep
                anchors.fill: parent
                visible: sweep_anim.running

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillGradient: ConicalGradient {
                            centerX: scope.c
                            centerY: scope.c
                            angle: 90
                            GradientStop { position: 0; color: Qt.alpha(root.vec, 0.3) }
                            GradientStop { position: 0.11; color: "transparent" }
                            GradientStop { position: 1; color: "transparent" }
                        }
                        startX: scope.c
                        startY: scope.c
                        PathLine { x: scope.c; y: scope.c - scope.r }
                        PathArc {
                            x: scope.c - Math.sin(40 * Math.PI / 180) * scope.r
                            y: scope.c - Math.cos(40 * Math.PI / 180) * scope.r
                            radiusX: scope.r
                            radiusY: scope.r
                            direction: PathArc.Counterclockwise
                        }
                        PathLine { x: scope.c; y: scope.c }
                    }

                    ShapePath {
                        strokeColor: root.vec
                        strokeWidth: 1.5
                        fillColor: "transparent"
                        startX: scope.c
                        startY: scope.c
                        PathLine { x: scope.c; y: scope.c - scope.r }
                    }
                }

                NumberAnimation {
                    id: sweep_anim
                    target: sweep
                    property: "rotation"
                    from: 0
                    to: 360
                    duration: 1400
                    easing.type: Easing.InOutSine
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Rectangle {
                visible: root.alert
                Layout.preferredWidth: warning_text.implicitWidth + 10
                Layout.preferredHeight: warning_text.implicitHeight + 4
                color: Qt.alpha(root.lock, 0.12)
                border.width: 1
                border.color: root.lock

                Text {
                    id: warning_text
                    anchors.centerIn: parent
                    text: "WARNING"
                    color: root.lock
                    font.family: Style.mono_font
                    font.pixelSize: Style.font_size - 5
                    font.bold: true
                    font.letterSpacing: 1.5
                }
            }

            Item {
                Layout.preferredWidth: temp_row.implicitWidth + 16
                Layout.preferredHeight: temp_row.implicitHeight + 4

                Row {
                    id: temp_row
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        id: temp_text
                        text: root.has ? Math.round(root.cur.temp) : "--"
                        color: root.has ? Style.text_strong : Style.text_dim
                        font.family: Style.number_font
                        font.pixelSize: Style.font_size * 2 + 6
                    }

                    Text {
                        y: temp_text.height * 0.14
                        text: "°" + WeatherState.unit_symbol()
                        color: root.lock
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 2
                    }
                }

                CornerBrackets {
                    anchors.fill: parent
                    color: root.lock
                    inset: 0
                    arm: 7
                    thickness: 1.5
                    all_corners: true
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: "TGT: " + (root.has ? root.cur.cond : WeatherState.loading ? "Acquiring" : "No signal")
                color: root.has || WeatherState.loading ? Style.text_fg : Theme.warning
                font.family: Style.mono_font
                font.pixelSize: Style.font_size - 3
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
            }

            Text {
                visible: root.has
                Layout.bottomMargin: 3
                text: "FEELS " + (root.has ? Math.round(root.cur.feels) + "°" + WeatherState.unit_symbol() : "")
                color: root.readout
                font.family: Style.mono_font
                font.pixelSize: Style.font_size - 4
            }

            Repeater {
                model: root.readouts

                RowLayout {
                    id: readout_row
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: readout_row.modelData.label
                        color: Qt.alpha(root.readout, 0.6)
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 4
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        clip: true
                        text: "·".repeat(60)
                        color: Qt.alpha(root.readout, 0.3)
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 4
                    }

                    Text {
                        text: readout_row.modelData.value
                        color: readout_row.modelData.color
                        font.family: Style.mono_font
                        font.pixelSize: Style.font_size - 4
                    }
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
            font.pixelSize: Style.font_size - 4
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: WeatherState.location_name
            color: Style.text_fg
            font.family: Style.mono_font
            font.pixelSize: Style.font_size - 4
        }

        Text {
            visible: root.width >= 330
            text: Math.abs(WeatherState.lat).toFixed(2) + (WeatherState.lat >= 0 ? "N " : "S ") + Math.abs(WeatherState.lon).toFixed(2) + (WeatherState.lon >= 0 ? "E" : "W")
            color: Style.text_muted
            font.family: Style.mono_font
            font.pixelSize: Style.font_size - 4
        }
    }

    Text {
        visible: WeatherState.stale
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: "STALE DATA" + (WeatherState.error ? ": " + WeatherState.error : "")
        color: Theme.warning
        font.family: Style.mono_font
        font.pixelSize: Style.font_size - 4
    }
}
