import QtQuick
import Quickshell
import Quickshell.Bluetooth as QsBt
import "../../theme"
import "../../services"
import "../../components/bar_icons"

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

        BarIcon {
            name: "bluetooth"
            variant: root.blocked ? "blocked" : !root.has_adapter || !root.adapter.enabled ? "off" : root.any_connected ? "connected" : "on"
            fallback_variant: "on"
            glyph: root.glyph
            tint: root.glyph_color
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
