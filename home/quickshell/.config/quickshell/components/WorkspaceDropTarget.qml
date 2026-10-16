// home/quickshell/.config/quickshell/components/WorkspaceDropTarget.qml
import QtQuick
import "../theme"
import "../services"

// A bar workspace that takes a dragged WorkspaceIcon: lights while one hovers over it and moves that window here on drop, without following it.
DropArea {
    id: root

    required property int workspace_id
    property real radius: 0

    // The window's own workspace is no target, so it never lights.
    readonly property bool armed: root.containsDrag && !!root.drag.source && root.drag.source.workspace_id !== root.workspace_id

    keys: ["bar-window"]

    onDropped: drop => {
        if (drop.source.workspace_id === root.workspace_id) return;
        WindowState.move_to_workspace(drop.source.window_address, root.workspace_id, false);
        drop.accept();
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.armed
        color: Qt.alpha(Theme.theme_primary, 0.25)
        border.width: 1
        border.color: Theme.theme_primary
    }
}
