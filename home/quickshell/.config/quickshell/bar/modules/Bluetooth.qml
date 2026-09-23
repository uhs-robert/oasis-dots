// home/quickshell/.config/quickshell/bar/modules/Bluetooth.qml
import QtQuick
import Quickshell
import Quickshell.Bluetooth as QsBt
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property var adapter: QsBt.Bluetooth.defaultAdapter
    readonly property bool has_adapter: !!adapter
    readonly property bool blocked: has_adapter && adapter.state === QsBt.BluetoothAdapterState.Blocked
    readonly property var connected_devices: has_adapter ? adapter.devices.values.filter(d => d.connected) : []
    readonly property bool any_connected: connected_devices.length > 0

    readonly property bool shown: has_adapter
    visible: shown
    implicitWidth: has_adapter ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    readonly property string glyph: root.blocked ? "󰂲" : "󰂯"

    readonly property color glyph_color: {
        if (!root.has_adapter || root.blocked || !root.adapter.enabled) return Theme.fg_dim;
        if (root.any_connected) return Theme.theme_primary;
        return Theme.fg_core;
    }

    readonly property string tooltip_text: {
        if (!root.has_adapter) return "No adapter";
        const lines = [root.adapter.name];
        if (root.any_connected) {
            for (const d of root.connected_devices) lines.push(d.name);
        } else {
            lines.push("No devices connected");
        }
        return lines.join("\n");
    }

    onIslandChanged: if (root.island) Popups.register_default("bluetooth", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("bluetooth", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    Row {
        id: row
        spacing: 6

        Text {
            text: root.glyph
            color: root.glyph_color
            font.family: Theme.font_family
            font.pixelSize: Theme.glyph_size
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached(["blueman-manager"]);
            } else {
                Popups.toggle("bluetooth", root.island, root.island_color, root.screen_name);
            }
        }
    }
}
