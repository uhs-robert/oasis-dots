import QtQuick
import QtQuick.Layouts
import qs.core
import qs.theme
import qs.features.bar
import qs.features.system

BarModule {
    id: root
    module_name: "system"
    hover_popup: true
    wash: false

    property string stat: "cpu"

    readonly property string effective_stat: SystemStat.stat_for(root.screen_name, root.stat)
    readonly property bool show_temp: root.effective_stat === "temperature"
    readonly property bool show_mem: root.effective_stat === "memory"
    readonly property bool dim: !PowerSource.on_ac

    readonly property string glyph: root.show_temp ? "" : (root.show_mem ? "" : "")
    readonly property bool hot: root.show_temp && SysStats.temp_c >= 80
    readonly property color temp_color: root.hot ? Theme.theme_label : Theme.theme_primary
    readonly property color value_color: root.show_temp ? root.temp_color : Style.bar_fg

    readonly property string value_text: {
        if (root.show_temp) return SysStats.temp_c + "°C";
        if (root.show_mem) return SysStats.mem_percent + "%";
        return SysStats.cpu_percent + "%";
    }

    tooltip_text: "CPU " + SysStats.cpu_percent + "%  RAM " + SysStats.mem_percent + "%"
        + (SysStats.has_temp ? "  Temp " + SysStats.temp_c + "°C" : "")

    shown: !root.compact && (!root.show_temp || SysStats.has_temp)
    implicitWidth: root.shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight
    opacity: root.dim ? 0.4 : 1

    readonly property string short_value_text: root.show_temp ? SysStats.temp_c + "°" : (root.show_mem ? SysStats.mem_percent : SysStats.cpu_percent) + ""

    ModuleRow {
        id: row
        vertical: root.vertical
        spacing: root.vertical ? 2 : 4

        BarIcon {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            name: "system"
            variant: root.show_temp ? "temp" : root.show_mem ? "mem" : "cpu"
            glyph: root.glyph
            tint: root.show_temp ? root.value_color : Theme.theme_primary
        }

        VerticalText {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            vertical: root.vertical
            cross: root.cross
            full_text: root.value_text
            short_text: root.short_value_text
            full_template: root.show_temp ? "100°C" : "100%"
            short_template: root.show_temp ? "100°" : "100"
            color: root.value_color
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggle_popup()
    }

}
