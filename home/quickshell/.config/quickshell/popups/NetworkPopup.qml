// home/quickshell/.config/quickshell/popups/NetworkPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "network"
    preferred_width: 320
    key_help: root.password_mode || root.dns_edit_mode ? "" : root.forget_confirm ? "y forget · n keep" : root.on_details ? root.details_help : root.list_help
    footer_hint: root.key_help
    sub_views: ["Networks", "Details"]

    // The list fits its rows and only scrolls past most of the screen height.
    readonly property real max_list_height: (root.screen ? root.screen.height : 1080) * 0.6
    body_height: content.implicitHeight + 24
    jumps_enabled: !root.password_mode && !root.forget_confirm && !root.dns_edit_mode

    readonly property string list_help: "Tab details · j/k move · gg/G first/last · Enter connect · f forget · t toggle · r scan · q close"
    readonly property string details_help: root.profile
        ? "Tab/Esc list · j/k move · gg/G first/last · t/Enter toggle · Enter edit DNS · r refresh · q close"
        : "Tab/Esc list · r refresh · q close"

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

    readonly property var wifi_glyphs: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]

    function signal_glyph(strength) {
        if (strength <= 0.2) return root.wifi_glyphs[0];
        if (strength <= 0.4) return root.wifi_glyphs[1];
        if (strength <= 0.6) return root.wifi_glyphs[2];
        if (strength <= 0.8) return root.wifi_glyphs[3];
        return root.wifi_glyphs[4];
    }

    // Dedupe scan results by SSID, keeping the strongest signal, sorted best-first.
    function build_network_list() {
        if (!root.wifi_device) return [];
        const by_name = {};
        for (const n of root.wifi_device.networks.values) {
            if (!by_name[n.name] || n.signalStrength > by_name[n.name].signalStrength) by_name[n.name] = n;
        }
        return Object.values(by_name).sort((a, b) => b.signalStrength - a.signalStrength);
    }

    readonly property var wifi_networks: root.build_network_list()
    readonly property var nav_rows: root.wifi_networks.concat([{ advanced: true }])

    // -1 is the Wi-Fi switch above the list.
    property int selected: 0
    property bool forget_confirm: false
    // Captured when f is pressed: rescans reorder the list while the prompt is up.
    property var forget_target: null
    property bool password_mode: false
    property var password_target: null
    property string password_text: ""
    property bool password_visible: false
    property string status_text: ""
    property string wifi_ipv4: ""
    property string wired_ipv4: ""

    readonly property bool on_details: root.current_sub === 1
    // Captured on entering Details: rescans reorder the list underneath it.
    property var details_target: null
    property string details_ssid: ""
    property var details: ({})
    property bool details_stale: false
    readonly property var profile: root.details.profile || null
    readonly property bool details_connected: !!root.details_target && root.details_target.connected
    readonly property int setting_count: root.profile ? 3 : 0
    property int setting_selected: 0
    property string setting_error: ""
    property bool dns_edit_mode: false
    property string dns_text: ""
    readonly property var metered_labels: ({ yes: "On", no: "Off", unknown: "Auto" })
    readonly property var metered_next: ({ unknown: "yes", yes: "no", no: "unknown" })

    readonly property bool is_open: Popups.open_name === "network"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        root.forget_confirm = false;
        root.password_mode = false;
        root.dns_edit_mode = false;
        root.current_sub = 0;
        root.status_text = "";
        root.start_scan();
        root.refresh_ip();
    }
    onNav_rowsChanged: if (root.selected >= root.nav_rows.length) root.selected = Math.max(0, root.nav_rows.length - 1);
    search_enabled: !root.password_mode && !root.forget_confirm && !root.on_details && !root.dns_edit_mode
    search_rows: root.nav_rows.map(r => r.advanced ? "Advanced…" : r.name)
    search_cursor: root.selected
    onSearch_select: index => {
        root.selected = index;
        network_list.positionViewAtIndex(index, ListView.Contain);
    }
    onJump_first: {
        if (root.on_details) root.setting_selected = 0;
        else root.selected = -1;
    }
    onJump_last: {
        if (root.on_details) {
            root.setting_selected = Math.max(0, root.setting_count - 1);
            return;
        }
        root.selected = Math.max(-1, root.nav_rows.length - 1);
        network_list.positionViewAtIndex(root.selected, ListView.Contain);
    }
    onCurrent_subChanged: {
        root.forget_confirm = false;
        root.dns_edit_mode = false;
        if (root.on_details) root.open_details();
    }
    // A field taking focus leaves `content` without it once the field hides.
    onDns_edit_modeChanged: if (!root.dns_edit_mode) content.forceActiveFocus()
    onPassword_modeChanged: if (!root.password_mode) content.forceActiveFocus()
    onSetting_countChanged: if (root.setting_selected >= root.setting_count) root.setting_selected = 0

    function open_details() {
        const row = root.nav_rows[root.selected];
        root.details_target = row && !row.advanced ? row : null;
        root.details_ssid = root.details_target ? root.details_target.name : "";
        root.details = {};
        root.setting_selected = 0;
        root.setting_error = "";
        root.fetch_details();
    }

    readonly property string details_script: "nmcli -t -e no -m multiline -f IN-USE,SSID,BSSID,BAND,CHAN,FREQ,SIGNAL,SECURITY device wifi list ifname \"$1\" --rescan no; "
        + "echo @@DEV; nmcli -t -e no -f GENERAL.HWADDR,GENERAL.CON-UUID,CAPABILITIES.SPEED,IP4,IP6 device show \"$1\"; "
        + "echo @@SAVED; u=$(nmcli -t -f UUID,TYPE connection show | sed -n 's/:802-11-wireless$//p'); "
        + "[ -z \"$u\" ] || nmcli -t -e no -f connection.uuid,connection.id,connection.timestamp,connection.autoconnect,connection.metered,ipv4.dns,802-11-wireless.ssid connection show $u"

    // Errors go to stdout so one collector sees them; reapply runs only for the active profile and keeps the link up.
    readonly property string modify_script: "u=$1; r=$2; shift 2; "
        + "out=$(nmcli connection modify uuid \"$u\" \"$@\" 2>&1) || { printf '%s' \"${out:-nmcli modify failed}\"; exit 1; }; "
        + "[ \"$r\" = 1 ] || exit 0; "
        + "d=$(nmcli -g GENERAL.DEVICES connection show uuid \"$u\"); "
        + "out=$(nmcli device reapply \"$d\" 2>&1) || { printf '%s' \"${out:-nmcli reapply failed}\"; exit 1; }"

    function fetch_details() {
        if (!root.is_open || !root.on_details || !root.details_target || !root.wifi_device || !root.wifi_device.name) return;
        if (details_proc.running) {
            root.details_stale = true;
            return;
        }
        details_proc.command = ["sh", "-c", root.details_script, "sh", root.wifi_device.name];
        details_proc.running = true;
    }

    function parse_details(text) {
        const aps = [];
        const saved = [];
        const dev = { ipv4: [], ipv6: [], dns: [], gateway: "", mac: "", speed: "", con_uuid: "" };
        let section = "aps";
        for (const line of text.split("\n")) {
            if (line === "@@DEV" || line === "@@SAVED") {
                section = line;
                continue;
            }
            const i = line.indexOf(":");
            if (i < 0) continue;
            const key = line.slice(0, i).replace(/\[\d+\]$/, "");
            const value = line.slice(i + 1);
            if (section === "aps") {
                if (key === "IN-USE") aps.push({ in_use: value === "*" });
                else if (aps.length > 0) aps[aps.length - 1][key] = value;
            } else if (section === "@@DEV") {
                if (key === "IP4.ADDRESS") dev.ipv4.push(value);
                else if (key === "IP6.ADDRESS" && !value.startsWith("fe80:")) dev.ipv6.push(value);
                else if (key === "IP4.DNS" || key === "IP6.DNS") dev.dns.push(value);
                else if (key === "IP4.GATEWAY") dev.gateway = value;
                else if (key === "GENERAL.HWADDR") dev.mac = value;
                else if (key === "GENERAL.CON-UUID") dev.con_uuid = value;
                else if (key === "CAPABILITIES.SPEED") dev.speed = value;
            } else if (key === "connection.uuid") {
                saved.push({ uuid: value });
            } else if (saved.length > 0) {
                saved[saved.length - 1][key] = value;
            }
        }

        const ssid = root.details_ssid;
        const matches = aps.filter(a => a.SSID === ssid).sort((a, b) => Number(b.SIGNAL) - Number(a.SIGNAL));
        const ap = matches.find(a => a.in_use) || matches[0] || null;
        const profiles = saved.filter(c => c["802-11-wireless.ssid"] === ssid).sort((a, b) => Number(b["connection.timestamp"]) - Number(a["connection.timestamp"]));
        const p = profiles.find(c => c.uuid === dev.con_uuid) || profiles[0] || null;
        root.details = {
            loaded: true,
            ap: ap,
            dev: dev,
            profile: p ? {
                uuid: p.uuid,
                name: p["connection.id"] || "",
                active: p.uuid === dev.con_uuid,
                autoconnect: p["connection.autoconnect"] === "yes",
                metered: p["connection.metered"] || "unknown",
                dns: (p["ipv4.dns"] || "").split(",").map(d => d.trim()).filter(d => d !== "")
            } : null
        };
    }

    readonly property var detail_rows: {
        const t = root.details_target;
        if (!t) return [];
        const ap = root.details.ap || null;
        const dev = root.details.dev || null;
        const rows = [{ label: "SSID", value: root.details_ssid }];
        const security = ap ? (ap.SECURITY && ap.SECURITY !== "--" ? ap.SECURITY : "Open") : WifiSecurityType.toString(t.security);
        rows.push({ label: "Security", value: security });
        rows.push({ label: "Signal", value: (ap ? ap.SIGNAL : Math.round(t.signalStrength * 100)) + "%" });
        if (ap) {
            if (ap.BAND) rows.push({ label: "Band", value: ap.BAND });
            if (ap.CHAN) rows.push({ label: "Channel", value: ap.CHAN + (ap.FREQ ? " (" + ap.FREQ + ")" : "") });
            if (ap.BSSID) rows.push({ label: "BSSID", value: ap.BSSID });
        }
        if (root.profile && root.profile.name !== root.details_ssid) rows.push({ label: "Profile", value: root.profile.name });
        if (root.details_connected && dev && dev.con_uuid !== "") {
            if (dev.ipv4.length > 0) rows.push({ label: "IPv4", value: dev.ipv4.join("\n"), wrap: true });
            if (dev.gateway) rows.push({ label: "Gateway", value: dev.gateway });
            if (dev.dns.length > 0) rows.push({ label: "DNS", value: dev.dns.join("\n"), wrap: true });
            if (dev.ipv6.length > 0) rows.push({ label: "IPv6", value: dev.ipv6.join("\n"), wrap: true });
            if (dev.mac) rows.push({ label: "MAC", value: dev.mac });
            if (dev.speed && dev.speed !== "unknown") rows.push({ label: "Speed", value: dev.speed });
        }
        return rows;
    }

    function run_modify(props, reapply) {
        if (!root.profile || modify_proc.running) return;
        root.setting_error = "";
        modify_proc.command = ["sh", "-c", root.modify_script, "sh", root.profile.uuid, reapply ? "1" : "0"].concat(props);
        modify_proc.running = true;
    }

    function activate_setting(i) {
        if (!root.profile) return;
        root.setting_selected = i;
        if (i === 0) root.run_modify(["connection.autoconnect", root.profile.autoconnect ? "no" : "yes"], false);
        else if (i === 1) root.run_modify(["connection.metered", root.metered_next[root.profile.metered] || "unknown"], false);
        else if (i === 2) root.start_dns_edit();
    }

    function start_dns_edit() {
        if (!root.profile || modify_proc.running) return;
        root.dns_text = root.profile.dns.join(" ");
        root.setting_error = "";
        root.dns_edit_mode = true;
        dns_input.forceActiveFocus();
    }

    function finish_dns_edit(apply) {
        root.dns_edit_mode = false;
        if (!apply) return;
        const list = root.dns_text.split(/[\s,;]+/).filter(d => d !== "");
        root.run_modify(["ipv4.dns", list.join(","), "ipv4.ignore-auto-dns", list.length > 0 ? "yes" : "no"], root.profile && root.profile.active);
    }

    function handle_details_key(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
            root.current_sub = 0;
        } else if (event.key === Qt.Key_R) {
            root.fetch_details();
        } else if (root.setting_count > 0 && event.key === Qt.Key_J) {
            root.setting_selected = root.wrap_index(root.setting_selected, 1, 0, root.setting_count);
        } else if (root.setting_count > 0 && event.key === Qt.Key_K) {
            root.setting_selected = root.wrap_index(root.setting_selected, -1, 0, root.setting_count);
        } else if (event.key === Qt.Key_T && root.setting_selected < 2) {
            root.activate_setting(root.setting_selected);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate_setting(root.setting_selected);
        } else {
            return;
        }
        event.accepted = true;
    }

    Process {
        id: details_proc
        onExited: if (root.details_stale) {
            root.details_stale = false;
            root.fetch_details();
        }
        stdout: StdioCollector {
            onStreamFinished: root.parse_details(text)
        }
    }

    Process {
        id: modify_proc
        stdout: StdioCollector {
            onStreamFinished: {
                root.setting_error = text.trim().replace(/^Error: /, "");
                root.fetch_details();
            }
        }
    }

    Connections {
        target: root.details_target
        enabled: root.on_details
        function onConnectedChanged() {
            root.fetch_details();
        }
        function onKnownChanged() {
            root.fetch_details();
        }
    }

    function start_scan() {
        if (root.wifi_device) root.wifi_device.scannerEnabled = true;
        scan_timer.restart();
    }

    // Quickshell.Networking has no IPv4 property, so read it once via `ip` instead of the MAC/BSSID.
    function refresh_ip() {
        root.wifi_ipv4 = "";
        root.wired_ipv4 = "";
        if (root.active_wifi_network && root.wifi_device && root.wifi_device.name) {
            wifi_ip_proc.command = ["ip", "-4", "-o", "addr", "show", "dev", root.wifi_device.name];
            wifi_ip_proc.running = true;
        }
        if (root.wired_device && root.wired_device.connected && root.wired_device.name) {
            wired_ip_proc.command = ["ip", "-4", "-o", "addr", "show", "dev", root.wired_device.name];
            wired_ip_proc.running = true;
        }
    }

    Process {
        id: wifi_ip_proc
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
                root.wifi_ipv4 = m ? m[1] : "";
            }
        }
    }

    Process {
        id: wired_ip_proc
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
                root.wired_ipv4 = m ? m[1] : "";
            }
        }
    }

    // Scanning burns radio power; only run it briefly around an explicit open/rescan.
    Timer {
        id: scan_timer
        interval: 8000
        onTriggered: if (root.wifi_device) root.wifi_device.scannerEnabled = false
    }

    Connections {
        target: root.password_target
        function onConnectionFailed(reason) {
            root.status_text = ConnectionFailReason.toString(reason);
        }
        function onConnectedChanged() {
            if (root.password_target && root.password_target.connected) {
                root.status_text = "Connected";
                root.password_mode = false;
            }
        }
    }

    function connect_to(network) {
        if (!network) return;
        if (network.connected) {
            network.disconnect();
            return;
        }
        if (network.known || network.security === WifiSecurityType.Open) {
            root.status_text = "Connecting…";
            network.connect();
        } else {
            root.password_target = network;
            root.password_mode = true;
            root.password_text = "";
            root.password_visible = false;
            root.status_text = "";
        }
    }

    function open_advanced() {
        Popups.close();
        Quickshell.execDetached(["env", "-u", "TMUX", "-u", "TMUX_PANE", "sh", "-c", "t=\"$HOME/.config/hypr/scripts/term\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e nmtui"]);
    }

    function toggle_wifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled;
    }

    function submit_password() {
        if (!root.password_target) return;
        root.status_text = "Connecting…";
        root.password_target.connectWithPsk(root.password_text);
        root.password_text = "";
    }

    function cancel_password() {
        root.password_mode = false;
        root.password_text = "";
        root.password_target = null;
        root.status_text = "";
    }

    Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        implicitHeight: root.password_mode ? password_column.implicitHeight : view_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            if (root.password_mode || root.dns_edit_mode) return;

            if (root.forget_confirm) {
                if (root.is_help_key(event) || event.key === Qt.Key_Q) return;
                if (event.key === Qt.Key_Y) {
                    if (root.forget_target) root.forget_target.forget();
                    root.forget_confirm = false;
                    root.forget_target = null;
                } else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape) {
                    root.forget_confirm = false;
                    root.forget_target = null;
                }
                event.accepted = true;
                return;
            }

            if (root.on_details) {
                root.handle_details_key(event);
                return;
            }

            const row = root.nav_rows[root.selected];
            if (event.key === Qt.Key_J) {
                root.selected = root.wrap_index(root.selected, 1, -1, root.nav_rows.length + 1);
                if (root.selected >= 0) network_list.positionViewAtIndex(root.selected, ListView.Contain);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, -1, root.nav_rows.length + 1);
                if (root.selected >= 0) network_list.positionViewAtIndex(root.selected, ListView.Contain);
                event.accepted = true;
            } else if (event.key === Qt.Key_T) {
                root.toggle_wifi();
                event.accepted = true;
            } else if (event.key === Qt.Key_R) {
                root.start_scan();
                event.accepted = true;
            } else if (event.key === Qt.Key_F && row && !row.advanced && row.known) {
                root.forget_target = row;
                root.forget_confirm = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.selected === -1) root.toggle_wifi();
                else if (row && row.advanced) root.open_advanced();
                else root.connect_to(row);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: view_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8
            visible: !root.password_mode

            ColumnLayout {
                id: main_column
                Layout.fillWidth: true
                spacing: 6
                visible: !root.on_details

                ToggleRow {
                    label: "Wi-Fi"
                    checked: Networking.wifiEnabled
                    selected: root.selected === -1
                    onToggled: {
                        root.selected = -1;
                        root.forget_confirm = false;
                        root.toggle_wifi();
                    }
                }

                Text {
                    visible: !!root.active_wifi_network
                    text: root.active_wifi_network
                        ? root.active_wifi_network.name + "  " + Math.round(root.active_wifi_network.signalStrength * 100) + "%"
                            + (root.wifi_ipv4 ? "  " + root.wifi_ipv4 : "")
                        : ""
                    color: root.st.text_accent
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 2
                }

                Text {
                    visible: !!root.wired_device && root.wired_device.connected
                    text: root.wired_device ? "Wired: " + root.wired_device.name + (root.wired_ipv4 ? "  " + root.wired_ipv4 : "") : ""
                    color: root.st.text_accent
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 2
                }

                Text {
                    visible: root.status_text !== ""
                    text: root.status_text
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 3
                }

                Text {
                    visible: root.forget_confirm
                    text: "Forget " + (root.forget_target ? root.forget_target.name : "this network") + "? y/n"
                    color: Theme.error
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 2
                }

                ListView {
                    id: network_list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, root.max_list_height)
                    clip: true
                    spacing: 4
                    model: root.nav_rows
                    currentIndex: root.selected

                    delegate: MenuRow {
                        id: net_row
                        required property var modelData
                        required property int index

                        readonly property bool is_advanced: !!net_row.modelData.advanced

                        width: network_list.width
                        height: Style.px(24)
                        selected: net_row.index === root.selected

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6 + net_row.inset
                            anchors.rightMargin: 6 + net_row.key_space
                            spacing: 6

                            Text {
                                visible: !net_row.is_advanced
                                text: root.signal_glyph(net_row.modelData.signalStrength || 0)
                                color: net_row.fg(net_row.modelData.connected ? root.st.text_primary : root.st.text_fg)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size - 1
                            }

                            RowLabel {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                label: net_row.is_advanced ? "Advanced…" : net_row.modelData.name
                                color: net_row.fg(net_row.modelData.connected ? root.st.text_accent : root.st.text_fg)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size - 1
                            }

                            Text {
                                visible: !net_row.is_advanced && net_row.modelData.security !== WifiSecurityType.Open
                                text: ""
                                color: net_row.fg(root.st.text_muted)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size - 2
                            }

                            Text {
                                visible: !net_row.is_advanced && net_row.modelData.known
                                text: ""
                                color: net_row.fg(root.st.text_muted)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.font_size - 2
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selected = net_row.index;
                                root.forget_confirm = false;
                                if (net_row.is_advanced) root.open_advanced();
                                else root.connect_to(net_row.modelData);
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: details_column
                Layout.fillWidth: true
                spacing: 6
                visible: root.on_details

                Text {
                    visible: !root.details_target
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Select a network in the list to see its details"
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 2
                }

                Repeater {
                    model: root.detail_rows

                    Item {
                        id: detail_row
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: Math.max(detail_label.implicitHeight, detail_value.implicitHeight)

                        Text {
                            id: detail_label
                            text: detail_row.modelData.label
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size - 2
                        }

                        Text {
                            id: detail_value
                            x: detail_label.implicitWidth + 12
                            width: Math.max(0, detail_row.width - x)
                            horizontalAlignment: Text.AlignRight
                            wrapMode: detail_row.modelData.wrap ? Text.Wrap : Text.NoWrap
                            elide: detail_row.modelData.wrap ? Text.ElideNone : Text.ElideRight
                            text: detail_row.modelData.value
                            color: root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size - 2
                        }
                    }
                }

                MenuSection {
                    visible: !!root.details_target
                    Layout.fillWidth: true
                    topPadding: 4
                    label: "Settings"
                }

                Text {
                    visible: !!root.details_target && !root.profile
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: !root.details_target || !root.details_target.known ? "Connect to edit settings" : root.details.loaded ? "No saved profile found" : "Loading…"
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 2
                }

                ToggleRow {
                    visible: !!root.profile
                    label: "Autoconnect"
                    toggle_key: ""
                    checked: !!root.profile && root.profile.autoconnect
                    selected: root.setting_selected === 0
                    onToggled: root.activate_setting(0)
                }

                ToggleRow {
                    visible: !!root.profile
                    label: "Metered"
                    toggle_key: ""
                    checked: !!root.profile && root.profile.metered === "yes"
                    state_label: root.profile ? root.metered_labels[root.profile.metered] || "Auto" : ""
                    selected: root.setting_selected === 1
                    onToggled: root.activate_setting(1)
                }

                MenuRow {
                    id: dns_row
                    readonly property real pad: dns_row.st.toggle_brackets ? 6 : 0
                    visible: !!root.profile && !root.dns_edit_mode
                    Layout.fillWidth: true
                    implicitHeight: Math.max(dns_row.st.toggle_brackets ? Style.px(22) : 0, Math.max(dns_label.implicitHeight, dns_value.implicitHeight) + dns_row.pad)
                    selected: root.setting_selected === 2

                    Text {
                        id: dns_label
                        x: dns_row.pad + dns_row.inset
                        y: dns_value.y
                        text: "DNS"
                        color: dns_row.fg(root.st.text_strong)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size - 1
                    }

                    Text {
                        id: dns_value
                        x: dns_label.x + dns_label.implicitWidth + 12
                        y: (dns_row.height - height) / 2
                        width: Math.max(0, dns_row.width - x - dns_row.pad - dns_row.key_space)
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.Wrap
                        text: root.profile && root.profile.dns.length > 0 ? root.profile.dns.join("\n") : "Auto"
                        color: dns_row.fg(root.profile && root.profile.dns.length > 0 ? root.st.text_fg : root.st.toggle_off)
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size - 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.activate_setting(2)
                    }
                }

                ColumnLayout {
                    visible: root.dns_edit_mode
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "DNS for " + root.details_ssid
                        color: root.st.text_strong
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size - 1
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Style.px(26)
                        radius: Style.radius(4)
                        color: Theme.bg_surface

                        TextInput {
                            id: dns_input
                            anchors.fill: parent
                            anchors.margins: 6
                            clip: true
                            color: root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size - 1
                            text: root.dns_text
                            onTextChanged: root.dns_text = text

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    root.finish_dns_edit(true);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    root.finish_dns_edit(false);
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                    event.accepted = true;
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Separate with spaces; leave blank for automatic"
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.font_size - 3
                    }

                    MenuFooter {
                        Layout.fillWidth: true
                        wrap: true
                        text: "Enter apply · Esc cancel"
                    }
                }

                Text {
                    visible: modify_proc.running
                    text: root.profile && root.profile.active ? "Applying…" : "Saving…"
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 3
                }

                Text {
                    visible: root.setting_error !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.setting_error
                    color: Theme.warning
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 3
                }
            }

            TabRows {
                visible: !root.dns_edit_mode
                Layout.fillWidth: true
                chips: true
                labels: root.sub_views
                current: root.current_sub
                onPicked: i => root.current_sub = i
            }
        }

        ColumnLayout {
            id: password_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8
            visible: root.password_mode

            Text {
                text: root.password_target ? "Password for " + root.password_target.name : ""
                color: root.st.text_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size - 1
            }

            Rectangle {
                Layout.fillWidth: true
                height: Style.px(26)
                radius: Style.radius(4)
                color: Theme.bg_surface

                TextInput {
                    id: password_input
                    anchors.fill: parent
                    anchors.margins: 6
                    focus: root.password_mode
                    echoMode: root.password_visible ? TextInput.Normal : TextInput.Password
                    color: root.st.text_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 1
                    text: root.password_text
                    onTextChanged: root.password_text = text

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            root.password_visible = !root.password_visible;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submit_password();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.cancel_password();
                            event.accepted = true;
                        }
                    }
                }
            }

            MenuFooter {
                Layout.fillWidth: true
                text: "Tab show/hide · Enter connect · Esc cancel"
            }

            Text {
                visible: root.status_text !== ""
                text: root.status_text
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size - 3
            }
        }
    }
}
