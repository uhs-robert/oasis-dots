// home/quickshell/.config/quickshell/popups/NetworkPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../components"
import "../theme"
import "../services"
import "../components/goldeneye" as Goldeneye
import "network"
import "network/Network.js" as Net

Popup {
    id: root

    popup_name: "network"
    preferred_width: 320
    key_help: root.password_mode || root.dns_edit_mode ? "" : root.forget_confirm ? "y forget · n keep" : root.on_details ? root.details_help : root.list_help
    footer_hint: root.key_help
    sub_views: ["Networks", "Details"]

    // The list fits its rows and only scrolls past most of the screen height.
    readonly property real max_list_height: (root.screen ? root.screen.height : 1080) * 0.6
    body_height: Math.max(340, content.implicitHeight + 24)
    jumps_enabled: !root.password_mode && !root.forget_confirm && !root.dns_edit_mode
    cursor_state: [root.selected, root.setting_selected]

    readonly property string list_help: "Tab details · j/k move · gg/G first/last · Enter connect · x forget · t toggle · r scan · q close"
    readonly property string details_help: root.profile
        ? "Tab/Esc list · j/k move · gg/G first/last · t/Enter toggle · Enter edit DNS · r refresh · q close"
        : "Tab/Esc list · r refresh · q close"

    readonly property var wifi_device: {
        for (const d of Networking.devices.values) if (d.type === DeviceType.Wifi) return d;
        return null;
    }

    readonly property string no_wifi_reason: Networking.backend === NetworkBackendType.None ? "NetworkManager not running" : !root.wifi_device ? "No Wi-Fi adapter" : ""

    // goldeneye: the link in the watch's mission wording, with a dial header and segment signal bars.
    readonly property bool link_watch: root.st.link_style === "watch"
    readonly property bool link_scanning: !!root.wifi_device && root.wifi_device.scannerEnabled
    readonly property bool link_wired: !!root.wired_device && root.wired_device.connected
    readonly property string link_state: {
        if (root.status_text.indexOf("Connecting") === 0) return "LINKING...";
        if (root.link_scanning && !root.active_wifi_network) return "SCANNING...";
        if (root.active_wifi_network || root.link_wired) return "LINK SECURE";
        return "NO UPLINK";
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

    // The MGS codec: signal read out as a 140.xx frequency.
    readonly property bool codec: root.st.console_views === "ps1"
    readonly property bool ps2: root.st.console_views === "ps2"

    readonly property var wifi_networks: Net.build_network_list(root.wifi_device ? root.wifi_device.networks.values : [])
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

    function fetch_details() {
        if (!root.is_open || !root.on_details || !root.details_target || !root.wifi_device || !root.wifi_device.name) return;
        if (details_proc.running) {
            root.details_stale = true;
            return;
        }
        details_proc.command = ["sh", "-c", Net.details_script, "sh", root.wifi_device.name];
        details_proc.running = true;
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

    // Latest request per setting, run in order after the current one exits.
    property var modify_queue: []

    property var modify_current: null

    function start_modify(req, idle) {
        if (idle) root.setting_error = "";
        root.modify_current = req;
        modify_proc.command = ["sh", "-c", Net.modify_script, "sh", req.uuid, req.reapply ? "1" : "0"].concat(req.props);
        modify_proc.running = true;
    }

    function run_modify(props, reapply) {
        if (!root.profile) return;
        const req = { uuid: root.profile.uuid, props: props, reapply: reapply };
        if (!modify_proc.running) {
            root.start_modify(req, root.modify_queue.length === 0);
            return;
        }
        root.modify_queue = root.modify_queue.filter(q => q.uuid !== req.uuid || q.props[0] !== props[0]).concat([req]);
    }

    function pending_request(key) {
        const mine = r => root.profile && r.uuid === root.profile.uuid && r.props[0] === key;
        return root.modify_queue.find(mine) || (root.modify_current && mine(root.modify_current) ? root.modify_current : null);
    }

    function queued_value(key) {
        const q = root.pending_request(key);
        return q ? q.props[1] : "";
    }

    function next_modify() {
        const req = root.modify_queue[0];
        if (!req) return;
        root.modify_queue = root.modify_queue.slice(1);
        root.start_modify(req, false);
    }

    function activate_setting(i) {
        if (!root.profile) return;
        ThemeAudio.play("confirm");
        root.setting_selected = i;
        if (i === 0) {
            const auto = root.queued_value("connection.autoconnect") || (root.profile.autoconnect ? "yes" : "no");
            root.run_modify(["connection.autoconnect", auto === "yes" ? "no" : "yes"], false);
        } else if (i === 1) {
            const metered = root.queued_value("connection.metered") || root.profile.metered;
            root.run_modify(["connection.metered", root.metered_next[metered] || "unknown"], false);
        }
        else if (i === 2) root.start_dns_edit();
    }

    function start_dns_edit() {
        if (!root.profile) return;
        const pending = root.pending_request("ipv4.dns");
        root.dns_text = pending ? pending.props[1].split(",").filter(d => d !== "").join(" ") : root.profile.dns.join(" ");
        root.setting_error = "";
        root.dns_edit_mode = true;
        details_pane.focus_dns();
    }

    function finish_dns_edit(apply) {
        ThemeAudio.play(apply ? "confirm" : "cancel");
        root.dns_edit_mode = false;
        if (!apply) return;
        const list = root.dns_text.split(/[\s,;]+/).filter(d => d !== "");
        root.run_modify(["ipv4.dns", list.join(","), "ipv4.ignore-auto-dns", list.length > 0 ? "yes" : "no"], root.profile && root.profile.active);
    }

    function handle_details_key(event) {
        const before = root.cursor_key();
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
            root.current_sub = 0;
            ThemeAudio.play("cancel");
        } else if (event.key === Qt.Key_R) {
            root.fetch_details();
            ThemeAudio.play("confirm");
        } else if (root.setting_count > 0 && event.key === Qt.Key_J) {
            root.setting_selected = root.wrap_index(root.setting_selected, 1, 0, root.setting_count);
            root.play_if_moved(before);
        } else if (root.setting_count > 0 && event.key === Qt.Key_K) {
            root.setting_selected = root.wrap_index(root.setting_selected, -1, 0, root.setting_count);
            root.play_if_moved(before);
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
            onStreamFinished: root.details = Net.parse_details(text, root.details_ssid)
        }
    }

    Process {
        id: modify_proc
        onExited: {
            root.modify_current = null;
            root.next_modify();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const err = text.trim().replace(/^Error: /, "");
                if (err !== "") root.setting_error = err;
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
            onStreamFinished: root.wifi_ipv4 = Net.parse_ipv4(text)
        }
    }

    Process {
        id: wired_ip_proc
        stdout: StdioCollector {
            onStreamFinished: root.wired_ipv4 = Net.parse_ipv4(text)
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
        ThemeAudio.play("confirm");
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
        ThemeAudio.play("confirm");
        Popups.after_close(() => Quickshell.execDetached(["env", "-u", "TMUX", "-u", "TMUX_PANE", "sh", "-c", "t=\"${XDG_STATE_HOME:-$HOME/.local/state}/hypr/bin/term\"; [ -x \"$t\" ] || t=\"${TERMINAL:-kitty}\"; exec \"$t\" -e nmtui"]));
    }

    function toggle_wifi() {
        if (root.no_wifi_reason !== "") return;
        ThemeAudio.play("confirm");
        Networking.wifiEnabled = !Networking.wifiEnabled;
    }

    function submit_password() {
        if (!root.password_target) return;
        ThemeAudio.play("confirm");
        root.status_text = "Connecting…";
        root.password_target.connectWithPsk(root.password_text);
        root.password_text = "";
    }

    function cancel_password() {
        ThemeAudio.play("cancel");
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
        implicitHeight: root.password_mode ? password_pane.implicitHeight : view_column.implicitHeight
        focus: true

        Keys.onPressed: event => {
            const before = root.cursor_key();
            if (root.password_mode || root.dns_edit_mode) return;

            if (root.forget_confirm) {
                if (root.is_help_key(event) || event.key === Qt.Key_Q) return;
                if (event.key === Qt.Key_Y) {
                    ThemeAudio.play("confirm");
                    if (root.forget_target) root.forget_target.forget();
                    root.forget_confirm = false;
                    root.forget_target = null;
                } else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape) {
                    ThemeAudio.play("cancel");
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
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, -1, root.nav_rows.length + 1);
                if (root.selected >= 0) network_list.positionViewAtIndex(root.selected, ListView.Contain);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_T) {
                root.toggle_wifi();
                event.accepted = true;
            } else if (event.key === Qt.Key_R) {
                root.start_scan();
                ThemeAudio.play("confirm");
                event.accepted = true;
            } else if (event.key === Qt.Key_X && row && !row.advanced && row.known) {
                root.forget_target = row;
                root.forget_confirm = true;
                ThemeAudio.play("confirm");
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
                Layout.fillWidth: true
                spacing: 6
                visible: !root.on_details

                WifiHeader {
                    Layout.fillWidth: true
                    st: root.st
                    wifi: root.active_wifi_network
                    wired_device: root.wired_device
                    wifi_ipv4: root.wifi_ipv4
                    wired_ipv4: root.wired_ipv4
                    link_state: root.link_state
                    link_watch: root.link_watch
                    link_wired: root.link_wired
                    codec: root.codec
                    ps2: root.ps2
                    speed: root.details.dev && root.details.dev.speed && root.details.dev.speed !== "unknown" ? root.details.dev.speed : ""
                    status_text: root.status_text
                    no_wifi_reason: root.no_wifi_reason
                    wifi_enabled: Networking.wifiEnabled
                    toggle_selected: root.selected === -1
                    onToggle_clicked: {
                        root.selected = -1;
                        root.forget_confirm = false;
                        root.toggle_wifi();
                    }
                }

                Text {
                    visible: root.forget_confirm
                    text: "Forget " + (root.forget_target ? root.forget_target.name : "this network") + "? y/n"
                    color: Style.pal.error
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                ListView {
                    id: network_list
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, root.max_list_height)
                    clip: true
                    spacing: 4
                    model: root.nav_rows
                    currentIndex: root.selected

                    Goldeneye.ScanStatic {
                        anchors.fill: parent
                        z: 10
                        scanning: root.link_watch && root.link_scanning
                    }

                    delegate: WifiRow {
                        id: net_row
                        width: network_list.width
                        popup_st: root.st
                        selected: net_row.index === root.selected
                        link_watch: root.link_watch
                        codec: root.codec
                        ps2: root.ps2
                        onActivated: {
                            root.selected = net_row.index;
                            root.forget_confirm = false;
                            if (net_row.is_advanced) root.open_advanced();
                            else root.connect_to(net_row.modelData);
                        }
                    }
                }
            }

            DetailsPane {
                id: details_pane
                Layout.fillWidth: true
                visible: root.on_details
                st: root.st
                target: root.details_target
                ssid: root.details_ssid
                loaded: !!root.details.loaded
                profile: root.profile
                rows: root.detail_rows
                setting_selected: root.setting_selected
                dns_edit_mode: root.dns_edit_mode
                dns_text: root.dns_text
                saving: modify_proc.running
                setting_error: root.setting_error
                metered_labels: root.metered_labels
                onActivate: i => root.activate_setting(i)
                onDns_edited: t => root.dns_text = t
                onDns_finished: apply => root.finish_dns_edit(apply)
            }

            TabRows {
                visible: !root.dns_edit_mode
                Layout.fillWidth: true
                chips: true
                labels: root.sub_views
                current: root.current_sub
                onPicked: i => {
                    root.current_sub = i;
                    ThemeAudio.play("cursor");
                }
            }
        }

        PasswordPane {
            id: password_pane
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            visible: root.password_mode
            st: root.st
            target_name: root.password_target ? root.password_target.name : ""
            text: root.password_text
            reveal: root.password_visible
            status_text: root.status_text
            active: root.password_mode
            onEdited: t => root.password_text = t
            onToggle_reveal: root.password_visible = !root.password_visible
            onSubmit: root.submit_password()
            onCancel: root.cancel_password()
        }
    }
}
