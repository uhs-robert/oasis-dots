// home/quickshell/.config/quickshell/components/goldeneye/WatchReadout.qml
import QtQuick
import "../../theme"
import "../../lock/skins/goldeneye" as Watch
import "../../lock/skins/goldeneye/Watch.js" as W

// A small watch face for the pickers' readouts: a black dial, two caption words and a green panel that holds the children.
Item {
    id: root

    property string label: "OASIS WATCH"
    property string status: ""
    default property alias content: body.data
    readonly property real caption_width: label_text.implicitWidth + status_text.implicitWidth + 36

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Style.wk.frame
        border.width: 2
        border.color: Style.wk.rim
    }

    Text {
        id: label_text
        x: 10
        y: 4
        text: root.label
        color: Style.wk.dim
        font.family: W.mono_font
        font.pixelSize: Style.fs(-7)
        font.letterSpacing: 1
    }

    Text {
        id: status_text
        x: root.width - width - 10
        y: 4
        text: root.status
        color: Style.wk.dim
        font.family: W.mono_font
        font.pixelSize: Style.fs(-7)
        font.letterSpacing: 1
    }

    Watch.PanelShape {
        x: 5
        y: 17
        width: root.width - 10
        height: root.height - 22
        cut: 6
        notches: false
        top_color: Style.wk.panel_top
        edge: Style.wk.edge
        bottom_color: Style.wk.panel_bottom

        Item {
            id: body
            anchors.fill: parent
        }
    }
}
