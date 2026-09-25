// home/quickshell/.config/quickshell/components/WorkspaceIcon.qml
import QtQuick
import Quickshell.Widgets
import "../services"

// An app on a bar workspace: click focuses its window, middle-click closes it, hover shows its title; `host` is the Workspaces module.
Item {
    id: root

    required property var modelData
    property var host: null
    property int workspace_id: 0
    property real glyph: 16
    property real icon_opacity: 1
    // Art drawn under the icon, e.g. a materia slot.
    default property alias underlay: under.data

    width: root.glyph
    height: root.glyph

    Item {
        id: under
        anchors.fill: parent
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: root.glyph
        opacity: root.icon_opacity
        source: root.host ? root.host.icon_for(root.host.class_of(root.modelData)) : ""
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) root.host.focus_toplevel(root.workspace_id, root.modelData.address);
            else root.host.close_toplevel(root.modelData.address);
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.modelData.title, root.host.name_of(root.modelData));
            else Tooltip.hide(root);
        }
    }
}
