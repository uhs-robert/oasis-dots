// home/quickshell/.config/quickshell/bar/modules/Weather.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property bool shown: true
    visible: shown
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    readonly property var current: WeatherState.current
    readonly property bool has_data: WeatherState.has_data && !!current

    readonly property string tooltip_text: {
        if (!has_data) return WeatherState.failed ? "Weather unavailable: " + WeatherState.error : "Weather unavailable";
        const lines = [];
        for (const a of WeatherState.alerts) lines.push(a.event);
        lines.push(current.cond, "Feels like " + Math.round(current.feels) + "°" + WeatherState.unit_symbol());
        if (WeatherState.location_name) lines.push(WeatherState.location_name);
        if (WeatherState.stale) lines.push("Stale data" + (WeatherState.error ? ": " + WeatherState.error : ""));
        return lines.join("\n");
    }

    onIslandChanged: if (root.island) Popups.register_default("weather", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("weather", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignVCenter
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

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.has_data ? Math.round(root.current.temp) + "°" + WeatherState.unit_symbol() : WeatherState.failed ? "n/a" : "--°"
            color: root.has_data ? WeatherState.temp_color(root.current.temp) : WeatherState.failed ? Theme.warning : Theme.fg_dim
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size
            font.capitalization: Style.bar_capitalization
            font.letterSpacing: Style.bar_letter_spacing
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: WeatherState.stale
            text: "\u{f002a}"
            color: Theme.warning
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_font_size - 2
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text, "weather");
            else Tooltip.hide(root);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("weather", root.island, root.island_color, root.screen_name)
    }
}
