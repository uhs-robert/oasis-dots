// home/quickshell/.config/quickshell/bar/modules/Network.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import "../../theme"
import "../../services"

Item {
    id: root

    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property var wifi_device: {
        for (const d of Networking.devices.values) if (d.type === DeviceType.Wifi) return d;
        return null;
    }

    readonly property var wired_device: {
        for (const d of Networking.devices.values) if (d.type === DeviceType.Wired) return d;
        return null;
    }

    readonly property var active_wifi_network: {
        if (!root.wifi_device) return null;
        for (const n of root.wifi_device.networks.values) if (n.connected) return n;
        return null;
    }

    readonly property bool wired_connected: root.wired_device ? root.wired_device.connected : false
    readonly property bool wifi_connected: root.wifi_device ? root.wifi_device.connected : false

    readonly property var wifi_glyphs: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]

    readonly property string net_glyph: {
        if (root.wired_connected) return "󰈀";
        if (root.wifi_connected && root.active_wifi_network) {
            const s = root.active_wifi_network.signalStrength;
            if (s <= 0.2) return root.wifi_glyphs[0];
            if (s <= 0.4) return root.wifi_glyphs[1];
            if (s <= 0.6) return root.wifi_glyphs[2];
            if (s <= 0.8) return root.wifi_glyphs[3];
            return root.wifi_glyphs[4];
        }
        return "󰤭";
    }

    readonly property bool net_connected: root.wired_connected || root.wifi_connected

    readonly property string net_tooltip: {
        if (root.wired_connected) return "Wired: " + root.wired_device.name;
        if (root.wifi_connected && root.active_wifi_network) {
            return root.active_wifi_network.name + " (" + Math.round(root.active_wifi_network.signalStrength * 100) + "%)";
        }
        if (root.wifi_device) return "Wi-Fi: " + root.wifi_device.name;
        return "Disconnected";
    }

    implicitWidth: net_row.implicitWidth
    implicitHeight: net_row.implicitHeight

    onIslandChanged: if (root.island) Popups.register_default("network", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("network", root.screen_name, root)

    RowLayout {
        id: net_row
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.net_glyph
            color: root.net_connected ? Theme.theme_primary : Theme.fg_dim
            font.family: Theme.font_family
            font.pixelSize: Theme.glyph_size
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) Quickshell.execDetached(["nm-connection-editor"]);
            else Popups.toggle("network", root.island, root.island_color, root.screen_name);
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) Tooltip.show(parent, root.net_tooltip);
            else Tooltip.hide();
        }
    }
}
