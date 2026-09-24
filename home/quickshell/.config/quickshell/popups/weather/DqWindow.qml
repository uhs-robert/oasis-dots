// home/quickshell/.config/quickshell/popups/weather/DqWindow.qml
import QtQuick
import "../../theme"

// A Dragon Quest window: black fill inside a white double border, with an optional name set into the top edge.
Rectangle {
    id: root

    property string title: ""
    property int inner_gap: 3

    color: Theme.bg_crust
    border.width: 2
    border.color: Theme.fg_strong
    radius: 3

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2 + root.inner_gap
        color: "transparent"
        border.width: 1
        border.color: Theme.fg_strong
        radius: 1
    }

    Rectangle {
        visible: root.title !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 24, name.implicitWidth + 8)
        height: name.implicitHeight
        y: -height / 2 + 1
        color: Theme.bg_crust

        Text {
            id: name
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.title
            color: Theme.fg_strong
            font.family: Style.font_family
            font.pixelSize: Style.font_size - 6
        }
    }
}
