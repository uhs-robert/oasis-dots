// home/quickshell/.config/quickshell/services/Power.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../theme"

Singleton {
    id: root

    readonly property bool on_ac: !UPower.onBattery

    readonly property var actions: ["lock", "logout", "reboot", "poweroff"]
    readonly property var labels: ({ lock: "Lock", logout: "Logout", reboot: "Reboot", poweroff: "Power Off" })
    readonly property var glyphs: ({ lock: "󰌾", logout: "󰍃", reboot: "󰜉", poweroff: "󰐥" })

    // Lock follows the popup's text color, so it takes the popup's style tokens.
    function color(action, st) {
        return ({ lock: st.text_fg, logout: Theme.info, reboot: Theme.warning, poweroff: Theme.theme_label })[action];
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
