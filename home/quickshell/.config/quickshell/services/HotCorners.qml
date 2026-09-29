// home/quickshell/.config/quickshell/services/HotCorners.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"

// Whether the screen corners act as hot corners, saved in hot_corners.json.
Singleton {
    id: root

    property bool enabled: true

    function set_enabled(on) {
        root.enabled = on;
        file.setText(JSON.stringify({ enabled: on }));
    }

    FileView {
        id: file
        path: Style.state_dir + "/hot_corners.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                root.enabled = JSON.parse(text()).enabled !== false;
            } catch (e) {
                console.warn("HotCorners: invalid hot_corners.json (" + e + ")");
            }
        }
        onLoadFailed: error => {}
    }
}
