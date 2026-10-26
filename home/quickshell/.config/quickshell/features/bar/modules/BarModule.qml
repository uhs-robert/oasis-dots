import QtQuick
import qs.theme
import qs.features.popups
import "../VerticalLayout.js" as VerticalLayout

Item {
    id: root

    property string module_name: ""
    property bool has_popup: true
    property bool compact: false
    property string screen_name: ""
    property int bar_height: 30
    // On a left or right bar. A module lays its content out in a column with ModuleRow and VerticalText; one that does not still draws horizontally.
    property bool vertical: false
    property Item island: null
    property color island_color: Theme.bg_core
    property bool shown: true
    property string tooltip_text: ""
    property string tooltip_title: module_name
    property bool wash: true
    // The width the content may use on a side bar: the bar's thickness less the island's inset (capsule, floating strip), its border on both sides and 4 px of air.
    readonly property real cross: VerticalLayout.cross_width(root.bar_height, Style.bar_capsule + (Style.strip_floats ? Style.bar_strip_inset : 0) + Style.bar_border_width * 2 + 4)
    readonly property alias hovered: hover_handler.hovered

    visible: shown

    function toggle_popup() {
        Popups.toggle(root.module_name, root.island, root.island_color, root.screen_name);
    }

    onIslandChanged: if (root.has_popup && root.island) Popups.register_default(root.module_name, root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: if (root.has_popup) Popups.unregister(root.module_name, root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: root.wash && hover_handler.hovered ? 0.5 : 0
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text, root.tooltip_title);
            else Tooltip.hide(root);
        }
    }
}
