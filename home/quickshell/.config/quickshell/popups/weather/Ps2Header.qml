// home/quickshell/.config/quickshell/popups/weather/Ps2Header.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "../../services"

// The PS2 clock screen: a thin oversized temperature in a soft blue glow, readings set out beneath like the system browser.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property var stats: !root.has ? [] : [
        ["Humidity", root.cur.humidity + "%"],
        ["Wind", Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit() + " " + WeatherState.wind_dir_label(root.cur.wind_dir)],
        ["UV", root.cur.uv_index.toFixed(1)]
    ].concat(root.aqi >= 0 ? [["AQI", String(root.aqi)]] : [])

    spacing: 6

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: top_row.implicitHeight

        Shape {
            id: glow
            x: temp_text.x + temp_text.width / 2 - width / 2
            y: top_row.height / 2 - height / 2
            width: Math.max(120, temp_text.width * 2)
            height: top_row.height * 1.6
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: 0.5 * glow.width
                    centerY: 0.5 * glow.height
                    focalX: centerX
                    focalY: centerY
                    centerRadius: 0.5 * Math.min(glow.width, glow.height)
                    focalRadius: 0
                    GradientStop { position: 0; color: Qt.alpha(Theme.theme_primary, 0.55) }
                    GradientStop { position: 0.5; color: Qt.alpha(Theme.theme_primary, 0.14) }
                    GradientStop { position: 1; color: "transparent" }
                }
                PathRectangle { width: glow.width; height: glow.height }
            }
        }

        RowLayout {
            id: top_row
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 12

            Row {
                id: temp_text
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    text: root.has ? String(Math.round(root.cur.temp)) : "--"
                    color: root.has ? Theme.fg_strong : Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size * 3
                    font.weight: Font.ExtraLight
                }

                Text {
                    y: parent.height * 0.18
                    text: "°" + WeatherState.unit_symbol()
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.font_size
                    font.weight: Font.Light
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: root.has ? root.cur.cond : WeatherState.loading ? "Loading…" : "Unavailable"
                    color: root.has || WeatherState.loading ? Theme.fg_strong : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(1)
                    font.weight: Font.Light
                }

                Text {
                    visible: root.has
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Feels like " + (root.has ? Math.round(root.cur.feels) + "°" : "")
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    visible: WeatherState.location_name !== ""
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: WeatherState.location_name
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-4)
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.5
                }
            }
        }
    }

    Rectangle {
        visible: root.has
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.3; color: Qt.alpha(Theme.theme_primary_light, 0.45) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Flow {
        visible: root.has
        Layout.fillWidth: true
        spacing: 14

        Repeater {
            model: root.stats

            Row {
                id: stat
                required property var modelData
                spacing: 5

                Text {
                    anchors.baseline: value_text.baseline
                    text: stat.modelData[0]
                    color: Theme.theme_primary_light
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-5)
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Text {
                    id: value_text
                    text: stat.modelData[1]
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                }
            }
        }
    }

    Text {
        visible: WeatherState.stale || (!root.has && !WeatherState.loading && WeatherState.error !== "")
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: (WeatherState.stale ? "Stale data" : "Error") + (WeatherState.error ? ": " + WeatherState.error : "")
        color: Theme.warning
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }
}
