// home/quickshell/.config/quickshell/services/GreeterSync.qml
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../theme"

// Keeps the login screen's data (lock style, tint, theme) in /var/lib/qs-greeter current; does nothing when that directory is absent.
Scope {
    id: root

    readonly property string theme_path: Quickshell.shellDir + "/theme/theme.json"

    // The greeter's lock style: follow resolves to the bar style, and a style without a skin to simple.
    function resolved_lock() {
        const name = Style.lock_style === "follow" ? Style.saved_name : Style.lock_style;
        if (name === "simple") return "simple";
        const file = name.charAt(0).toUpperCase() + name.slice(1) + ".qml";
        for (let i = 0; i < skin_files.count; i++) {
            if (skin_files.get(i, "fileName") === file) return name;
        }
        return "simple";
    }

    function write() {
        const data = {
            user: Quickshell.env("USER") || "",
            lock_style: root.resolved_lock(),
            lock_tint: Style.lock_tint,
            session: "Hyprland"
        };
        Quickshell.execDetached([Quickshell.shellDir + "/scripts/greeter-data", JSON.stringify(data), root.theme_path]);
    }

    function schedule() {
        debounce.restart();
    }

    Timer {
        id: debounce
        interval: 1500
        onTriggered: root.write()
    }

    FolderListModel {
        id: skin_files
        folder: Qt.resolvedUrl("../lock/skins")
        nameFilters: ["*.qml"]
        showDirs: false
        onStatusChanged: {
            if (status === FolderListModel.Ready) root.schedule();
        }
    }

    Connections {
        target: Style
        function onSaved_nameChanged() { root.schedule(); }
        function onLock_styleChanged() { root.schedule(); }
        function onLock_tintChanged() { root.schedule(); }
    }

    FileView {
        path: root.theme_path
        watchChanges: true
        printErrors: false
        onFileChanged: root.schedule()
    }
}
