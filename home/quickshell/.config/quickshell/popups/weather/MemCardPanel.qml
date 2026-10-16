import QtQuick
import qs.components
import qs.theme
import qs.services

// A BIOS panel: a rounded frame under a title strip, with `heading` at the left and `trailing` at the right.
// Children land in `body`, the frame's interior under the strip.
Rectangle {
    id: root

    property string heading: ""
    property string trailing: ""
    property color trailing_color: Style.text_strong
    default property alias content: body.data
    readonly property alias body: body
    // Height the frame adds around its content: strip, and the margins above the strip and around the body.
    readonly property real chrome_h: strip.height + 12

    radius: 6
    color: Qt.alpha(Theme.bg_shadow, 0.35)
    border.width: 2
    border.color: Style.frame_border_color
    clip: true

    Rectangle {
        id: strip
        x: 4
        y: 4
        width: parent.width - 8
        height: strip_text.implicitHeight + 4
        radius: 3
        color: "transparent"

        FadeFill {
            radius: parent.radius
            fill: Style.title_bg
        }

        Text {
            id: strip_text
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.heading
            color: Style.title_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            style: Text.Raised
            styleColor: Style.text_shadow
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.trailing
            color: root.trailing_color
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
        }
    }

    Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: strip.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 4
    }
}
