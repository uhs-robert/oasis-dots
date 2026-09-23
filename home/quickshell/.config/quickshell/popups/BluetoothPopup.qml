// home/quickshell/.config/quickshell/popups/BluetoothPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth as QsBt
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "bluetooth"
    preferred_width: 260
    implicitHeight: content.implicitHeight + 24

    readonly property var adapter: QsBt.Bluetooth.defaultAdapter
    readonly property bool has_adapter: !!adapter
    readonly property var devices: has_adapter ? adapter.devices.values.filter(d => d.paired) : []

    property int selected: 0
    onDevicesChanged: if (selected >= devices.length) selected = Math.max(0, devices.length - 1);

    readonly property bool is_open: Popups.open_name === "bluetooth"
    onIs_openChanged: if (is_open) root.selected = 0;

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
            if (event.key === Qt.Key_P && root.has_adapter) {
                root.adapter.enabled = !root.adapter.enabled;
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                root.selected = Math.min(root.devices.length - 1, root.selected + 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = Math.max(0, root.selected - 1);
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.has_adapter ? root.adapter.name : "No adapter"
                    color: Theme.fg_strong
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 1
                }

                Text {
                    visible: root.has_adapter
                    text: root.has_adapter && root.adapter.enabled ? "On" : "Off"
                    color: root.has_adapter && root.adapter.enabled ? Theme.theme_primary : Theme.fg_dim
                    font.family: Theme.font_family
                    font.pixelSize: Theme.popup_font_size - 2
                }
            }

            Text {
                visible: root.devices.length === 0
                Layout.topMargin: 6
                text: "No paired devices"
                color: Theme.fg_dim
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size - 2
            }

            Repeater {
                model: root.devices

                Rectangle {
                    id: device_row
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.topMargin: device_row.index === 0 ? 6 : 0
                    height: 22
                    radius: 4
                    color: device_row.index === root.selected ? Theme.bg_surface : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        Text {
                            text: device_row.modelData.connected ? "󰂱" : "󰂯"
                            color: device_row.modelData.connected ? Theme.theme_primary : Theme.fg_dim
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 1
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: device_row.modelData.name
                            color: device_row.modelData.connected ? Theme.theme_secondary : Theme.fg_core
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 1
                        }

                        Text {
                            visible: root.battery_label(device_row.modelData) !== ""
                            text: root.battery_label(device_row.modelData)
                            color: Theme.fg_muted
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 2
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
