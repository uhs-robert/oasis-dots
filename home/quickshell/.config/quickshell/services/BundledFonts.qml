// home/quickshell/.config/quickshell/services/BundledFonts.qml
import QtQuick
import Qt.labs.folderlistmodel

// Registers every font in fonts/ for the whole process; text relayouts once each lands.
Instantiator {
    model: FolderListModel {
        folder: Qt.resolvedUrl("../fonts")
        nameFilters: ["*.ttf", "*.otf"]
        showDirs: false
    }

    delegate: FontLoader {
        required property url fileUrl
        source: fileUrl
    }
}
