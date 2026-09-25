// home/quickshell/.config/quickshell/components/oasis/OasisHeader.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "../../services"

// Current conditions over the desert: a light temperature numeral, the condition lines, and a small night or day scene.
RowLayout {
    id: root

    readonly property var cur: WeatherState.current
    readonly property color sand: Theme.theme_secondary
    readonly property string kind: WeatherState.has_data ? WeatherState.weather_color_keys[Math.round(root.cur.code)] || "clear" : "clear"
    readonly property bool is_day: WeatherState.has_data && !!root.cur.is_day
    readonly property bool cloudy: root.kind !== "clear"
    readonly property bool wet: ["drizzle", "rain", "heavy_rain", "freezing_rain", "thunderstorm"].indexOf(root.kind) >= 0
    readonly property bool snowy: root.kind === "snow" || root.kind === "heavy_snow"

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    spacing: 14

    Row {
        Layout.alignment: Qt.AlignBottom
        spacing: 1

        Text {
            id: numeral
            text: WeatherState.has_data ? String(Math.round(root.cur.temp)) : "--"
            color: Theme.fg_strong
            font.family: Style.number_font
            font.pixelSize: Style.px(52)
            font.weight: Font.Light
            font.letterSpacing: -1.5
            font.features: { "tnum": 1 }
        }

        Text {
            y: numeral.y + Math.round(numeral.height * 0.2)
            text: "°" + WeatherState.unit_symbol()
            color: Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(1)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignBottom
        Layout.bottomMargin: 6
        spacing: 2

        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: WeatherState.has_data ? root.cur.cond : WeatherState.loading ? "Loading…" : "Unavailable"
            color: WeatherState.has_data || WeatherState.loading ? Theme.fg_strong : Theme.warning
            font.family: Style.font_family
            font.pixelSize: Style.fs(1)
            font.weight: Font.DemiBold
        }

        Text {
            Layout.fillWidth: true
            visible: WeatherState.has_data
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: "Feels like <font color=\"" + Style.text_dim + "\">" + (WeatherState.has_data ? root.fmt_temp(root.cur.feels) : "") + "</font>"
            color: Theme.fg_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Text {
            Layout.fillWidth: true
            visible: WeatherState.location_name !== ""
            elide: Text.ElideRight
            text: "\u{f041}  " + WeatherState.location_name
            color: Theme.fg_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Text {
            Layout.fillWidth: true
            visible: WeatherState.stale || (!WeatherState.has_data && !WeatherState.loading && WeatherState.error !== "")
            elide: Text.ElideRight
            text: (WeatherState.stale ? "Stale data" : "Error") + (WeatherState.error ? ": " + WeatherState.error : "")
            color: Theme.warning
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }
    }

    Shape {
        Layout.preferredWidth: 84
        Layout.preferredHeight: 56
        Layout.alignment: Qt.AlignVCenter
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Theme.theme_primary_light
            PathSvg { path: "M11.2 10a.8 .8 0 1 0 1.6 0a.8 .8 0 1 0 -1.6 0M75.3 36a.7 .7 0 1 0 1.4 0a.7 .7 0 1 0 -1.4 0M44.4 3a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0 -1.2 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(Theme.fg_strong, 0.6)
            PathSvg { path: "M29.4 5a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0 -1.2 0M3.4 30a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0 -1.2 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(root.sand, 0.08)
            PathSvg { path: "M0 48Q20 42 42 46T84 45V56H0Z" }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.sand, 0.5)
            fillColor: "transparent"
            PathSvg { path: "M2 44H82" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.alpha(root.sand, root.is_day ? 0.16 : 0.1)
            PathSvg { path: "M49 16a11 11 0 1 0 22 0a11 11 0 1 0 -22 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.is_day ? root.sand : "transparent"
            PathSvg { path: "M53 16a7 7 0 1 0 14 0a7 7 0 1 0 -14 0" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.is_day ? "transparent" : Qt.tint(root.sand, Qt.alpha(Theme.fg_strong, 0.35))
            PathSvg { path: "M64.55 8.12A9.1 9.1 0 1 0 64.55 23.88A7.88 7.88 0 0 1 64.55 8.12Z" }
        }

        ShapePath {
            strokeWidth: root.cloudy ? 0.9 : -1
            strokeColor: root.cloudy ? Theme.theme_primary_light : "transparent"
            fillColor: root.cloudy ? Qt.tint(Theme.bg_mantle, Qt.alpha(Theme.theme_primary_light, 0.3)) : "transparent"
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M28 45H48.4A8 8 0 0 0 49.4 29.06A12 12 0 0 0 26.6 30.6A7.2 7.2 0 0 0 28 45Z" }
        }

        ShapePath {
            strokeWidth: root.wet ? 1.2 : -1
            strokeColor: root.wet ? Theme.info : "transparent"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M31 48L29.4 52M37 48L35.4 52M43 48L41.4 52" }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.snowy ? Theme.fg_strong : "transparent"
            PathSvg { path: "M29 50a1 1 0 1 0 2 0a1 1 0 1 0 -2 0M36 52a1 1 0 1 0 2 0a1 1 0 1 0 -2 0M43 50a1 1 0 1 0 2 0a1 1 0 1 0 -2 0" }
        }

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.info, 0.55)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M56 48H68M61 51H72" }
        }
    }
}
