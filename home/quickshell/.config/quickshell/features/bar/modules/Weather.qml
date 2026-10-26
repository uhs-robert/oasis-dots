import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.features.bar
import qs.features.weather

BarModule {
    id: root
    module_name: "weather"
    hover_popup: true

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    readonly property var current: WeatherState.current
    readonly property bool has_data: WeatherState.has_data && !!current

    tooltip_text: {
        if (!has_data) return WeatherState.failed ? "Weather unavailable: " + WeatherState.error : "Weather unavailable";
        const lines = [];
        for (const a of WeatherState.alerts) lines.push(a.event);
        lines.push(current.cond, "Feels like " + Math.round(current.feels) + "°" + WeatherState.unit_symbol());
        if (WeatherState.location_name) lines.push(WeatherState.location_name);
        if (WeatherState.stale) lines.push("Stale data" + (WeatherState.error ? ": " + WeatherState.error : ""));
        return lines.join("\n");
    }

    ModuleRow {
        id: row
        vertical: root.vertical
        spacing: root.vertical ? 2 : 4

        Item {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            implicitWidth: icon.visible ? icon.implicit_size : 0
            implicitHeight: icon.implicit_size

            Image {
                id: icon
                readonly property int implicit_size: Style.bar_glyph_size
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
                readonly property var crop: root.has_data ? WeatherState.icon_crop(root.current.code, root.current.is_day) : [0, 0, 128]
                // Scales the whole canvas so the art's crop square fills the slot; the transparent padding overhangs.
                readonly property real unit: implicit_size / crop[2]

                visible: root.has_data
                x: -crop[0] * unit
                y: -crop[1] * unit
                width: 128 * unit
                height: 128 * unit
                sourceSize.width: Math.ceil(width * dpr)
                sourceSize.height: Math.ceil(height * dpr)
                source: root.has_data ? WeatherState.icon_source(root.current.code, root.current.is_day) : ""
                smooth: true
                mipmap: true
            }
        }

        VerticalText {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            full_text: root.has_data ? Math.round(root.current.temp) + "°" + WeatherState.unit_symbol() : WeatherState.failed ? "n/a" : "--°"
            short_text: root.has_data ? Math.round(root.current.temp) + "°" : ""
            // Three digits are wider than "-88" in a proportional font; 104°F is real.
            full_template: "100°" + WeatherState.unit_symbol()
            short_template: "100°"
            color: root.has_data ? WeatherState.temp_color(root.current.temp) : WeatherState.failed ? Theme.warning : Theme.fg_dim
        }

        Text {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            visible: WeatherState.stale
            text: "\u{f002a}"
            color: Theme.warning
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size - 2
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggle_popup()
    }
}
