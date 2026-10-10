// home/quickshell/.config/quickshell/bar/modules/BarModule.qml
import QtQuick
import "../../theme"
import "../../services"

Item {
    id: root

    property string module_name: ""
    property bool has_popup: true
    property bool compact: false
    property string screen_name: ""
    property int bar_height: 30
    property Item island: null
    property color island_color: Theme.bg_core
    property bool shown: true
    property string tooltip_text: ""
    property string tooltip_title: module_name
    property bool wash: true
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
