// home/quickshell/.config/quickshell/services/TimeFormat.qml
pragma Singleton
import QtQuick
import Quickshell

// Clock-time text for popups and cards; follows the weather `time_format` setting.
Singleton {
    id: root

    readonly property bool h24: WeatherState.settings.time_format === "24h"

    function format(date) {
        return Qt.formatTime(date, root.h24 ? "HH:mm" : "h:mmap");
    }
}
