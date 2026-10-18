// /etc/greetd/quickshell/Fonts.qml
import QtQuick
import Qt.labs.folderlistmodel

// Registers the fonts synced into assets/fonts/.
Instantiator {
    model: FolderListModel {
        folder: Qt.resolvedUrl("assets/fonts")
        nameFilters: ["*.ttf", "*.otf"]
        showDirs: false
    }

    delegate: FontLoader {
        required property url fileUrl
        source: fileUrl
    }
}
