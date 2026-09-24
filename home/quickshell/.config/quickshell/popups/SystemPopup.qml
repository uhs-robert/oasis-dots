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
    footer_hint: "b/Enter btop · q close"
    body_height: content.implicitHeight + 24

    readonly property var stat_rows: {
        const list = [
            { kind: "cpu", label: "CPU", glyph: "" },
            { kind: "memory", label: "RAM", glyph: "" }
        ];
        if (SysStats.has_temp) list.push({ kind: "temperature", label: "Temp", glyph: "" });
        list.push({ kind: "btop", label: "Open btop", glyph: "", key: "b" });
        return list;
    }

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

    function open_btop() {
        Quickshell.execDetached(["kitty", "btop"]);
        Popups.close();
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
            const plain = !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier));
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (plain && event.key === Qt.Key_B)) {
                root.open_btop();
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

                MenuRow {
                    id: stat_row
                    required property var modelData
                    required property int index

                    readonly property bool is_btop: modelData.kind === "btop"

                    Layout.fillWidth: true
                    height: Style.px(26)
                    clip: true
                    // The stats are read-only; btop is the popup's one action.
                    selected: stat_row.is_btop
                    key: stat_row.modelData.key || ""

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6 + stat_row.inset
                        anchors.rightMargin: 6 + stat_row.key_space
                        spacing: 8

                        Text {
                            text: stat_row.modelData.glyph
                            visible: !stat_row.is_btop
                            color: stat_row.fg(Theme.theme_primary)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size
                        }

                        Text {
                            Layout.preferredWidth: 40
                            text: stat_row.modelData.label
                            color: stat_row.fg(Theme.fg_core)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 1
                        }

                        Meter {
                            Layout.fillWidth: true
                            on_selection: stat_row.selected
                            visible: !stat_row.is_btop
                            value: root.meter_value(stat_row.modelData.kind)
                            hot: root.meter_hot(stat_row.modelData.kind)
                        }

                        Text {
                            visible: !stat_row.is_btop
                            text: root.value_text(stat_row.modelData.kind)
                                + (stat_row.modelData.kind === "memory" ? " (" + SysStats.mem_used_gb.toFixed(1) + "/" + SysStats.mem_total_gb.toFixed(1) + "GB)" : "")
                            color: stat_row.fg(Style.text_muted)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: stat_row.is_btop
                        onClicked: root.open_btop()
                    }
                }
            }
        }
    }
}
