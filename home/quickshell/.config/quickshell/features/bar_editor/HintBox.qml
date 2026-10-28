import QtQuick
import qs.theme

// The plate the hint bar sits on, at the screen edge the bar is not on. A plain Rectangle so the harness can place it in an Item.
Rectangle {
    id: root
    property bool on_top: false
    property bool carrying: false
    property bool vertical: false
    readonly property Item content: hint_row

    anchors.horizontalCenter: parent.horizontalCenter
    // y rather than top/bottom anchors: flipping them between undefined and a parent edge left both set and stretched the plate.
    y: root.on_top ? 24 : parent.height - root.height - 24
    width: Math.min(parent.width - 32, hint_row.implicitWidth + 28)
    height: hint_row.implicitHeight + 16
    radius: Style.frame_radius
    color: Style.frame_color
    border.width: Style.frame_border_width
    border.color: Style.frame_border_color
    HintContent {
        id: hint_row
        anchors.centerIn: parent
        carrying: root.carrying
        vertical: root.vertical
    }
}
