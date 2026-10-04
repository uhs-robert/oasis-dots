// home/quickshell/.config/quickshell/popups/network/WifiHeader.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../components/ps1" as Ps1
import "../../components/ps2" as Ps2
import "../../components/goldeneye" as Goldeneye

ColumnLayout {
    id: root

    property var st
    property var wifi: null
    property var wired_device: null
    property string wifi_ipv4: ""
    property string wired_ipv4: ""
    property string link_state: ""
    property bool link_watch: false
    property bool link_wired: false
    property bool codec: false
    property bool ps2: false
    property string speed: ""
    property string status_text: ""
    property string no_wifi_reason: ""
    property bool wifi_enabled: false
    property bool toggle_selected: false

    signal toggle_clicked()

    spacing: 6

    Loader {
        active: root.ps2
        visible: active
        Layout.fillWidth: true
        sourceComponent: Column {
            spacing: 0

            Ps2.ConfigRow {
                width: parent.width
                label: "Connection"
                value: root.wifi ? root.wifi.name : root.link_wired ? "Wired: " + root.wired_device.name : "Not connected"
                value_color: root.wifi || root.link_wired ? Style.pal.fg_strong : root.st.text_muted
            }

            Ps2.ConfigRow {
                visible: !!root.wifi
                width: parent.width
                label: "Signal"
                value: root.wifi ? Math.round(root.wifi.signalStrength * 100) + "%" : ""
                level: root.wifi ? root.wifi.signalStrength : -1
            }

            Ps2.ConfigRow {
                visible: text_ip !== ""
                readonly property string text_ip: root.wifi ? root.wifi_ipv4 : root.link_wired ? root.wired_ipv4 : ""
                width: parent.width
                label: "IP Address"
                value: text_ip
            }
        }
    }

    Loader {
        active: root.link_watch
        visible: active
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        sourceComponent: Goldeneye.GaugeHeader {
            size: Style.px(100)
            value: root.wifi ? root.wifi.signalStrength : 0
            readout: root.wifi ? "" : "--"
            label: "SIGNAL"

            Goldeneye.ReadoutLine {
                Layout.fillWidth: true
                label: root.link_state
                alert: root.link_state === "NO UPLINK"
                text: root.wifi ? root.wifi.name : root.link_wired ? "Wired: " + root.wired_device.name : ""
            }

            Goldeneye.ReadoutLine {
                Layout.fillWidth: true
                visible: text !== ""
                label: "ADDRESS"
                text: root.wifi ? root.wifi_ipv4 : root.link_wired ? root.wired_ipv4 : ""
            }

            Goldeneye.ReadoutLine {
                Layout.fillWidth: true
                visible: text !== ""
                label: "SPEED"
                text: root.speed
            }
        }
    }

    ToggleRow {
        label: root.no_wifi_reason !== "" ? root.no_wifi_reason : root.link_watch ? "UPLINK" : "Wi-Fi"
        checked: root.no_wifi_reason === "" && root.wifi_enabled
        show_state: root.no_wifi_reason === ""
        selected: root.toggle_selected
        onToggled: root.toggle_clicked()
    }

    Loader {
        active: root.codec && !!root.wifi
        visible: active
        Layout.fillWidth: true
        sourceComponent: Ps1.CodecPanel {
            ssid: root.wifi ? root.wifi.name : ""
            strength: root.wifi ? root.wifi.signalStrength : 0
            detail: root.wifi_ipv4
        }
    }

    Text {
        visible: !root.codec && !!root.wifi && !root.ps2 && !root.link_watch
        text: root.wifi
            ? root.wifi.name + "  " + Math.round(root.wifi.signalStrength * 100) + "%"
                + (root.wifi_ipv4 ? "  " + root.wifi_ipv4 : "")
            : ""
        color: root.st.text_accent
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    Text {
        visible: root.link_wired && !root.ps2 && !root.link_watch
        text: root.wired_device ? "Wired: " + root.wired_device.name + (root.wired_ipv4 ? "  " + root.wired_ipv4 : "") : ""
        color: root.st.text_accent
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    Text {
        visible: root.status_text !== "" && !root.link_watch
        text: root.status_text
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
