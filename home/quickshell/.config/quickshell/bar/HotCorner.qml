// home/quickshell/.config/quickshell/bar/HotCorner.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../lock"
import "../services"

// A tiny overlay square in a top corner: resting the pointer there opens the overview (left) or notifications (right).
PanelWindow {
    id: root

    property bool right: false
    property var overview: null

    readonly property int dwell_ms: 250
    readonly property var monitor: Hyprland.monitorFor(root.screen)
    property bool fired: false

    function fullscreen_here() {
        const ws = root.monitor ? root.monitor.activeWorkspace : null;
        return !!ws && !!ws.lastIpcObject && !!ws.lastIpcObject.hasfullscreen;
    }

    function fire() {
        if (root.fullscreen_here()) return;
        if (root.right) {
            if ((!root.overview || !root.overview.wanted) && Popups.find_default("notifications")) Popups.open("notifications", undefined);
        } else if (root.overview) {
            root.overview.show_overview();
        }
    }

    visible: HotCorners.enabled && !Lock.locked
    color: "transparent"
    implicitWidth: 3
    implicitHeight: 3
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.left: !root.right
    anchors.right: root.right
    WlrLayershell.namespace: "quickshell-hotcorner"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hover.hovered) {
                Hyprland.refreshWorkspaces();
                dwell.restart();
            } else {
                dwell.stop();
                // The overview covering the corner is not a real leave; closing it must not refire.
                if (!root.overview || !root.overview.wanted) root.fired = false;
            }
        }
    }

    Timer {
        id: dwell
        interval: root.dwell_ms
        onTriggered: {
            if (root.fired || !hover.hovered) return;
            root.fired = true;
            root.fire();
        }
    }
}
