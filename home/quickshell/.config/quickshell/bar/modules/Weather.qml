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
        if (!has_data) return "Weather unavailable";
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
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    RowLayout {
        id: row
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: icon.width
            implicitHeight: icon.height

            Image {
                id: icon
                readonly property int implicit_size: root.compact ? 24 : 30
                readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1

                visible: root.has_data
                width: visible ? implicit_size : 0
                height: implicit_size
                sourceSize.width: Math.ceil(implicit_size * dpr)
                sourceSize.height: Math.ceil(implicit_size * dpr)
                source: root.has_data ? WeatherState.icon_source(root.current.code, root.current.is_day) : ""
                smooth: true
                mipmap: true
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.has_data ? Math.round(root.current.temp) + "°" + WeatherState.unit_symbol() : "--°"
            color: root.has_data ? WeatherState.temp_color(root.current.temp) : Theme.fg_dim
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: WeatherState.stale
            text: "\u{f002a}"
            color: Theme.warning
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size - 2
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("weather", root.island, root.island_color, root.screen_name)
    }
}
