// home/quickshell/.config/quickshell/services/SystemStat.qml
pragma Singleton
import QtQuick
import Quickshell

// Per-screen, in-memory override of which SysStats value the system module shows.
Singleton {
    id: root

    property var overrides: ({})

    function stat_for(screen_name, fallback) {
        return root.overrides[screen_name] || fallback;
    }

    function set_override(screen_name, stat) {
        const next = Object.assign({}, root.overrides);
        next[screen_name] = stat;
        root.overrides = next;
    }
}
