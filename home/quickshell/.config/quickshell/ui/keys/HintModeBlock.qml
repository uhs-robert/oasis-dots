import QtQuick
import qs.theme

// The mode chip at the left of a hint bar: the mode's name in the title style, with any status lines given as children
// stacked under it.
Rectangle {
    id: root
    property string title: ""
    default property alias lines: block.data

    width: block.implicitWidth + 24
    height: block.implicitHeight + 14
    radius: Math.min(Style.frame_radius, 4)
    color: Style.title_bg
    Column {
        id: block
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.title
            color: Style.title_fg
            font.family: Style.title_font_family
            font.pixelSize: Style.fs(0)
            font.bold: true
        }
    }
}
