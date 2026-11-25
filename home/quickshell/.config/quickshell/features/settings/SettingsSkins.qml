pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.theme

// The settings skins on disk. A style without a file draws with Default.
Singleton {
    id: root

    readonly property var files: {
        const out = [];
        for (let i = 0; i < skin_files.count; i++) out.push(skin_files.get(i, "fileName"));
        return out;
    }

    function file_for(style_name) {
        return style_name.charAt(0).toUpperCase() + style_name.slice(1) + ".qml";
    }

    function has(style_name) {
        return root.files.indexOf(root.file_for(style_name)) >= 0;
    }

    // Default while the folder listing is still loading, so the first frame never has no skin.
    function url_for(style_name) {
        return Qt.resolvedUrl("skins/" + (root.has(style_name) ? root.file_for(style_name) : "Default.qml"));
    }

    FolderListModel {
        id: skin_files
        folder: Qt.resolvedUrl("skins")
        nameFilters: ["*.qml"]
        showDirs: false
    }
}
