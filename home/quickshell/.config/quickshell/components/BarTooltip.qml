// home/quickshell/.config/quickshell/components/BarTooltip.qml
import QtQuick
import Quickshell
import "../theme"
import "../services"

PopupWindow {
    id: root

    color: "transparent"
    visible: Tooltip.visible && Tooltip.anchor_item !== null

    anchor.item: Tooltip.anchor_item
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY

    implicitWidth: label.implicitWidth + 16
    implicitHeight: label.implicitHeight + 10

    Rectangle {
        anchors.fill: parent
        color: Theme.ui_float_bg
        radius: 6
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: Tooltip.text
        color: Theme.ui_float_fg
        font.family: Theme.font_family
        font.pixelSize: Theme.popup_font_size
        horizontalAlignment: Text.AlignHCenter
    }
}
