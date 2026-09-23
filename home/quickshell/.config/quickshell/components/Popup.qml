// home/quickshell/.config/quickshell/components/Popup.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../services"

PopupWindow {
    id: root

    property string popup_name: ""
    default property alias content: content_scope.data

    color: "transparent"
    visible: Popups.open_name === root.popup_name

    anchor.item: Popups.open_anchor
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.SlideX | PopupAdjustment.FlipY

    // Reads as the island unfolding downward: its color, joined flush at the top.
    Rectangle {
        anchors.fill: parent
        color: Popups.open_color
        bottomLeftRadius: 10
        bottomRightRadius: 10
    }

    FocusScope {
        id: content_scope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Popups.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Q) {
                Popups.close();
                event.accepted = true;
            }
        }
    }

    HyprlandFocusGrab {
        id: focus_grab
        windows: [root]
        onCleared: Popups.close()
    }

    // Grabbing before the backing surface is mapped is a no-op, so defer one tick.
    onVisibleChanged: {
        if (visible) {
            content_scope.forceActiveFocus();
            Qt.callLater(() => focus_grab.active = root.visible);
        } else {
            focus_grab.active = false;
        }
    }
}
