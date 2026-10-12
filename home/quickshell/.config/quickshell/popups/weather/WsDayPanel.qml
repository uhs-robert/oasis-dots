// home/quickshell/.config/quickshell/popups/weather/WsDayPanel.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// One WeatherStar 4000 "Extended Forecast" day: name, icon, short condition, two readings and rain chance.
// sub picks the readings: 0 Lo and Hi, 1 wind speed and gusts under the direction, 2 UV under its band, 3 sunshine hours.
Item {
    id: root

    property var day: ({})
    property bool selected: false
    property int sub: 0
    readonly property var short_conds: ({ 0: "Sunny", 1: "Mostly Sunny", 2: "Partly Cloudy", 3: "Cloudy", 45: "Fog", 48: "Fog", 51: "Drizzle", 53: "Drizzle", 55: "Drizzle", 56: "Frz Drizzle", 57: "Frz Drizzle", 61: "Light Rain", 63: "Rain", 65: "Heavy Rain", 66: "Frz Rain", 67: "Frz Rain", 71: "Light Snow", 73: "Snow", 75: "Heavy Snow", 77: "Flurries", 80: "Showers", 81: "Showers", 82: "Heavy Showers", 85: "Snow Showers", 86: "Snow Showers", 95: "T'Storms", 96: "T'Storms", 99: "T'Storms" })
    readonly property int small_px: Style.fs(-6)

    readonly property var readings: {
        const d = root.day;
        if (d.min === undefined) return [];
        if (root.sub === 1) return [["Wind", Theme.theme_primary_light, Math.round(d.wind_speed_max)], ["Gust", Theme.theme_secondary, Math.round(d.wind_gusts_max)]];
        if (root.sub === 2) return [["UV", Theme.theme_primary_light, d.uv_max.toFixed(1)]];
        if (root.sub === 3) return [["Sun", Theme.theme_primary_light, d.sunshine_hours.toFixed(1) + "h"]];
        return [["Lo", Theme.theme_primary_light, Math.round(d.min)], ["Hi", Theme.theme_secondary, Math.round(d.max)]];
    }
    readonly property string note: {
        if (root.day.min === undefined) return "";
        if (root.sub === 1) return "From " + WeatherState.wind_dir_label(root.day.wind_dir);
        if (root.sub === 2) return WeatherState.uv_band(root.day.uv_max).label;
        return "";
    }

    WsPanel {
        anchors.fill: parent
        lit: root.selected
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 5
        anchors.topMargin: 6
        spacing: 2

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.day.weekday || ""
            color: Theme.theme_secondary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Item {
            Layout.fillHeight: true
        }

        Image {
            readonly property real size: Math.max(24, Math.min(56, root.width - 12))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: size
            Layout.preferredHeight: size
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            sourceSize.width: Math.ceil(112 * dpr)
            sourceSize.height: Math.ceil(112 * dpr)
            source: root.day.code !== undefined ? WeatherState.icon_source(root.day.code, true) : ""
            smooth: true
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.ceil(2 * lh.lineSpacing) + 2
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.short_conds[root.day.code] || root.day.cond || ""
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: root.small_px
            style: Text.Outline
            styleColor: Theme.bg_shadow

            FontMetrics {
                id: lh
                font.family: Style.font_family
                font.pixelSize: root.small_px
            }
        }

        Item {
            Layout.fillHeight: true
        }

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1, root.readings.length)
            columnSpacing: 2
            rowSpacing: 0

            Repeater {
                model: root.readings

                Text {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData[0]
                    color: modelData[1]
                    font.family: Style.font_family
                    font.pixelSize: root.small_px
                    style: Text.Outline
                    styleColor: Theme.bg_shadow
                }
            }

            Repeater {
                model: root.readings

                Text {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData[2]
                    color: Theme.fg_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                    style: Text.Outline
                    styleColor: Theme.bg_shadow
                }
            }
        }

        Text {
            visible: root.note !== ""
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.note
            color: Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: root.small_px
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: "Precip"
            color: Theme.theme_primary_light
            font.family: Style.font_family
            font.pixelSize: root.small_px
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            horizontalAlignment: Text.AlignHCenter
            text: (root.day.pop || 0) + "%"
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }
    }
}
