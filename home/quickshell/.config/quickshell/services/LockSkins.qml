// home/quickshell/.config/quickshell/services/LockSkins.qml
pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import "../theme"

// The lock skins on disk, and the lock or login screens they make selectable.
Singleton {
    id: root

    readonly property bool ready: skin_files.status === FolderListModel.Ready
    readonly property var files: {
        const out = [];
        for (let i = 0; i < skin_files.count; i++) out.push(skin_files.get(i, "fileName"));
        return out;
    }
    // Styles with a skin, in bar order, then the lock-only ones.
    readonly property var names: Style.names.concat(Style.lock_only_names).filter(n => root.has(n))

    function file_for(style_name) {
        return style_name.charAt(0).toUpperCase() + style_name.slice(1) + ".qml";
    }

    function has(style_name) {
        return root.files.indexOf(root.file_for(style_name)) >= 0;
    }

    function meta(style_name) {
        return Style.lock_skins[style_name] || {};
    }

    function url_for(style_name) {
        return root.has(style_name) ? Qt.resolvedUrl("../lock/skins/" + root.file_for(style_name)) : Qt.resolvedUrl("../lock/LockScreen.qml");
    }

    FolderListModel {
        id: skin_files
        folder: Qt.resolvedUrl("../lock/skins")
        nameFilters: ["*.qml"]
        showDirs: false
    }
}
