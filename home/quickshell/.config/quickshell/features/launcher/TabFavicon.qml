import QtQuick
import qs.theme
import "FirefoxTabs.js" as FirefoxTabs

// A Firefox tab's favicon, or a globe glyph while it has none the bar loads without the network.
Item {
    id: root

    property string url: ""
    property real size: Style.px(16)

    implicitWidth: root.size
    implicitHeight: root.size

    Image {
        id: icon
        anchors.fill: parent
        visible: icon.status === Image.Ready
        source: FirefoxTabs.favicon_source(root.url)
        sourceSize: Qt.size(Math.ceil(root.size), Math.ceil(root.size))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    Text {
        anchors.centerIn: parent
        visible: !icon.visible
        text: "\u{f0ac}"
        color: Style.text_muted
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: Math.round(root.size * 0.9)
    }
}
