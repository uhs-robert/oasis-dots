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
    // A module opts in to hover-open by setting this; Media keeps its own HoverPopup and stays off.
    property bool hover_popup: false
    // The module's own gate on top of the opt-in, e.g. nothing to show yet.
    property bool hover_ready: true
    readonly property bool hover_active: root.shown && root.has_popup && root.hover_popup && root.hover_ready && Popups.hover_popups
    property string tooltip_text: ""
    property string tooltip_title: module_name
    property bool wash: true
    // The width the content may use on a side bar: the bar's thickness less the island's capsule inset, its border on both sides and the air. The floating strip's inset is not taken off: it grows the bar window, the plate stays bar_height thick.
    readonly property real cross: VerticalLayout.cross_width(root.bar_height, Style.bar_capsule + Style.bar_border_width * 2 + VerticalLayout.air_px)
    readonly property alias hovered: hover_handler.hovered

    visible: shown

    // The click entry: with hover-open active it goes through the helper so a click pins, or closes without a reopen under the pointer.
    function toggle_popup() {
        if (root.hover_active) hover.click();
        else Popups.toggle(root.module_name, root.island, root.island_color, root.screen_name);
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

    HoverPopup {
        id: hover
        popup_name: root.module_name
        module: root
        enabled: root.hover_active
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            // The popup replaces the tooltip where hover opens it.
            if (hovered && !root.hover_active) Tooltip.show(root, root.tooltip_text, root.tooltip_title);
            else Tooltip.hide(root);
        }
    }
}
