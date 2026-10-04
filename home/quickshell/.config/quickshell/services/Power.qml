// home/quickshell/.config/quickshell/services/Power.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../theme"

Singleton {
    id: root

    readonly property bool on_ac: !UPower.onBattery

    property bool ppd_available: false

    function probe_ppd() {
        ppd_check_proc.running = true;
    }

    function format_time(seconds) {
        if (seconds <= 0) return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    // busctl exits non-zero when the daemon is not D-Bus activatable.
    Process {
        id: ppd_check_proc
        command: ["busctl", "--system", "introspect", "org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles"]
        running: true
        onExited: code => root.ppd_available = code === 0
    }

    readonly property var actions: ["lock", "logout", "reboot", "poweroff"]
    readonly property var labels: ({ lock: "Lock", logout: "Logout", reboot: "Reboot", poweroff: "Power Off" })
    readonly property var glyphs: ({ lock: "󰌾", logout: "󰍃", reboot: "󰜉", poweroff: "󰐥" })

    // Lock follows the popup's text color, so it takes the popup's style tokens.
    function color(action, st) {
        return ({ lock: st.text_fg, logout: Style.pal.info, reboot: Style.pal.warning, poweroff: Style.pal.danger })[action];
    }

    function run(action) {
        if (action === "lock") {
            Quickshell.execDetached(["sh", "-c", "~/.config/hypr/scripts/lock-screen.sh"]);
        } else if (action === "logout") {
            Quickshell.execDetached(["sh", "-c", "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch \"hl.dsp.exit()\""]);
        } else if (action === "reboot") {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (action === "poweroff") {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }
}
