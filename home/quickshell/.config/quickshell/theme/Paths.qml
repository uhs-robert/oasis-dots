// home/quickshell/.config/quickshell/theme/Paths.qml
pragma Singleton
import QtQuick
import Quickshell

// XDG base directories, resolved once.
Singleton {
    id: root

    function xdg(name, fallback) {
        const value = Quickshell.env(name);
        return value && value !== "" ? value : Quickshell.env("HOME") + fallback;
    }

    readonly property string state_dir: root.xdg("XDG_STATE_HOME", "/.local/state") + "/quickshell"
    readonly property string hypr_state_dir: root.xdg("XDG_STATE_HOME", "/.local/state") + "/hypr"
    readonly property string cache_dir: root.xdg("XDG_CACHE_HOME", "/.cache") + "/quickshell"
    readonly property string data_dir: root.xdg("XDG_DATA_HOME", "/.local/share") + "/quickshell"
}
