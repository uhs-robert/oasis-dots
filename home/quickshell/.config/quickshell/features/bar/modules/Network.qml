import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.theme
import qs.features.bar

BarModule {
    id: root
    module_name: "network"
    wash: false

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

    readonly property string net_variant: {
        if (root.wired_connected) return "wired";
        if (root.wifi_connected && root.active_wifi_network) {
            const s = root.active_wifi_network.signalStrength;
            return "wifi_" + (s <= 0.2 ? 0 : s <= 0.4 ? 1 : s <= 0.6 ? 2 : s <= 0.8 ? 3 : 4);
        }
        return "offline";
    }

    readonly property bool net_connected: root.wired_connected || root.wifi_connected

    tooltip_text: {
        if (root.wired_connected) return "Wired: " + root.wired_device.name;
        if (root.wifi_connected && root.active_wifi_network) {
            return root.active_wifi_network.name + " (" + Math.round(root.active_wifi_network.signalStrength * 100) + "%)";
        }
        if (root.wifi_device) return "Wi-Fi: " + root.wifi_device.name;
        return "Disconnected";
    }

    implicitWidth: net_row.implicitWidth
    implicitHeight: net_row.implicitHeight

    ModuleRow {
        id: net_row
        vertical: root.vertical
        spacing: 4

        BarIcon {
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            ink_centre: root.vertical
            name: "network"
            fixed_slot: true
            variant: root.net_variant
            glyph: root.net_glyph
            tint: root.net_connected ? Theme.theme_primary : Theme.fg_dim
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) Quickshell.execDetached(["nm-connection-editor"]);
            else root.toggle_popup();
        }
    }

}
