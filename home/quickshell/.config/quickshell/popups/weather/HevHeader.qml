// home/quickshell/.config/quickshell/popups/weather/HevHeader.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../components"
import "../../theme"
import "../../services"

// The HEV suit readout: a health cross beside TEMP, the suit shield and an angled bar for HUM, then an HEV voice line.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool wide: root.width >= 300
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property real humidity: root.has ? Math.max(0, Math.min(100, root.cur.humidity)) : 0
    readonly property var compass: ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted

    // Alert, then air, then radiation, as the suit would announce them.
    readonly property var voice: {
        if (WeatherState.alerts.length > 0) return [true, "WARNING: HAZARDOUS ENVIRONMENT DETECTED"];
        if (root.aqi > 100) return [true, "ATMOSPHERIC CONTAMINANT SENSORS ACTIVATED"];
        if (root.has && root.cur.uv_index >= 8) return [true, "RADIATION LEVELS DETECTED"];
        if (!root.has) return [WeatherState.error !== "" && !WeatherState.loading, WeatherState.loading ? "SENSORS INITIALIZING" : "SENSOR FAILURE"];
        return [false, "SURFACE CONDITIONS NOMINAL"];
    }
    readonly property color voice_color: root.voice[0] ? Theme.theme_label : root.hl

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: root.wide ? 14 : 10

        GridLayout {
            columns: 2
            columnSpacing: 8
            rowSpacing: 3

            Shape {
                id: cross
                readonly property real zoom: root.wide ? 1.25 : 1
                Layout.preferredWidth: 24 * zoom
                Layout.preferredHeight: 24 * zoom
                Layout.alignment: Qt.AlignVCenter
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: -1
                    fillColor: root.hl
                    scale: Qt.size(cross.zoom, cross.zoom)
                    PathSvg { path: "M8.5 1h7v7.5H23v7h-7.5V23h-7v-7.5H1v-7h7.5z" }
                }
            }

            Readout {
                value: root.has ? String(Math.round(root.cur.temp)) : "--"
                unit: "°" + WeatherState.unit_symbol()
                size: root.wide ? 46 : 36
            }

            CapsLabel {
                Layout.columnSpan: 2
                text: "TEMP"
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Style.hairline
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 4

            RowLayout {
                spacing: 8

                Item {
                    id: shield
                    readonly property real fill_top: 28 * (1 - root.humidity / 100)
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 28

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 1.5
                            strokeColor: Style.hairline
                            fillColor: "transparent"
                            PathSvg { path: "M12 1.5 22 5.5v8.5c0 6-4.4 10.4-10 12.5C6.4 24.4 2 20 2 14V5.5z" }
                        }
                    }

                    Item {
                        y: shield.fill_top
                        width: parent.width
                        height: parent.height - shield.fill_top
                        clip: true

                        Shape {
                            y: -shield.fill_top
                            width: shield.width
                            height: shield.height
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeWidth: -1
                                fillColor: root.hl
                                PathSvg { path: "M12 1.5 22 5.5v8.5c0 6-4.4 10.4-10 12.5C6.4 24.4 2 20 2 14V5.5z" }
                            }
                        }
                    }
                }

                Readout {
                    value: root.has ? String(root.cur.humidity) : "--"
                    unit: "%"
                    size: root.wide ? 34 : 28
                }
            }

            SkewBar {
                Layout.fillWidth: true
                Layout.maximumWidth: 150
                Layout.leftMargin: 5
                value: root.humidity / 100
            }

            CapsLabel {
                text: "HUM"
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.preferredHeight: voice_row.implicitHeight + 8
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(root.voice_color, 0.13) }
            GradientStop { position: 1; color: "transparent" }
        }

        Rectangle {
            width: 2
            height: parent.height
            color: root.voice_color
        }

        RowLayout {
            id: voice_row
            x: 8
            width: parent.width - 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Item {
                Layout.preferredWidth: 13
                Layout.preferredHeight: 12
                Layout.alignment: Qt.AlignVCenter

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: -1
                        fillColor: root.voice_color
                        PathPolyline { path: [Qt.point(6.5, 0), Qt.point(13, 12), Qt.point(0, 12), Qt.point(6.5, 0)] }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -1
                    text: "!"
                    color: Theme.bg_crust
                    font.family: Style.number_font
                    font.pixelSize: 9
                    font.bold: true
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                wrapMode: Text.WordWrap
                text: root.voice[1]
                color: root.voice_color
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
                font.bold: true
                font.letterSpacing: 1.3
            }
        }
    }

    Text {
        visible: root.has
        Layout.fillWidth: true
        Layout.topMargin: 2
        elide: Text.ElideRight
        text: root.has ? root.cur.cond + " · Feels like " + Math.round(root.cur.feels) + "°" + WeatherState.unit_symbol() + " · Wind " + Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit() + " " + root.compass[Math.round(((root.cur.wind_dir % 360) + 360) % 360 / 22.5) % 16] : ""
        color: root.hl_t
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }

    Text {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: WeatherState.location_name
        color: root.hl_t
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    Text {
        visible: WeatherState.stale || (!root.has && WeatherState.error !== "")
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: (WeatherState.stale ? "Stale data" : "Unavailable") + (WeatherState.error ? ": " + WeatherState.error : "")
        color: Theme.warning
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    component Readout: Row {
        id: readout
        property string value: ""
        property string unit: ""
        property int size: 46
        spacing: 2

        Text {
            text: readout.value
            color: root.hl
            font.family: Style.number_font
            font.pixelSize: readout.size
            font.bold: true
            lineHeight: 0.9
        }

        Text {
            text: readout.unit
            color: root.hl_t
            font.family: Style.number_font
            font.pixelSize: Math.round(readout.size * 0.35)
            font.bold: true
        }
    }

    component CapsLabel: Text {
        color: root.hl_t
        font.family: Style.font_family
        font.pixelSize: Style.fs(-6)
        font.bold: true
        font.letterSpacing: 3.2
    }
}
