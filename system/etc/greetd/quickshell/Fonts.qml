// /etc/greetd/quickshell/Fonts.qml
import QtQuick
import "theme/FontFiles.js" as FontFiles

// Registers every bundled font synchronously at creation, so a skin that measures text once (TextMetrics, PathText) already sees its family.
// Not a FolderListModel: that fills asynchronously and the MGS2 title was laid out in the fallback font.
Item {
    property bool ready: false

    ListModel {
        id: fonts
    }

    Instantiator {
        model: fonts
        delegate: FontLoader {
            required property string file
            source: Qt.resolvedUrl("assets/fonts/" + file)
        }
    }

    Component.onCompleted: {
        for (const files of Object.values(FontFiles.family_files)) {
            for (const file of files) fonts.append({ file: file });
        }
        ready = true;
    }
}
