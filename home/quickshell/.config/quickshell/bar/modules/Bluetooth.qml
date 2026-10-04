// home/quickshell/.config/quickshell/bar/modules/Bluetooth.qml
import QtQuick
import Quickshell
import Quickshell.Bluetooth as QsBt
import "../../theme"
import "../../services"

BarModule {
    id: root
    module_name: "bluetooth"

    readonly property var adapter: QsBt.Bluetooth.defaultAdapter
    readonly property bool has_adapter: !!adapter
    readonly property bool blocked: has_adapter && adapter.state === QsBt.BluetoothAdapterState.Blocked
    readonly property var connected_devices: has_adapter ? adapter.devices.values.filter(d => d.connected) : []
    readonly property bool any_connected: connected_devices.length > 0

    shown: has_adapter
    implicitWidth: has_adapter ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    readonly property string glyph: root.blocked ? "󰂲" : "󰂯"

    readonly property color glyph_color: {
        if (!root.has_adapter || root.blocked || !root.adapter.enabled) return Theme.fg_dim;
        if (root.any_connected) return Theme.theme_primary;
        return Style.bar_fg;
    }

    tooltip_text: {
        if (!root.has_adapter) return "No adapter";
        const lines = [root.adapter.name];
        if (root.any_connected) {
            for (const d of root.connected_devices) lines.push(d.name);
        } else {
            lines.push("No devices connected");
        }
        return lines.join("\n");
    }

    Row {
        id: row
        spacing: 6

        Text {
            text: root.glyph
            color: root.glyph_color
            font.family: Style.bar_font_family
            style: Style.bar_text_style
            styleColor: Style.bar_glow_color
            font.pixelSize: Style.bar_glyph_size
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached(["blueman-manager"]);
            } else {
                root.toggle_popup();
            }
        }
    }
}
