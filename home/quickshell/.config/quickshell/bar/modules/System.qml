// home/quickshell/.config/quickshell/bar/modules/System.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property string stat: "cpu"
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property string effective_stat: SystemStat.stat_for(root.screen_name, root.stat)
    readonly property bool show_temp: root.effective_stat === "temperature"
    readonly property bool show_mem: root.effective_stat === "memory"
    readonly property bool dim: !Power.on_ac

    readonly property string glyph: root.show_temp ? "" : (root.show_mem ? "" : "")
    readonly property bool hot: root.show_temp && SysStats.temp_c >= 80
    readonly property color temp_color: root.hot ? Theme.theme_label : Theme.theme_primary
    readonly property color value_color: root.show_temp ? root.temp_color : Theme.fg_core

    readonly property string value_text: {
        if (root.show_temp) return SysStats.temp_c + "°C";
        if (root.show_mem) return SysStats.mem_percent + "%";
        return SysStats.cpu_percent + "%";
    }

    readonly property string tooltip_text: "CPU " + SysStats.cpu_percent + "%  RAM " + SysStats.mem_percent + "%"
        + (SysStats.has_temp ? "  Temp " + SysStats.temp_c + "°C" : "")

    readonly property bool shown: !root.compact && (!root.show_temp || SysStats.has_temp)
    visible: shown
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight
    opacity: root.dim ? 0.4 : 1

    onIslandChanged: if (root.island) Popups.register_default("system", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("system", root.screen_name, root)

    RowLayout {
        id: row
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.glyph
            color: root.show_temp ? root.value_color : Theme.theme_primary
            font.family: Theme.font_family
            font.pixelSize: Theme.glyph_size
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.value_text
            color: root.value_color
            font.family: Theme.font_family
            font.pixelSize: Theme.font_size
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("system", root.island, root.island_color, root.screen_name)
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text);
            else Tooltip.hide();
        }
    }
}
