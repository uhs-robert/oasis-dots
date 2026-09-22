// home/quickshell/.config/quickshell/components/Popup.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../services"

PopupWindow {
    id: root

    property string popup_name: ""

    color: "transparent"
    visible: Popups.open_name === root.popup_name

    anchor.item: Popups.open_anchor
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY

    Item {
        id: key_handler
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Popups.close()
    }

    HyprlandFocusGrab {
        id: focus_grab
        windows: [root]
        onCleared: Popups.close()
    }

    // Grabbing before the backing surface is mapped is a no-op, so defer one tick.
    onVisibleChanged: {
        if (visible) {
            key_handler.forceActiveFocus();
            Qt.callLater(() => focus_grab.active = root.visible);
        } else {
            focus_grab.active = false;
        }
    }
}
