// home/quickshell/.config/quickshell/popups/media/AlbumArt.qml
import QtQuick
import QtQuick.Effects
import "../../theme"

// Rounded album art tile with a drop shadow and a note-glyph fallback.
Item {
    id: root

    property string source: ""
    property bool has_art: false

    Rectangle {
        id: art_shadow_source
        anchors.fill: parent
        radius: Style.radius(12)
        color: Style.pal.bg_shadow
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        anchors.topMargin: 8
        visible: root.has_art && art_image.status === Image.Ready
        source: art_shadow_source
        blurEnabled: true
        blur: 0.6
        blurMax: 32
        opacity: 0.55
        z: -1
    }

    Rectangle {
        anchors.fill: parent
        radius: Style.radius(12)
        color: Style.pal.bg_surface
        visible: !root.has_art || art_image.status !== Image.Ready
    }

    Text {
        anchors.centerIn: parent
        visible: !root.has_art || art_image.status !== Image.Ready
        text: "\u{f001}"
        color: Style.text_dim
        font.family: Style.font_family
        font.pixelSize: 48
    }

    Rectangle {
        id: art_mask
        anchors.fill: parent
        radius: Style.radius(12)
        visible: false
        layer.enabled: true
    }

    Image {
        id: art_image
        anchors.fill: parent
        visible: false
        source: root.source
        sourceSize.width: width * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.has_art && art_image.status === Image.Ready
        source: art_image
        maskEnabled: true
        maskSource: art_mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
