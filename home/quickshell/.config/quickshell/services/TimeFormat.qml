// home/quickshell/.config/quickshell/services/TimeFormat.qml
pragma Singleton
import QtQuick
import Quickshell

// Clock-time text for every clock; follows the Settings > Clock time format.
Singleton {
    id: root

    readonly property string choice: ClockSettings.time_format
    readonly property bool locale_12h: /[aA]/.test(Qt.locale().timeFormat(Locale.ShortFormat).replace(/'[^']*'/g, ""))
    readonly property bool h24: root.choice === "24h" || (root.choice === "locale" && !root.locale_12h)

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n;
    }

    function format(date) {
        return Qt.formatTime(date, root.h24 ? "HH:mm" : "h:mmap");
    }

    // Padded "HH:mm" or "hh:mm", with ":ss" when asked.
    function digits(date, seconds) {
        const h = root.h24 ? date.getHours() : date.getHours() % 12 || 12;
        const hm = root.pad2(h) + ":" + root.pad2(date.getMinutes());
        return seconds ? hm + ":" + root.pad2(date.getSeconds()) : hm;
    }

    // "AM" or "PM" in 12-hour mode, empty in 24-hour mode.
    function meridiem(date) {
        return root.h24 ? "" : date.getHours() < 12 ? "AM" : "PM";
    }

    // Hour-only forecast label: "3pm" or "15".
    function hour(date) {
        const h = date.getHours();
        return root.h24 ? root.pad2(h) : (h % 12 || 12) + (h < 12 ? "am" : "pm");
    }
}
