// home/quickshell/.config/quickshell/bar/modules/Hardware.qml
import QtQuick
import Quickshell
import Quickshell.Networking
import "../../theme"
import "../../services"

Row {
    id: root

    property bool compact: false
    spacing: 16

    readonly property bool dim: !Power.on_ac

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
    readonly property color temp_color: SysStats.temp_c >= 80 ? Theme.theme_label : Theme.theme_primary

    readonly property string net_tooltip: {
        if (root.wired_connected) return "Wired: " + root.wired_device.name;
        if (root.wifi_connected && root.active_wifi_network) {
            return root.active_wifi_network.name + " (" + Math.round(root.active_wifi_network.signalStrength * 100) + "%)";
        }
        if (root.wifi_device) return "Wi-Fi: " + root.wifi_device.name;
        return "Disconnected";
    }

    Item {
        visible: !root.compact
        width: cpu_row.implicitWidth
        height: cpu_row.implicitHeight
        opacity: root.dim ? 0.4 : 1

        Row {
            id: cpu_row
            spacing: 4

            Text {
                text: ""
                color: Theme.theme_primary
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }

            Text {
                text: SysStats.cpu_percent + "%"
                color: Theme.fg_core
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["kitty", "btop"])
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) Tooltip.show(parent, "CPU " + SysStats.cpu_percent + "%");
                else Tooltip.hide();
            }
        }
    }

    Item {
        visible: !root.compact
        width: mem_row.implicitWidth
        height: mem_row.implicitHeight
        opacity: root.dim ? 0.4 : 1

        Row {
            id: mem_row
            spacing: 4

            Text {
                text: ""
                color: Theme.theme_primary
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }

            Text {
                text: SysStats.mem_percent + "%"
                color: Theme.fg_core
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["kitty", "btop"])
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) Tooltip.show(parent, "RAM " + SysStats.mem_used_gb.toFixed(1) + " / " + SysStats.mem_total_gb.toFixed(1) + " GB");
                else Tooltip.hide();
            }
        }
    }

    Item {
        visible: !root.compact && SysStats.has_temp
        width: temp_row.implicitWidth
        height: temp_row.implicitHeight
        opacity: root.dim ? 0.4 : 1

        Row {
            id: temp_row
            spacing: 4

            Text {
                text: ""
                color: root.temp_color
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }

            Text {
                text: SysStats.temp_c + "°C"
                color: root.temp_color
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Quickshell.execDetached(["kitty", "btop"])
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) Tooltip.show(parent, "Temperature " + SysStats.temp_c + "°C");
                else Tooltip.hide();
            }
        }
    }

    Item {
        width: net_row.implicitWidth
        height: net_row.implicitHeight

        Row {
            id: net_row
            spacing: 4

            Text {
                text: root.net_glyph
                color: root.net_connected ? Theme.theme_primary : Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.font_size
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) Quickshell.execDetached(["nm-connection-editor"]);
                else Quickshell.execDetached(["kitty", "-e", "nmtui"]);
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) Tooltip.show(parent, root.net_tooltip);
                else Tooltip.hide();
            }
        }
    }
}
