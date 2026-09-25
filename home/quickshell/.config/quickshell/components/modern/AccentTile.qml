// home/quickshell/.config/quickshell/components/modern/AccentTile.qml
import QtQuick
import Quickshell
import "../../theme"
import ".."

// A rounded square in the selection gradient holding a glyph or an icon.
Rectangle {
    id: root

    property string glyph: ""
    // A notification whose image, else app icon, fills the tile.
    property var notification: null
    property url icon: !root.notification ? "" : root.notification.image !== "" ? root.notification.image : root.notification.appIcon !== "" ? Quickshell.iconPath(root.notification.appIcon, true) : ""
    property bool dimmed: false
    property int size: 36
    // Tints the tile from this color instead of the selection gradient.
    property color tint: "transparent"

    implicitWidth: root.size
    implicitHeight: root.size
    radius: Math.round(root.size * 0.28)
    opacity: root.dimmed ? 0.55 : 1
    gradient: Gradient {
        GradientStop { position: 0; color: root.tint.a > 0 ? Qt.tint(root.tint, Qt.alpha(Theme.fg_strong, 0.12)) : Style.selection_shade.a > 0 ? Style.selection_shade : Style.selection_bg }
        GradientStop { position: 1; color: root.tint.a > 0 ? Qt.tint(root.tint, Qt.alpha(Theme.theme_primary_strong, 0.4)) : Style.selection_bg }
    }

    Sheen {
        color_top: Style.sheen
        corner: root.radius
    }

    Text {
        visible: root.icon.toString() === ""
        anchors.centerIn: parent
        text: root.glyph
        color: Style.selection_fg
        font.family: Theme.font_family
        font.pixelSize: Math.round(root.size * 0.55)
    }

    Image {
        visible: root.icon.toString() !== ""
        anchors.centerIn: parent
        width: Math.round(root.size * 0.66)
        height: width
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        source: root.icon
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
