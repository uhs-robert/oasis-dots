// home/quickshell/.config/quickshell/popups/BatteryPopup.qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import "../components"
import "../theme"
import "../services"
import "../components/nes" as Nes
import "snes" as Snes
import "../components/ps1" as Ps1
import "../components/ps2" as Ps2
import "battery"

Popup {
    id: root

    popup_name: "battery"

    WheelStepper {
        id: stepper
    }
    preferred_width: 260
    footer_hint: "j/k move · gg/G first/last · h/l adjust · Enter profile · s/b/p profile · q close"
    body_height: content.implicitHeight + 24
    jumps_enabled: true
    cursor_state: root.selected

    readonly property var battery_device: UPower.displayDevice
    readonly property bool has_battery: !!battery_device && battery_device.ready && battery_device.isLaptopBattery
    readonly property real percent: has_battery ? battery_device.percentage * 100 : 0
    readonly property int state: has_battery ? battery_device.state : UPowerDeviceState.Unknown
    readonly property real rate: has_battery ? battery_device.changeRate : 0

    readonly property string state_label: {
        if (state === UPowerDeviceState.Charging || state === UPowerDeviceState.PendingCharge) return "Charging";
        if (state === UPowerDeviceState.FullyCharged) return "Full";
        return "Discharging";
    }

    readonly property string time_label: {
        if (has_battery && battery_device.timeToEmpty > 0) return Power.format_time(battery_device.timeToEmpty) + " remaining";
        if (has_battery && battery_device.timeToFull > 0) return Power.format_time(battery_device.timeToFull) + " until full";
        return "";
    }

    readonly property bool ppd_available: Power.ppd_available
    readonly property bool nes: root.st.console_views === "nes"
    readonly property real status_indent: root.nes ? 22 : 0
    readonly property real percent_width: percent_metrics.height > 0 ? Math.max(32, Math.ceil(percent_metrics.advanceWidth("100%"))) : 32
    property int selected: 0

    readonly property var profiles: {
        const list = [
            { label: "Power Saver", value: PowerProfile.PowerSaver, key: "s" },
            { label: "Balanced", value: PowerProfile.Balanced, key: "b" },
        ];
        if (PowerProfiles.hasPerformanceProfile) list.push({ label: "Performance", value: PowerProfile.Performance, key: "p" });
        return list;
    }

    readonly property var current_profile: root.profiles.find(p => p.value === PowerProfiles.profile)

    function row_kind(index) {
        const row = root.nav_rows[index];
        return row ? row.kind : "";
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
        if (!Power.ppd_available) Power.probe_ppd();
        Backlight.refresh();
    }
    search_enabled: true
    search_rows: root.nav_rows.map(r => r.kind === "profile" ? root.profiles[r.index].label : "")
    search_cursor: root.selected
    onSearch_select: index => root.selected = index
    onJump_first: root.selected = 0
    onJump_last: root.selected = Math.max(0, root.nav_rows.length - 1)

    // Sysfs brightness has no inotify; catch writers other than the shell.
    Timer {
        interval: 5000
        running: root.is_open
        repeat: true
        onTriggered: Backlight.refresh()
    }

    // The wheel steps a backlight row like h/l, one snap step per notch.
    property string wheel_kind: ""
    function wheel_adjust(kind, wheel) {
        if (kind !== root.wheel_kind) {
            stepper.accumulated = 0;
            root.wheel_kind = kind;
        }
        const notches = stepper.consume_event(wheel);
        if (notches === 0) return;
        if (kind === "brightness" && Backlight.has_device) Backlight.set_percent(stepper.snap_by(Backlight.percent, notches, 1, 100));
        else if (kind === "kbd" && Backlight.has_kbd) Backlight.kbd_set_percent(stepper.snap_by(Backlight.kbd_percent, notches, 0, 100));
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
            const before = root.cursor_key();
            const row = root.nav_rows[root.selected];
            if (event.key === Qt.Key_J) {
                root.selected = root.wrap_index(root.selected, 1, 0, root.nav_rows.length);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.selected = root.wrap_index(root.selected, -1, 0, root.nav_rows.length);
                root.play_if_moved(before);
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                const level = !row ? -1 : row.kind === "brightness" ? Backlight.percent : row.kind === "kbd" ? Backlight.kbd_percent : -1;
                const target = level < 0 ? level : stepper.snap(level, 1, row.kind === "brightness" ? 1 : 0, 100);
                if (row && row.kind === "brightness") Backlight.set_percent(target);
                else if (row && row.kind === "kbd") Backlight.kbd_set_percent(target);
                if (target !== level) ThemeAudio.play("cursor");
                event.accepted = true;
            } else if (event.key === Qt.Key_H) {
                const level = !row ? -1 : row.kind === "brightness" ? Backlight.percent : row.kind === "kbd" ? Backlight.kbd_percent : -1;
                const target = level < 0 ? level : stepper.snap(level, -1, row.kind === "brightness" ? 1 : 0, 100);
                if (row && row.kind === "brightness") Backlight.set_percent(target);
                else if (row && row.kind === "kbd") Backlight.kbd_set_percent(target);
                if (target !== level) ThemeAudio.play("cursor");
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && row && row.kind === "profile") {
                PowerProfiles.profile = root.profiles[row.index].value;
                ThemeAudio.play("confirm");
                event.accepted = true;
            } else if (root.ppd_available && !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier))) {
                const i = root.profiles.findIndex(p => p.key === event.text);
                if (i >= 0) {
                    root.selected = root.nav_rows.findIndex(r => r.kind === "profile" && r.index === i);
                    PowerProfiles.profile = root.profiles[i].value;
                    ThemeAudio.play("confirm");
                    event.accepted = true;
                }
            }
        }

        Loader {
            active: root.nes && root.has_battery
            width: 14
            height: Math.max(0, brightness_row.y - 10)
            sourceComponent: Nes.EnergyBar {
                vertical: true
                value: root.percent / 100
                low_from: 0.2
            }
        }

        ColumnLayout {
            id: main_column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            Loader {
                id: watch_gauge
                active: root.st.osd_layout === "watch" && root.has_battery
                visible: active
                Layout.fillWidth: true
                Layout.preferredHeight: active ? Style.px(100) : 0
                Layout.bottomMargin: 6
                sourceComponent: WatchGauge {
                    percent: root.percent
                    state_label: root.state_label
                    rate: root.rate
                    time_label: root.time_label
                    device: root.battery_device
                    ppd_available: root.ppd_available
                    profile_label: root.current_profile ? root.current_profile.label : ""
                }
            }

            // Console status views replace the readout lines.
            Loader {
                id: status_view
                readonly property Component view: ({ snes: snes_status, ps1: ps1_status, ps2: ps2_status })[root.st.console_views] || null
                active: !!view && root.has_battery
                visible: active
                Layout.fillWidth: true
                sourceComponent: view
            }

            Component {
                id: snes_status
                Snes.SnesBatteryStatus {
                    percent: root.percent
                    state_label: root.state_label
                    time_label: root.time_label
                    rate: root.rate
                }
            }

            Component {
                id: ps1_status
                Ps1.LifeBar {
                    value: root.percent / 100
                    detail: [root.state_label.toUpperCase(), root.time_label, root.rate > 0 ? root.rate.toFixed(1) + " W" : ""].filter(t => t !== "").join("  ")
                }
            }

            Component {
                id: ps2_status
                Column {
                    spacing: 0

                    Ps2.ConfigRow {
                        width: parent.width
                        label: "Battery"
                        value: root.has_battery ? Math.round(root.percent) + "%" : "None"
                        level: root.has_battery ? root.percent / 100 : -1
                        level_color: root.percent <= 20 && root.state_label === "Discharging" ? Style.pal.warning : Style.pal.primary_light
                    }

                    Ps2.ConfigRow {
                        width: parent.width
                        label: "Status"
                        value: root.state_label
                    }

                    Ps2.ConfigRow {
                        visible: root.time_label !== ""
                        width: parent.width
                        label: "Time"
                        value: root.time_label
                    }

                    Ps2.ConfigRow {
                        visible: root.rate > 0
                        width: parent.width
                        label: "Rate"
                        value: root.rate.toFixed(1) + " W"
                    }
                }
            }

            Text {
                visible: !root.has_battery
                Layout.leftMargin: root.status_indent
                text: "No battery"
                color: root.st.text_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(4)
            }

            Text {
                visible: root.has_battery && !status_view.active && !watch_gauge.active
                Layout.leftMargin: root.status_indent
                text: (root.nes ? "BAT " : "") + Math.round(root.percent) + "%"
                color: root.st.text_strong
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(4)
            }

            Text {
                visible: root.has_battery && !status_view.active && !watch_gauge.active
                Layout.leftMargin: root.status_indent
                text: root.state_label
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Text {
                visible: root.has_battery && root.time_label !== "" && !status_view.active && !watch_gauge.active
                Layout.leftMargin: root.status_indent
                text: root.time_label
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            Text {
                visible: root.has_battery && root.rate > 0 && !status_view.active && !watch_gauge.active
                Layout.leftMargin: root.status_indent
                text: root.rate.toFixed(1) + " W"
                color: root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            FontMetrics {
                id: percent_metrics
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
            }

            LevelRow {
                id: brightness_row
                st: root.st
                glyph: "󰃠"
                label: "Brightness"
                percent: Backlight.percent
                selected: root.row_kind(root.selected) === "brightness"
                percent_width: root.percent_width
                capsule: root.st.level_layout === "capsule"
                floor: root.st.level_layout === "capsule" ? 1 : 0
                top_gap: 6
                onMoved: pct => Backlight.set_percent(pct)
                onWheeled: event => root.wheel_adjust("brightness", event)
            }

            LevelRow {
                id: kbd_row
                visible: Backlight.has_kbd
                st: root.st
                glyph: "󰌌"
                label: "Keyboard"
                percent: Backlight.kbd_percent
                selected: root.row_kind(root.selected) === "kbd"
                percent_width: root.percent_width
                capsule: root.st.level_layout === "capsule"
                top_gap: root.st.level_layout === "capsule" ? 4 : 0
                onMoved: pct => Backlight.kbd_set_percent(pct)
                onWheeled: event => root.wheel_adjust("kbd", event)
            }

            Text {
                visible: !root.ppd_available
                Layout.topMargin: 6
                text: "power-profiles-daemon not running"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
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
                    key: profile_row.modelData.key

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6 + profile_row.inset
                        anchors.rightMargin: 6 + profile_row.key_space
                        spacing: 6

                        RowLabel {
                            Layout.fillWidth: true
                            label: profile_row.modelData.label
                            color: profile_row.fg(PowerProfiles.profile === profile_row.modelData.value ? root.st.text_accent : root.st.text_fg)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.selected = profile_row.nav_index;
                            PowerProfiles.profile = profile_row.modelData.value;
                            ThemeAudio.play("confirm");
                        }
                    }
                }
            }
        }
    }
}
