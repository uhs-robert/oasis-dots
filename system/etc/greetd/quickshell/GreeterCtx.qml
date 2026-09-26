// /etc/greetd/quickshell/GreeterCtx.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "theme"
import "lock/Tints.js" as Tints

// The lock skins' ctx for the greeter: the same fields as the shell's LockCtx, minus media, weather and notifications.
QtObject {
    id: root

    property int buffer_length: 0
    property bool checking: false
    property bool failed: false
    property int fail_count: 0
    property string message: ""
    property bool caps_lock: false
    property bool typing: false
    property bool granted: false
    property bool saver: false
    property bool animate: !UPower.onBattery
    property string forced_phase: ""
    property string user: ""
    property string tint: "primary"

    readonly property string phase: {
        if (root.forced_phase !== "") return root.forced_phase;
        if (root.granted) return "unlock";
        if (root.failed) return "wrong";
        if (root.saver) return "saver";
        if (root.buffer_length > 0 || root.checking) return "typing";
        return "idle";
    }

    signal rejected

    readonly property var tint_pair: Tints.pair(Theme, root.tint)
    readonly property color tint_base: root.tint_pair[0]
    readonly property color tint_bright: root.tint_pair[1]
    readonly property color tint_strong: root.tint === "primary" ? Theme.theme_primary_strong : root.tint === "secondary" ? Theme.theme_secondary_strong : root.tint_base

    property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
    readonly property date now: root.clock.date
    readonly property string time_text: Qt.formatTime(root.now, "HH:mm")
    readonly property string time_12: (root.now.getHours() % 12 || 12) + ":" + Qt.formatTime(root.now, "mm")
    readonly property string ampm: root.now.getHours() < 12 ? "AM" : "PM"
    readonly property string date_text: Qt.formatDate(root.now, "dddd, MMMM d")

    property FileView hostname_file: FileView {
        path: "/etc/hostname"
        blockLoading: true
        printErrors: false
    }
    readonly property string host: root.hostname_file.text().trim()

    readonly property var battery_device: UPower.displayDevice
    readonly property bool has_battery: !!root.battery_device && root.battery_device.ready && root.battery_device.isLaptopBattery
    readonly property int battery_percent: root.has_battery ? Math.round(root.battery_device.percentage * 100) : 0
    readonly property bool charging: root.has_battery && (root.battery_device.state === UPowerDeviceState.Charging || root.battery_device.state === UPowerDeviceState.PendingCharge || root.battery_device.state === UPowerDeviceState.FullyCharged)

    readonly property bool has_weather: false
    readonly property string weather_temp: ""
    readonly property string weather_cond: ""
    readonly property bool has_media: false
    readonly property string media_title: ""
    readonly property string media_artist: ""
    readonly property string media_status: ""
    readonly property int notifications: 0
    readonly property bool has_event: false
    readonly property string event_time: ""
    readonly property string event_title: ""
}
