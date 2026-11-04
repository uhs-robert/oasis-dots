import QtQuick
import qs.theme

// A Firefox tab's last captured image, dimmed while the tab is unloaded, or its favicon (and title, when `titled`)
// on a plain tile while it has none.
Item {
    id: root

    property var entry: ({})
    property string source: ""
    property bool crop: true
    property bool titled: false
    // A refresh keeps the tab's old image up until the new one is decoded, so a capture never blanks it to the
    // favicon tile for a frame. Only the same tab's image: a row rebound to another tab shows its tile meanwhile.
    readonly property bool shown: image.status === Image.Ready || (image.status === Image.Loading && root.ready_id !== "" && root.ready_id === String(root.entry.id || ""))
    property string ready_id: ""

    clip: true

    Rectangle {
        anchors.fill: parent
        radius: Style.radius(4)
        color: Style.pal.bg_surface
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
        fillMode: root.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        // Off so a refreshed file is read from disk even if its URL repeats; the source's time query is the main guard.
        cache: false
        asynchronous: true
        retainWhileLoading: true
        visible: root.shown
        onStatusChanged: {
            if (image.status === Image.Ready) root.ready_id = String(root.entry.id || "");
            else if (image.status !== Image.Loading) root.ready_id = "";
        }
        opacity: root.entry.discarded ? 0.4 : 1
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 16
        spacing: 6
        visible: !root.shown

        TabFavicon {
            anchors.horizontalCenter: parent.horizontalCenter
            url: root.entry.fav_icon_url || ""
            size: Math.max(Style.px(14), Math.min(Style.px(48), root.height * 0.3))
        }

        Text {
            visible: root.titled
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.entry.label || ""
            textFormat: Text.PlainText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(0)
        }
    }
}
