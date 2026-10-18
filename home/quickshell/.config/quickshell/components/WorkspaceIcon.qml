import QtQuick
import Quickshell.Widgets
import qs.features.popups
import qs.features.windows

// An app on a bar workspace: click focuses its window, middle-click closes it, hover shows its title, dragging onto another workspace's WorkspaceDropTarget moves it; `host` is the Workspaces module.
Item {
    id: root

    required property var modelData
    property var host: null
    property int workspace_id: 0
    property real glyph: 16
    property real icon_opacity: 1
    // Art drawn under the icon, e.g. a materia slot.
    default property alias underlay: under.data

    readonly property string window_address: root.modelData.address
    readonly property bool dragging: drag_handler.active

    width: root.glyph
    height: root.glyph

    Item {
        id: under
        anchors.fill: parent
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: root.glyph
        opacity: root.dragging ? 0.35 : root.icon_opacity
        source: WindowState.icon_for(root.modelData)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) root.host.focus_toplevel(root.workspace_id, root.modelData.address);
            else WindowState.close(root.modelData.address);
        }
    }

    DragHandler {
        id: drag_handler
        target: null
        // Qt only delivers a drop through Drag.drop(); letting Drag.active fall to false would cancel the drag.
        onActiveChanged: {
            if (active) {
                Tooltip.hide(root);
                ghost.Drag.start();
            } else {
                ghost.Drag.drop();
            }
        }
    }

    // The icon stays in its layout; this copy follows the pointer. It sits on the bar window's root item so no clipping ancestor (the dial strip) cuts it off.
    Item {
        id: ghost
        parent: root.Window.window ? root.Window.window.contentItem : root
        visible: root.dragging
        z: 1000
        width: root.glyph + 4
        height: width
        x: drag_handler.centroid.scenePosition.x - width / 2
        y: drag_handler.centroid.scenePosition.y - height / 2

        Drag.source: root
        Drag.keys: ["bar-window"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        IconImage {
            anchors.centerIn: parent
            implicitSize: root.glyph
            opacity: 0.9
            source: WindowState.icon_for(root.modelData)
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered && !root.dragging) Tooltip.show(root, root.modelData.title, root.host.name_of(root.modelData));
            else Tooltip.hide(root);
        }
    }
}
