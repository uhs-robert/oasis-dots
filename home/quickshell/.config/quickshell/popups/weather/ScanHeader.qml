// home/quickshell/.config/quickshell/popups/weather/ScanHeader.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../../services"

// A Scan Visor logbook entry: the condition locked in scan brackets beside the reading and a generated analysis line.
RowLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property bool threat: WeatherState.alerts.length > 0
    readonly property int aqi: WeatherState.aq_has_data && WeatherState.aq_current ? WeatherState.aq_current.aqi : -1
    readonly property color lock_color: root.threat ? Theme.theme_label : Theme.theme_primary
    readonly property var compass: ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    readonly property var phrases: ({ partly_cloudy: "broken cloud layer", overcast: "overcast cloud layer", fog: "dense fog bank", drizzle: "light drizzle", rain: "active rainfall", heavy_rain: "heavy rainfall", freezing_rain: "freezing precipitation", snow: "snowfall", heavy_snow: "heavy snowfall", thunderstorm: "electrical storm activity" })

    readonly property string log_line: {
        if (!root.has) return WeatherState.loading ? "Acquiring atmospheric data." : "No atmospheric data" + (WeatherState.error ? ": " + WeatherState.error : "") + ".";
        const key = WeatherState.weather_color_keys[Math.round(root.cur.code)] || "";
        const phrase = root.phrases[key] || (key === "clear" ? (root.cur.is_day ? "clear sky, no cloud layer" : "clear night sky") : root.cur.cond.toLowerCase());
        const dir = root.compass[Math.round(((root.cur.wind_dir % 360) + 360) % 360 / 22.5) % 16];
        return "Atmospheric analysis: " + phrase + ". Humidity " + root.cur.humidity + "%. Wind " + Math.round(root.cur.wind_speed) + " " + WeatherState.wind_unit() + " " + dir + "." + (root.aqi >= 0 ? " Air quality index " + root.aqi + "." : "");
    }

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
            text: "Stale data" + (WeatherState.error ? ": " + WeatherState.error : "")
            color: Theme.warning
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }
}
