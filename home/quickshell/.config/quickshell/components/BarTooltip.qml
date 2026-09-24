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
        color: Style.bar_tip_bg
        radius: Style.bar_radius(6)
        border.width: Style.bar_tip_border_width
        border.color: Style.bar_tip_border_color
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: Tooltip.text
        color: Style.bar_tip_fg
        font.family: Style.bar_font_family
        font.pixelSize: Theme.popup_font_size
        horizontalAlignment: Text.AlignHCenter
    }
}
