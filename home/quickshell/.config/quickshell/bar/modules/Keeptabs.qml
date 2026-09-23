// home/quickshell/.config/quickshell/bar/modules/Keeptabs.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property bool shown: KeeptabsState.available
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    onIslandChanged: if (root.island) Popups.register_default("keeptabs", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("keeptabs", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: 4
        color: Theme.bg_surface
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: KeeptabsState.runs

            Text {
                required property var modelData

                // Pango rise is in 1/1024 pt; keeptabs uses +-1024 to bob the running icon.
                y: -modelData.rise / 1024
                text: modelData.text
                color: modelData.color || Theme.theme_primary
                font.family: Theme.font_family
                font.pixelSize: /[-]|[\uDB80-\uDBFF]/.test(modelData.text) ? Theme.glyph_size : Theme.font_size
            }
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, KeeptabsState.tooltip.replace(/\t/g, "  "));
            else Tooltip.hide();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("keeptabs", root.island, root.island_color, root.screen_name)
    }
}
