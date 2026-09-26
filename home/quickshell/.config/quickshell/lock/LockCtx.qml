// home/quickshell/.config/quickshell/lock/LockCtx.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../services"

// Everything a lock skin draws: live status plus the auth state, which the lock (or the preview) sets.
QtObject {
    id: root

    property int buffer_length: 0
    property bool checking: false
    property bool failed: false
    property int fail_count: 0
    property string message: ""
    property bool caps_lock: false
    property bool typing: false
    // PAM accepted; the skin plays its unlock before the session opens.
    property bool granted: false
    property bool saver: false
    // Loops run only while this is true: on AC and not left alone for long.
    property bool animate: Power.on_ac
    // Set by the preview to pin a phase.
    property string forced_phase: ""

    readonly property string phase: {
        if (root.forced_phase !== "") return root.forced_phase;
        if (root.granted) return "unlock";
        if (root.failed) return "wrong";
        if (root.saver) return "saver";
        if (root.buffer_length > 0 || root.checking) return "typing";
        return "idle";
    }

    signal rejected

    property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
    readonly property date now: root.clock.date
    readonly property string time_text: Qt.formatTime(root.now, "HH:mm")
    readonly property string time_12: (root.now.getHours() % 12 || 12) + ":" + Qt.formatTime(root.now, "mm")
    readonly property string ampm: root.now.getHours() < 12 ? "AM" : "PM"
    readonly property string date_text: Qt.formatDate(root.now, "dddd, MMMM d")

    readonly property string user: Quickshell.env("USER") || ""
    property FileView hostname_file: FileView {
        path: "/etc/hostname"
        blockLoading: true
        printErrors: false
    }
    readonly property string host: root.hostname_file.text().trim() || Quickshell.env("HOSTNAME") || ""

    readonly property var battery_device: UPower.displayDevice
    readonly property bool has_battery: !!root.battery_device && root.battery_device.ready && root.battery_device.isLaptopBattery
    readonly property int battery_percent: root.has_battery ? Math.round(root.battery_device.percentage * 100) : 0
    readonly property bool charging: root.has_battery && (root.battery_device.state === UPowerDeviceState.Charging || root.battery_device.state === UPowerDeviceState.PendingCharge || root.battery_device.state === UPowerDeviceState.FullyCharged)

    readonly property bool has_weather: WeatherState.has_data && !!WeatherState.current
    readonly property string weather_temp: root.has_weather ? Math.round(WeatherState.current.temp) + "°" + WeatherState.unit_symbol() : ""
    readonly property string weather_cond: root.has_weather ? WeatherState.current.cond : ""

    readonly property var player: MediaState.active
    readonly property bool has_media: !!root.player && (root.player.trackTitle || "") !== ""
    readonly property string media_title: root.has_media ? root.player.trackTitle : ""
    readonly property string media_artist: root.has_media ? root.player.trackArtist || "" : ""
    readonly property string media_status: root.has_media ? (root.player.isPlaying ? "Playing" : "Paused") : ""

    readonly property int notifications: NotificationState.unread

    // No calendar source yet; skins show the event only when this turns true.
    readonly property bool has_event: false
    readonly property string event_time: ""
    readonly property string event_title: ""
}
