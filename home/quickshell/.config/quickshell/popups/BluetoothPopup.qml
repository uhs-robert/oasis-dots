// home/quickshell/.config/quickshell/popups/BluetoothPopup.qml
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
    footer_hint: "j/k move · gg/G first/last · Enter connect · t toggle · q close"
    body_height: content.implicitHeight + 24
    jumps_enabled: true

    readonly property var adapter: QsBt.Bluetooth.defaultAdapter
    readonly property bool has_adapter: !!adapter
    readonly property var devices: has_adapter ? adapter.devices.values.filter(d => d.paired) : []

    // The memory card slot screen: each device a block, lit while connected.
    readonly property bool slots: root.st.console_views === "ps1"
    // SNES: devices as party members, each in its own window.
    readonly property bool party: root.st.console_views === "snes"

    // -1 is the power switch above the list.
    property int selected: 0
    onDevicesChanged: if (selected >= devices.length) selected = Math.max(0, devices.length - 1);

    readonly property bool is_open: Popups.open_name === "bluetooth"
    onIs_openChanged: if (is_open) root.selected = 0;
    onJump_first: root.selected = root.has_adapter ? -1 : 0
    onJump_last: root.selected = Math.max(0, root.devices.length - 1)
    search_enabled: true
    search_rows: root.devices.map(d => d.name)
    search_cursor: root.selected
    onSearch_select: index => root.selected = index

    function toggle_power() {
        if (root.has_adapter) root.adapter.enabled = !root.adapter.enabled;
    }

    function battery_label(device) {
        return device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "";
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
            if (event.key === Qt.Key_T) {
                root.toggle_power();
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                const min = root.has_adapter ? -1 : 0;
                root.selected = root.wrap_index(root.selected, 1, min, root.devices.length - min);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                const min = root.has_adapter ? -1 : 0;
                root.selected = root.wrap_index(root.selected, -1, min, root.devices.length - min);
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selected === -1) {
                root.toggle_power();
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.devices[root.selected]) {
                const d = root.devices[root.selected];
                if (d.connected) d.disconnect(); else d.connect();
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
                visible: root.devices.length === 0
                Layout.topMargin: 6
                text: "No paired devices"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size - 2
            }

            Repeater {
                model: root.party ? root.devices : []

                Snes.SnesDeviceRow {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.topMargin: index === 0 ? 6 : 0
                    device: modelData
                    selected: index === root.selected
                    onClicked: {
                        root.selected = index;
                        if (modelData.connected) modelData.disconnect();
                        else modelData.connect();
                    }
                }
            }

            Repeater {
                model: root.party ? [] : root.devices

                MenuRow {
                    id: device_row
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.topMargin: device_row.index === 0 ? 6 : 0
                    height: root.slots ? Style.px(30) : Style.px(22)
                    selected: device_row.index === root.selected

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
                            font.pixelSize: root.st.font_size - 1
                        }

                        RowLabel {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            label: device_row.modelData.name
                            color: device_row.fg(device_row.modelData.connected ? root.st.text_accent : root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size - 1
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
                            font.pixelSize: root.st.font_size - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = device_row.index;
                            if (device_row.modelData.connected) device_row.modelData.disconnect();
                            else device_row.modelData.connect();
                        }
                    }
                }
            }
        }
    }
}
