// home/quickshell/.config/quickshell/popups/SystemPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "system"
    preferred_width: 340
    implicitHeight: content.implicitHeight + 24

    readonly property var stat_rows: {
        const list = [
            { kind: "cpu", label: "CPU", glyph: "" },
            { kind: "memory", label: "RAM", glyph: "" }
        ];
        if (SysStats.has_temp) list.push({ kind: "temperature", label: "Temp", glyph: "" });
        list.push({ kind: "btop", label: "Open btop", glyph: "" });
        return list;
    }

    property int selected: 0

    readonly property bool is_open: Popups.open_name === "system"
    onIs_openChanged: if (is_open) root.selected = 0

    function value_text(kind) {
        if (kind === "cpu") return SysStats.cpu_percent + "%";
        if (kind === "memory") return SysStats.mem_percent + "%";
        if (kind === "temperature") return SysStats.temp_c + "°C";
        return "";
    }

    function meter_value(kind) {
        if (kind === "cpu") return SysStats.cpu_percent / 100;
        if (kind === "memory") return SysStats.mem_percent / 100;
        if (kind === "temperature") return Math.min(1, SysStats.temp_c / 100);
        return 0;
    }

    function meter_hot(kind) {
        if (kind === "cpu" || kind === "memory") return SysStats[kind === "cpu" ? "cpu_percent" : "mem_percent"] >= 90;
        if (kind === "temperature") return SysStats.temp_c >= 80;
        return false;
    }

    function activate(index) {
        const row = root.stat_rows[index];
        if (!row) return;
        if (row.kind === "btop") {
            Quickshell.execDetached(["kitty", "btop"]);
            Popups.close();
        } else {
            SystemStat.set_override(Popups.open_screen_name, row.kind);
        }
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: main_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_J) {
                root.selected = Math.min(root.stat_rows.length - 1, root.selected + 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = Math.max(0, root.selected - 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate(root.selected);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Repeater {
                model: root.stat_rows

                Rectangle {
                    id: stat_row
                    required property var modelData
                    required property int index

                    readonly property bool is_btop: modelData.kind === "btop"

                    Layout.fillWidth: true
                    height: 26
                    radius: 4
                    clip: true
                    color: stat_row.index === root.selected ? Theme.bg_surface : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            text: stat_row.modelData.glyph
                            visible: !stat_row.is_btop
                            color: Theme.theme_primary
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size
                        }

                        Text {
                            Layout.preferredWidth: 40
                            text: stat_row.modelData.label
                            color: Theme.fg_core
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 1
                        }

                        Meter {
                            Layout.fillWidth: true
                            visible: !stat_row.is_btop
                            value: root.meter_value(stat_row.modelData.kind)
                            hot: root.meter_hot(stat_row.modelData.kind)
                        }

                        Text {
                            visible: !stat_row.is_btop
                            text: root.value_text(stat_row.modelData.kind)
                                + (stat_row.modelData.kind === "memory" ? " (" + SysStats.mem_used_gb.toFixed(1) + "/" + SysStats.mem_total_gb.toFixed(1) + "GB)" : "")
                            color: Theme.fg_muted
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = stat_row.index;
                            root.activate(stat_row.index);
                        }
                    }
                }
            }
        }
    }
}
