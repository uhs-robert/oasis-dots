// home/quickshell/.config/quickshell/popups/BatteryPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "battery"

    WheelStepper {
        id: stepper
    }
    preferred_width: 260
    footer_hint: "j/k move · h/l adjust · Enter profile · q close"
    body_height: content.implicitHeight + 24

    readonly property var device: UPower.displayDevice
    readonly property bool has_battery: !!device && device.ready
    readonly property real percent: has_battery ? device.percentage * 100 : 0
    readonly property int state: has_battery ? device.state : UPowerDeviceState.Unknown
    readonly property real rate: has_battery ? device.changeRate : 0

    readonly property string state_label: {
        if (state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge) return "Charging";
        if (state === UPowerDeviceState.FullyCharged) return "Full";
        return "Discharging";
    }

    function format_time(seconds) {
        if (seconds <= 0) return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    readonly property string time_label: {
        if (has_battery && device.timeToEmpty > 0) return format_time(device.timeToEmpty) + " remaining";
        if (has_battery && device.timeToFull > 0) return format_time(device.timeToFull) + " until full";
        return "";
    }

    property bool ppd_available: false
    property int selected: 0

    readonly property var profiles: {
        const list = [
            { label: "Power Saver", value: PowerProfile.PowerSaver },
            { label: "Balanced", value: PowerProfile.Balanced },
        ];
        if (PowerProfiles.hasPerformanceProfile) list.push({ label: "Performance", value: PowerProfile.Performance });
        return list;
    }

    // Keyboard nav walks brightness, keyboard backlight (if present), then profiles.
    readonly property var nav_rows: {
        const list = [{ kind: "brightness" }];
        if (Backlight.has_kbd) list.push({ kind: "kbd" });
        if (root.ppd_available) {
            for (let i = 0; i < root.profiles.length; i++) list.push({ kind: "profile", index: i });
        }
        return list;
    }

    readonly property bool is_open: Popups.open_name === "battery"
    onIs_openChanged: if (is_open) {
        root.selected = 0;
        ppd_check_proc.running = true;
        Backlight.refresh();
    }

    // Sysfs brightness has no inotify; poll while the popup is visible.
    Timer {
        interval: 1000
        running: root.is_open
        repeat: true
        onTriggered: Backlight.refresh()
    }

    // busctl exits non-zero when the daemon is not D-Bus activatable.
    Process {
        id: ppd_check_proc
        command: ["busctl", "--system", "introspect", "org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles"]
        onExited: code => root.ppd_available = code === 0
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
            const row = root.nav_rows[root.selected];
            if (event.key === Qt.Key_J) {
                root.selected = Math.min(root.nav_rows.length - 1, root.selected + 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = Math.max(0, root.selected - 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                if (row && row.kind === "brightness") Backlight.set_percent(stepper.snap(Backlight.percent, 1, 1, 100));
                else if (row && row.kind === "kbd") Backlight.kbd_set_percent(stepper.snap(Backlight.kbd_percent, 1, 0, 100));
                event.accepted = true;
            } else if (event.key === Qt.Key_H) {
                if (row && row.kind === "brightness") Backlight.set_percent(stepper.snap(Backlight.percent, -1, 1, 100));
                else if (row && row.kind === "kbd") Backlight.kbd_set_percent(stepper.snap(Backlight.kbd_percent, -1, 0, 100));
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && row && row.kind === "profile") {
                PowerProfiles.profile = root.profiles[row.index].value;
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Text {
                text: Math.round(root.percent) + "%"
                color: Theme.fg_strong
                font.family: Style.font_family
                font.pixelSize: Style.font_size + 4
            }

            Text {
                text: root.state_label
                color: Theme.fg_muted
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 2
            }

            Text {
                visible: root.time_label !== ""
                text: root.time_label
                color: Theme.fg_muted
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 2
            }

            Text {
                visible: root.rate > 0
                text: root.rate.toFixed(1) + " W"
                color: Theme.fg_muted
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 2
            }

            MenuRow {
                id: brightness_row
                Layout.fillWidth: true
                Layout.topMargin: 6
                height: Style.px(22)
                selected: !!root.nav_rows[root.selected] && root.nav_rows[root.selected].kind === "brightness"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6 + brightness_row.inset
                    anchors.rightMargin: 6
                    spacing: 8

                    Text {
                        text: "󰃠"
                        color: brightness_row.fg(Theme.theme_primary)
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                    }

                    Slider {
                        Layout.fillWidth: true
                        on_selection: brightness_row.selected
                        value: Backlight.percent / 100
                        onMoved: v => Backlight.set_percent(Math.round(v * 100))
                    }

                    Text {
                        Layout.preferredWidth: 32
                        text: Backlight.percent + "%"
                        color: brightness_row.fg(Theme.fg_core)
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 1
                    }
                }
            }

            MenuRow {
                id: kbd_row
                visible: Backlight.has_kbd
                Layout.fillWidth: true
                height: Style.px(22)
                selected: !!root.nav_rows[root.selected] && root.nav_rows[root.selected].kind === "kbd"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6 + kbd_row.inset
                    anchors.rightMargin: 6
                    spacing: 8

                    Text {
                        text: "󰌌"
                        color: kbd_row.fg(Theme.theme_primary)
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size
                    }

                    Slider {
                        Layout.fillWidth: true
                        on_selection: kbd_row.selected
                        value: Backlight.kbd_percent / 100
                        onMoved: v => Backlight.kbd_set_percent(Math.round(v * 100))
                    }

                    Text {
                        Layout.preferredWidth: 32
                        text: Backlight.kbd_percent + "%"
                        color: kbd_row.fg(Theme.fg_core)
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 1
                    }
                }
            }

            Text {
                visible: !root.ppd_available
                Layout.topMargin: 6
                text: "power-profiles-daemon not running"
                color: Theme.fg_dim
                font.family: Style.font_family
                font.pixelSize: Style.font_size - 3
            }

            Repeater {
                model: root.ppd_available ? root.profiles : []

                MenuRow {
                    id: profile_row
                    required property var modelData
                    required property int index

                    readonly property int nav_index: (Backlight.has_kbd ? 2 : 1) + profile_row.index

                    Layout.fillWidth: true
                    Layout.topMargin: profile_row.index === 0 ? 6 : 0
                    height: Style.px(22)
                    selected: profile_row.nav_index === root.selected

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6 + profile_row.inset
                        anchors.rightMargin: 6
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: profile_row.modelData.label
                            color: profile_row.fg(PowerProfiles.profile === profile_row.modelData.value ? Theme.theme_secondary : Theme.fg_core)
                            font.family: Style.font_family
                            font.pixelSize: Style.font_size - 1
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = profile_row.nav_index;
                            PowerProfiles.profile = profile_row.modelData.value;
                        }
                    }
                }
            }
        }
    }
}
