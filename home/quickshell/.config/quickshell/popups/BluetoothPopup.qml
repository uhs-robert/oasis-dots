// home/quickshell/.config/quickshell/popups/BluetoothPopup.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth as QsBt
import "../components"
import "../theme"
import "../services"
import "../components/nes" as Nes
import "../components/ps1" as Ps1
import "snes" as Snes

Popup {
    id: root

    popup_name: "bluetooth"
    preferred_width: 260
    footer_hint: root.forget_confirm ? "y forget · n keep" : "j/k move · gg/G first/last · Enter connect · s scan · T trust · x forget · t toggle · q close"
    body_height: Math.max(280, content.implicitHeight + 24)
    jumps_enabled: !root.forget_confirm

    readonly property var adapter: QsBt.Bluetooth.defaultAdapter
    readonly property bool has_adapter: !!adapter
    readonly property bool scanning: has_adapter && adapter.discovering
    readonly property var devices: has_adapter ? adapter.devices.values.filter(d => d.paired) : []
    // Named unpaired devices while scanning, capped so a busy area cannot outgrow the popup.
    readonly property var nearby: has_adapter ? adapter.devices.values.filter(d => !d.paired && (d === root.pair_target || root.scanning && d.deviceName !== "")).sort((a, b) => a.name.localeCompare(b.name)).slice(0, 8) : []
    readonly property var rows: root.devices.concat(root.nearby)

    // The device being paired from the nearby list, and how far it got: "pairing", "connecting" or "failed".
    property var pair_target: null
    property string pair_phase: ""

    property bool forget_confirm: false
    property var forget_target: null

    // The memory card slot screen: each device a block, lit while connected.
    readonly property bool slots: root.st.console_views === "ps1"
    // SNES: devices as party members, each in its own window.
    readonly property bool party: root.st.console_views === "snes"

    // -1 is the power switch above the list.
    property int selected: 0
    onRowsChanged: if (selected >= rows.length) selected = Math.max(0, rows.length - 1);

    readonly property bool is_open: Popups.open_name === "bluetooth"
    onIs_openChanged: {
        root.forget_confirm = false;
        root.forget_target = null;
        if (is_open) {
            root.selected = 0;
        } else {
            if (root.scanning) root.adapter.discovering = false;
            if (root.pair_phase === "failed") root.clear_pair();
        }
    }
    onJump_first: root.selected = root.has_adapter ? -1 : 0
    onJump_last: root.selected = Math.max(0, root.rows.length - 1)
    search_enabled: !root.forget_confirm
    search_rows: root.rows.map(d => d.name)
    search_cursor: root.selected
    onSearch_select: index => root.selected = index

    function toggle_power() {
        if (root.has_adapter) root.adapter.enabled = !root.adapter.enabled;
    }

    function toggle_scan() {
        if (root.has_adapter && root.adapter.enabled) root.adapter.discovering = !root.adapter.discovering;
    }

    function activate(device) {
        root.follow(device);
        if (device === root.pair_target && root.pair_phase !== "failed") return;
        if (device === root.pair_target) root.clear_pair();
        if (!device.paired) root.start_pair(device);
        else if (device.connected) device.disconnect();
        else device.connect();
    }

    function start_pair(device) {
        root.pair_target = device;
        root.pair_phase = "pairing";
        root.arm_pair_timer(60000);
        device.pair();
    }

    function clear_pair() {
        pair_timer.stop();
        root.pair_target = null;
        root.pair_phase = "";
    }

    function arm_pair_timer(ms) {
        pair_timer.interval = ms;
        pair_timer.restart();
    }

    function advance_pair() {
        const d = root.pair_target;
        if (!d || root.pair_phase === "failed") return;
        if (d.paired && d.connected) {
            root.clear_pair();
        } else if (d.paired && root.pair_phase === "pairing") {
            d.trusted = true;
            root.pair_phase = "connecting";
            root.arm_pair_timer(20000);
            d.connect();
            Qt.callLater(root.follow, d);
        }
    }

    // Keeps the cursor on a device as it moves from the nearby list to the paired one.
    function follow(device) {
        const i = root.rows.indexOf(device);
        if (i >= 0) root.selected = i;
    }

    function status_label(device) {
        if (device === root.pair_target) return root.pair_phase === "pairing" ? "Pairing" : root.pair_phase === "connecting" ? "Connecting" : "Failed";
        if (device.state === QsBt.BluetoothDeviceState.Connecting) return "Connecting";
        if (device.state === QsBt.BluetoothDeviceState.Disconnecting) return "Disconnecting";
        return "";
    }

    function battery_label(device) {
        return device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "";
    }

    Connections {
        target: root.pair_target
        function onPairedChanged() { root.advance_pair(); }
        function onConnectedChanged() { root.advance_pair(); }
        // Pairing can clear just before Paired is set, so wait briefly before calling it a failure.
        function onPairingChanged() { if (!root.pair_target.pairing && root.pair_phase === "pairing") root.arm_pair_timer(2000); }
        function onStateChanged() { if (root.pair_phase === "connecting" && root.pair_target.state === QsBt.BluetoothDeviceState.Disconnected) root.arm_pair_timer(1500); }
    }

    Timer {
        id: pair_timer
        onTriggered: {
            const phase = root.pair_phase;
            root.advance_pair();
            if (root.pair_target && root.pair_phase === phase) root.pair_phase = "failed";
        }
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
            if (root.forget_confirm) {
                if (root.is_help_key(event) || event.key === Qt.Key_Q) return;
                if (event.key === Qt.Key_Y && root.forget_target) root.forget_target.forget();
                if (event.key === Qt.Key_Y || event.key === Qt.Key_N || event.key === Qt.Key_Escape) {
                    root.forget_confirm = false;
                    root.forget_target = null;
                }
                event.accepted = true;
                return;
            }

            const row = root.rows[root.selected];
            if (event.key === Qt.Key_T && (event.modifiers & Qt.ShiftModifier)) {
                if (row && row.paired) row.trusted = !row.trusted;
                event.accepted = true;
            } else if (event.key === Qt.Key_T) {
                root.toggle_power();
                event.accepted = true;
            } else if (event.key === Qt.Key_S) {
                root.toggle_scan();
                event.accepted = true;
            } else if (event.key === Qt.Key_X) {
                if (row && row.paired) {
                    root.forget_target = row;
                    root.forget_confirm = true;
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                const min = root.has_adapter ? -1 : 0;
                root.selected = root.wrap_index(root.selected, 1, min, root.rows.length - min);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                const min = root.has_adapter ? -1 : 0;
                root.selected = root.wrap_index(root.selected, -1, min, root.rows.length - min);
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selected === -1) {
                root.toggle_power();
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && row) {
                root.activate(row);
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            ToggleRow {
                label: root.has_adapter ? root.adapter.name : "No adapter"
                checked: root.has_adapter && root.adapter.enabled
                show_state: root.has_adapter
                selected: root.selected === -1
                onToggled: {
                    root.selected = -1;
                    root.toggle_power();
                }
            }

            Text {
                visible: root.forget_confirm
                Layout.topMargin: 6
                text: "Forget " + (root.forget_target ? root.forget_target.name : "this device") + "? y/n"
                color: Theme.error
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Text {
                visible: root.devices.length === 0
                Layout.topMargin: 6
                text: "No paired devices"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Repeater {
                model: root.party ? root.devices : []
                delegate: party_delegate
            }

            Repeater {
                model: root.party ? [] : root.devices
                delegate: row_delegate
            }

            MenuSection {
                visible: root.scanning || root.nearby.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                label: root.scanning ? "Nearby · scanning" : "Nearby"
            }

            Text {
                visible: root.scanning && root.nearby.length === 0
                text: "Looking for devices"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Repeater {
                model: root.party ? root.nearby : []
                delegate: party_delegate
            }

            Repeater {
                model: root.party ? [] : root.nearby
                delegate: row_delegate
            }
        }
    }

    Component {
        id: party_delegate

        Snes.SnesDeviceRow {
            required property var modelData
            readonly property int row_index: root.rows.indexOf(modelData)

            Layout.fillWidth: true
            Layout.topMargin: row_index === 0 ? 6 : 0
            device: modelData
            status: root.status_label(modelData)
            selected: row_index === root.selected
            onClicked: root.activate(modelData)
        }
    }

    Component {
        id: row_delegate

        MenuRow {
            id: device_row
            required property var modelData
            readonly property int row_index: root.rows.indexOf(device_row.modelData)
            readonly property string status: root.status_label(device_row.modelData)

            Layout.fillWidth: true
            Layout.topMargin: device_row.row_index === 0 ? 6 : 0
            height: root.slots ? Style.px(30) : Style.px(22)
            selected: device_row.row_index === root.selected

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6 + device_row.inset
                anchors.rightMargin: 6 + device_row.key_space
                spacing: root.slots ? 8 : 6

                Loader {
                    active: root.slots
                    visible: active
                    sourceComponent: Ps1.MemBlock {
                        size: device_row.height - 4
                        glyph: device_row.modelData.connected ? "󰂱" : "󰂯"
                        glyph_color: device_row.modelData.connected ? Theme.theme_primary_light : root.st.text_dim
                        lit: device_row.modelData.connected
                    }
                }

                Text {
                    visible: !root.slots
                    text: device_row.modelData.connected ? "󰂱" : "󰂯"
                    color: device_row.fg(device_row.modelData.connected ? root.st.text_primary : root.st.text_dim)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                }

                RowLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    label: device_row.modelData.name
                    color: device_row.fg(device_row.modelData.connected ? root.st.text_accent : root.st.text_fg)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-1)
                }

                Text {
                    visible: device_row.status !== ""
                    text: device_row.status
                    color: device_row.fg(device_row.status === "Failed" ? Theme.error : root.st.text_muted)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Loader {
                    active: root.st.console_views === "nes" && device_row.modelData.batteryAvailable
                    visible: active
                    sourceComponent: Nes.CoinMeter {
                        size: 12
                        value: device_row.modelData.battery
                    }
                }

                Text {
                    visible: root.battery_label(device_row.modelData) !== ""
                    text: root.battery_label(device_row.modelData)
                    color: device_row.fg(root.st.text_muted)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }

                Text {
                    visible: device_row.modelData.paired && device_row.modelData.trusted
                    text: "󰕥"
                    color: device_row.fg(root.st.text_muted)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-2)
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.activate(device_row.modelData)
            }
        }
    }
}
