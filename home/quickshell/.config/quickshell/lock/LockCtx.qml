// home/quickshell/.config/quickshell/lock/LockCtx.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../services"
import "../theme"
import "Tints.js" as Tints

// Everything a lock skin draws: live status plus the auth state, which the lock (or the preview) sets.
QtObject {
    id: root

    property int buffer_length: 0
    property bool checking: false
    property bool failed: false
    property int fail_count: 0
    property string message: ""
    // A PAM prompt other than the password one, e.g. for a second factor.
    property string prompt: ""
    property bool caps_lock: false
    property bool typing: false
    // INSERT mode: every key types the password and skins get no navigation keys.
    property bool insert: false
    // PAM accepted; the skin plays its unlock before the session opens.
    property bool granted: false
    property bool saver: false
    // Loops run only while this is true: on AC and not left alone for long.
    property bool animate: Power.on_ac
    // The lock tint family (Style.lock_tint): a base and a bright shade that skins derive their colours from.
    property string tint: Style.lock_tint
    // The GoldenEye skin's Watch colours choice (Style option), Theme or Classic.
    readonly property string watch_colors: Style.watch_mode
    readonly property var tint_pair: Tints.pair(Theme, root.tint)
    readonly property color tint_base: root.tint_pair[0]
    readonly property color tint_bright: root.tint_pair[1]
    readonly property color tint_strong: root.tint === "primary" ? Theme.theme_primary_strong : root.tint === "secondary" ? Theme.theme_secondary_strong : root.tint_base
    // Output name to a pre-lock screenshot URL; skins opt in by reading it for their screen_name.
    property var backdrops: ({})
    // pixelate, blur or off (Style.lock_backdrop).
    property string backdrop_mode: Style.lock_backdrop
    // Set by the preview to pin a phase.
    property string forced_phase: ""
    // A skin's own sub-screen, shared by every output; the skin steps it from handle_key and "" is its first.
    property string scene: ""

    readonly property string phase: {
        if (root.forced_phase !== "") return root.forced_phase;
        if (root.granted) return "unlock";
        if (root.failed) return "wrong";
        if (root.saver) return "saver";
        if (root.buffer_length > 0 || root.checking) return "typing";
        return "idle";
    }

    signal rejected
    // A skin asks for "reboot", "poweroff" or "firmware" after its own confirmation; only a ctx with power_live acts on it.
    signal power_request(string action)
    property bool power_live: false
    // Audio: only a ctx with sound plays any (the lock and the full preview, never thumbnails); one skin instance, the owner, plays for all outputs.
    property bool sound: false
    property bool music: Style.lock_music
    // False while the lock waits for a key press; skins keep music silent until then.
    property bool music_armed: true
    readonly property real music_volume: ThemeAudio.music_volume
    // The login screen rather than the lock; skins may play more there.
    property bool login: false
    // The lock preview: a skin can show what it otherwise keeps for the login screen, such as its title music.
    property bool preview: false
    property var sound_owner: null
    // A skin's named sound effect, heard by the owner.
    signal cue(string name)

    property SystemClock clock: SystemClock {
        precision: SystemClock.Minutes
    }
    readonly property date now: root.clock.date
    readonly property string time_text: TimeFormat.format(root.now)
    readonly property string time_12: (root.now.getHours() % 12 || 12) + ":" + Qt.formatTime(root.now, "mm")
    readonly property string ampm: root.now.getHours() < 12 ? "AM" : "PM"
    readonly property string date_text: Qt.formatDate(root.now, "dddd, MMMM d")

    readonly property string user: Quickshell.env("USER") || ""
    property FileView passwd_file: FileView {
        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
    }
    // Only this user, as {name, full}; the greeter lists every login user.
    readonly property var users: {
        const line = root.passwd_file.text().split("\n").find(l => l.split(":")[0] === root.user) || "";
        return [{ name: root.user, full: line.split(":")[4] || "" }];
    }

    function face_urls(name) {
        return name === root.user ? ["file://" + Quickshell.env("HOME") + "/.face"] : [];
    }
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
